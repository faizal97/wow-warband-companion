import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/character.dart';
import '../../theme/wow_class_colors.dart';
import '../data/effect_types.dart';
import '../data/td_balance_config.dart';
import '../effects/tower_effects.dart';

// ---------------------------------------------------------------------------
// TdTower — a WoW character placed in a lane
// ---------------------------------------------------------------------------

/// A tower is a WoW character placed in a lane. Its stats are derived from
/// the character's class definition and item level.
class TdTower {
  final WowCharacter character;
  final TdClassDef classDef;
  int laneIndex;

  /// Position slot within the lane: 0=front (near spawn), 1=mid, 2=back (near goal).
  /// -1 means unassigned.
  int slotIndex;

  /// Slot positions along the lane (0.0=spawn, 1.0=goal).
  static const List<double> slotPositions = [0.25, 0.55, 0.85];

  /// The tower's position along the lane based on its slot.
  double get slotPosition =>
      slotIndex >= 0 && slotIndex < slotPositions.length
          ? slotPositions[slotIndex]
          : 0.85; // default to back if unassigned

  // Derived from classDef
  TowerArchetype get archetype => classDef.archetype;
  Color get color => WowClassColors.forClass(character.characterClass);
  Color get attackColor => classDef.attackColor;
  String get passiveName => classDef.passive.name;
  String get passiveDescription => classDef.passive.description;

  /// Derived from [character.equippedItemLevel] (defaults to 600).
  final double baseDamage;

  // Mutable combat state

  /// Whether the tower is currently debuffed (e.g. by Bursting).
  bool isDebuffed = false;

  /// Remaining debuff duration in seconds.
  double debuffTimer = 0;

  /// Total attacks this tower has made (for on_nth_attack tracking).
  int attackCount = 0;

  /// Seconds elapsed since last charge began (for charge_attack effect).
  double chargeTimer = 0;

  // ---- Active ability state ----

  /// Remaining cooldown for the active ability (seconds).
  double activeCooldownRemaining = 0;

  /// True while a channeled/timed active ability is running.
  bool activeAbilityActive = false;

  /// Remaining duration of active ability effect.
  double activeAbilityTimer = 0;

  // ---- Ultimate ability state ----

  /// Current ultimate charge (0 to charge.max).
  int ultimateCharge = 0;

  /// True while a timed ultimate effect is running.
  bool ultimateActive = false;

  /// Remaining duration of ultimate effect.
  double ultimateTimer = 0;

  /// Timer for on_time charge trigger.
  double ultimateChargeTickTimer = 0;

  // ---- Ability buffs ----

  /// Temporary buffs applied by abilities (damage mult, speed, immunity, etc.).
  List<TowerAbilityBuff> abilityBuffs = [];

  /// Whether this tower is in stealth (immune to enemy targeting).
  bool isStealthed = false;

  /// Remaining stealth duration.
  double stealthTimer = 0;

  /// Empowered next attack (from Vanish→Ambush etc.).
  double? empoweredNextAttackMult;
  double? empoweredNextAttackStun;

  /// Combo point tracker (for Shadow Blades).
  int comboPoints = 0;

  // ---- Shapeshift state ----
  /// Current shapeshift form name (null = base form).
  String? currentForm;
  /// Remaining shapeshift duration.
  double shapeshiftTimer = 0;

  // ---- Convenience getters ----

  AbilityDef? get activeAbility => classDef.activeAbility;
  AbilityDef? get ultimateAbility => classDef.ultimateAbility;

  bool get canUseActive =>
      activeAbility != null &&
      activeCooldownRemaining <= 0 &&
      !activeAbilityActive;

  bool get canUseUltimate =>
      ultimateAbility != null &&
      ultimateAbility!.charge != null &&
      ultimateCharge >= ultimateAbility!.charge!.max &&
      !ultimateActive;

  double get ultimateChargeProgress => ultimateAbility?.charge != null
      ? (ultimateCharge / ultimateAbility!.charge!.max).clamp(0.0, 1.0)
      : 0.0;

  /// Initialize ability cooldowns at wave start.
  /// On wave 1 (first call), applies initial cooldown penalty.
  /// On subsequent waves, carries over remaining cooldown from previous wave.
  bool _abilitiesInitialized = false;

  void initAbilityCooldowns() {
    if (!_abilitiesInitialized) {
      // First wave: start on full cooldown (must wait before first use)
      _abilitiesInitialized = true;
      if (activeAbility != null) {
        activeCooldownRemaining = activeAbility!.cooldown;
      }
    }
    // Subsequent waves: cooldown, active effects, and charge all carry over.
  }

  /// Add a charge to the ultimate if the trigger matches.
  void addUltimateCharge(String trigger, {int amount = 0}) {
    final ult = ultimateAbility;
    if (ult == null || ult.charge == null) return;
    if (ult.charge!.trigger != trigger) return;
    final gain = amount > 0 ? amount : ult.charge!.amount;
    ultimateCharge = (ultimateCharge + gain).clamp(0, ult.charge!.max);
  }

  /// Get the effective damage multiplier from active ability buffs.
  double get abilityDamageMultiplier {
    var mult = 1.0;
    for (final buff in abilityBuffs) {
      if (buff.type == 'damage_multiplier') mult *= buff.value;
    }
    if (empoweredNextAttackMult != null) {
      mult *= empoweredNextAttackMult!;
    }
    return mult;
  }

  /// Get the effective attack speed multiplier from ability buffs.
  double get abilitySpeedMultiplier {
    var mult = 1.0;
    for (final buff in abilityBuffs) {
      if (buff.type == 'attack_speed_multiplier') mult *= buff.value;
    }
    return mult;
  }

  /// Whether this tower currently has guaranteed crit from an ability.
  bool get hasAbilityGuaranteedCrit {
    return abilityBuffs.any((b) => b.type == 'guaranteed_crit');
  }

  /// Get the guaranteed crit multiplier (from ability buff).
  double get abilityCritMultiplier {
    for (final buff in abilityBuffs) {
      if (buff.type == 'guaranteed_crit') return buff.value;
    }
    return 2.0;
  }

  /// Whether this tower is immune to debuffs (from ability buff or passive).
  bool get isAbilityImmuneToDebuff {
    return abilityBuffs.any((b) => b.type == 'immune_to_debuff');
  }

  TdTower({
    required this.character,
    required this.classDef,
    required this.laneIndex,
    this.slotIndex = -1,
  }) : baseDamage = _normalizedDamage(character.equippedItemLevel);

  /// Normalize ilvl to a consistent damage value regardless of stat squish.
  /// Pre-Midnight ilvl ~560-640 and post-Midnight ilvl ~80-120 both map
  /// to a 40-70 damage range. Higher ilvl = more damage within the range.
  static double _normalizedDamage(int? ilvl) {
    final raw = ilvl ?? 100;
    if (raw > 300) {
      // Pre-squish: 560-640 maps to 40-70
      return 40 + ((raw - 500).clamp(0, 200) / 200) * 30;
    } else {
      // Post-squish (Midnight): 80-120 maps to 40-70
      return 40 + ((raw - 60).clamp(0, 80) / 80) * 30;
    }
  }

  /// Returns half damage when debuffed.
  double get effectiveDamage => isDebuffed ? baseDamage / 2 : baseDamage;

  /// Seconds between attacks — varies by archetype, modified by passive effects.
  /// Uses values from [TdBalanceConfig] if provided.
  double attackIntervalWith(TdBalanceConfig config) {
    double base;
    switch (archetype) {
      case TowerArchetype.melee:
        base = config.meleeAttackInterval;
      case TowerArchetype.ranged:
        base = config.rangedAttackInterval;
      case TowerArchetype.support:
        base = config.supportAttackInterval;
      case TowerArchetype.aoe:
        base = config.aoeAttackInterval;
    }
    for (final effect in classDef.passive.effects) {
      if (effect.type == 'attack_speed_multiplier') {
        base *= effect.value;
      }
    }
    return base;
  }

  /// Convenience getter using default config.
  double get attackInterval => attackIntervalWith(TdBalanceConfig.defaults);

  /// Check if this tower is immune to a specific affix.
  bool isImmuneToAffix(String affixName) {
    for (final effect in classDef.passive.effects) {
      // immune_to_debuff = immune to ALL tower debuffs (Paladin)
      if (effect.type == 'immune_to_debuff') return true;
      if (effect.type == 'immune_to_affix' &&
          effect.params['affix'] == affixName) {
        return true;
      }
    }
    return false;
  }

  /// Check if this tower is immune to all debuffs (e.g. Paladin).
  bool get isImmuneToDebuff {
    for (final effect in classDef.passive.effects) {
      if (effect.type == 'immune_to_debuff') return true;
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// TowerAbilityBuff — temporary buff from an ability
// ---------------------------------------------------------------------------

/// A temporary buff applied to a tower by an ability (active or ultimate).
class TowerAbilityBuff {
  /// Buff type: "damage_multiplier", "attack_speed_multiplier",
  /// "immune_to_debuff", "immune_to_damage", "guaranteed_crit",
  /// "cross_lane_attack".
  final String type;
  final double value;
  double remaining; // seconds left

  TowerAbilityBuff({
    required this.type,
    required this.value,
    required this.remaining,
  });

  bool get isExpired => remaining <= 0;
}

// ---------------------------------------------------------------------------
// SummonedPet — autonomous attacking entity from abilities
// ---------------------------------------------------------------------------

/// A pet summoned by an ability (e.g. Bestial Wrath, Summon Infernal).
class SummonedPet {
  final int ownerTowerIndex;
  final String targeting; // "furthest_any_lane", "all_in_lane"
  final double attackInterval;
  final double damageMultiplier;
  final double baseDamage;
  double remaining;
  double cooldown;
  int? laneIndex; // for lane-specific pets

  SummonedPet({
    required this.ownerTowerIndex,
    required this.targeting,
    required this.attackInterval,
    required this.damageMultiplier,
    required this.baseDamage,
    required this.remaining,
    this.laneIndex,
  }) : cooldown = 0;

  bool get isExpired => remaining <= 0;
}

// ---------------------------------------------------------------------------
// LaneBlock — blocks enemy movement in a lane
// ---------------------------------------------------------------------------

/// Blocks enemy movement in a lane for a duration (Army of the Dead).
class LaneBlock {
  final int laneIndex;
  double remaining;

  LaneBlock({required this.laneIndex, required this.remaining});
  bool get isExpired => remaining <= 0;
}

// ---------------------------------------------------------------------------
// BurnZone — persistent ground damage zone from abilities
// ---------------------------------------------------------------------------

/// A burn zone left by Meteor or similar abilities.
class BurnZone {
  final int laneIndex;
  final double damagePerTick;
  final double tickInterval;
  double remaining;
  double tickCooldown;

  BurnZone({
    required this.laneIndex,
    required this.damagePerTick,
    required this.tickInterval,
    required this.remaining,
  }) : tickCooldown = 0;

  bool get isExpired => remaining <= 0;
}

// ---------------------------------------------------------------------------
// TdEnemy — an enemy moving across a lane
// ---------------------------------------------------------------------------

/// An enemy that spawns at position 0.0 and moves toward 1.0 (the goal).
class TdEnemy {
  final String id;
  final double maxHp;
  double hp;

  /// Progress along the lane: 0.0 = spawn, 1.0 = goal reached.
  double position;

  /// Movement speed in position-units per second.
  final double speed;

  /// The lane this enemy is in. Mutable because lane_switch modifier can
  /// change it mid-run.
  int laneIndex;

  final bool isBoss;

  /// Multiplier applied to [speed] (e.g. by affixes).
  double speedMultiplier;

  // Effect system additions

  /// Modifiers from dungeon definition (e.g. shield, phase, lane_switch).
  final List<EffectDef> modifiers;

  /// Mutable state for modifiers (e.g. shield_hits, phase_invuln).
  final Map<String, dynamic> modifierState;

  /// Active slows, dots, and other debuffs on this enemy.
  List<EnemyStatusEffect> statusEffects;

  TdEnemy({
    required this.id,
    required this.maxHp,
    required this.speed,
    required this.laneIndex,
    this.isBoss = false,
    this.speedMultiplier = 1.0,
    this.modifiers = const [],
    Map<String, dynamic>? modifierState,
  })  : hp = maxHp,
        position = 0.0,
        modifierState = modifierState ?? {},
        statusEffects = [];

  bool get isDead => hp <= 0;
  bool get reachedEnd => position >= 1.0;
  double get hpFraction => (hp / maxHp).clamp(0, 1);

  /// Whether the enemy is currently invulnerable (phase modifier).
  bool get isInvulnerable => modifierState['phase_invuln'] == true;

  /// Remaining shield hits (shield modifier).
  int get shieldHits => (modifierState['shield_hits'] as int?) ?? 0;
}

// ---------------------------------------------------------------------------
// SanguinePool — heal zone left behind by a dying enemy
// ---------------------------------------------------------------------------

/// A healing pool dropped by the Sanguine affix. Heals nearby enemies until
/// the timer expires.
class SanguinePool {
  final int laneIndex;
  final double position;

  /// Time remaining in seconds before the pool disappears.
  double timer;

  SanguinePool({
    required this.laneIndex,
    required this.position,
    this.timer = 4.0,
  });

  bool get isExpired => timer <= 0;
}

// ---------------------------------------------------------------------------
// TdHitEvent — visual hit event for rendering
// ---------------------------------------------------------------------------

/// A visual hit event emitted when a tower attacks an enemy.
class TdHitEvent {
  final int towerLane;
  final double towerX; // 0.0–1.0 normalized position
  final String enemyId;
  final int enemyLane;
  final double enemyX;
  final double damage;
  final bool isAoe;
  final TowerArchetype archetype; // for per-archetype visual
  final Color attackColor; // class-colored attack
  final bool isCrit; // for crit visual
  double age; // seconds since creation

  TdHitEvent({
    required this.towerLane,
    required this.towerX,
    required this.enemyId,
    required this.enemyLane,
    required this.enemyX,
    required this.damage,
    this.isAoe = false,
    this.archetype = TowerArchetype.melee,
    this.attackColor = const Color(0xFFFFD700),
    this.isCrit = false,
    this.age = 0,
  });

  /// How long the particle lives (seconds).
  static const double lifetime = 0.4;
  bool get isExpired => age >= lifetime;

  /// 0.0 → 1.0 progress through the animation.
  double get progress => (age / lifetime).clamp(0, 1);
}

// ---------------------------------------------------------------------------
// TdAffix — Mythic+ affixes that modify gameplay
// ---------------------------------------------------------------------------

/// Mythic+ affixes that alter tower-defense gameplay.
enum TdAffix { fortified, tyrannical, bolstering, bursting, sanguine }

// ---------------------------------------------------------------------------
// FireZone — fire_zone boss mechanic
// ---------------------------------------------------------------------------

/// A fire zone spawned by a boss ability. Damages towers in the lane until
/// the timer expires.
class FireZone {
  final int laneIndex;
  double timer;

  FireZone({required this.laneIndex, required this.timer});

  bool get isExpired => timer <= 0;
}

// ---------------------------------------------------------------------------
// KeystoneRun — configuration for a single run
// ---------------------------------------------------------------------------

/// Describes the parameters of a keystone run: level, affixes, and dungeon.
class KeystoneRun {
  final int level;
  final List<TdAffix> affixes;
  final TdDungeonDef dungeon;

  String get dungeonName => dungeon.name;

  const KeystoneRun({
    required this.level,
    required this.affixes,
    required this.dungeon,
  });

  /// Enemy HP multiplier based on keystone level.
  /// Uses config for scaling coefficients.
  double hpMultiplierWith(TdBalanceConfig config) {
    if (level <= config.linearPhaseEnd) {
      return 1.0 + (level - 2) * config.linearRate;
    }
    final over = level - config.linearPhaseEnd;
    return config.exponentialBase + over * config.exponentialLinear + over * over * config.exponentialQuadratic;
  }

  /// Convenience getter using default config.
  double get hpMultiplier => hpMultiplierWith(TdBalanceConfig.defaults);

  bool get hasFortified => affixes.contains(TdAffix.fortified);
  bool get hasTyrannical => affixes.contains(TdAffix.tyrannical);
  bool get hasBolstering => affixes.contains(TdAffix.bolstering);
  bool get hasBursting => affixes.contains(TdAffix.bursting);
  bool get hasSanguine => affixes.contains(TdAffix.sanguine);

  /// Generates a random keystone run for the given [level] and [dungeon].
  static KeystoneRun generate(int level, {
    required TdDungeonDef dungeon,
    TdBalanceConfig config = TdBalanceConfig.defaults,
  }) {
    final rng = Random();
    final allAffixes = List<TdAffix>.from(TdAffix.values)..shuffle(rng);
    final count = level >= config.threeAffixLevel
        ? 3
        : level >= config.twoAffixLevel
            ? 2
            : level >= config.oneAffixLevel
                ? 1
                : 0;
    return KeystoneRun(
      level: level,
      affixes: allAffixes.take(count).toList(),
      dungeon: dungeon,
    );
  }
}
