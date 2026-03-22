import 'dart:math';
import '../data/effect_types.dart';

// ---------------------------------------------------------------------------
// EnemyStatusEffect — active debuff/dot on an enemy
// ---------------------------------------------------------------------------

/// An active debuff or damage-over-time effect applied to an enemy.
class EnemyStatusEffect {
  final String type; // "slow", "dot"
  final String sourceId; // which tower applied it (for stacking rules)
  final Map<String, dynamic> params;
  double remaining; // seconds left

  EnemyStatusEffect({
    required this.type,
    required this.sourceId,
    required this.params,
    required this.remaining,
  });

  /// For slow: speed reduction fraction (0.0–1.0).
  double get slowAmount => (params['value'] as num?)?.toDouble() ?? 0;

  /// For dot: damage per tick.
  double get dotDamage => (params['dotDamage'] as num?)?.toDouble() ?? 0;

  /// For dot: seconds between ticks.
  double get tickInterval => (params['tickInterval'] as num?)?.toDouble() ?? 1;
}

// ---------------------------------------------------------------------------
// TowerHit — a single damage event against one enemy
// ---------------------------------------------------------------------------

/// Describes a single hit dealt by a tower to an enemy.
class TowerHit {
  final String enemyId;
  final double damage;
  final int enemyLane;
  final double enemyPosition;

  const TowerHit({
    required this.enemyId,
    required this.damage,
    required this.enemyLane,
    required this.enemyPosition,
  });
}

// ---------------------------------------------------------------------------
// AttackResult — aggregate result of a tower's attack cycle
// ---------------------------------------------------------------------------

/// The outcome of a single tower attack, including all hits and new debuffs.
class AttackResult {
  final List<TowerHit> hits;
  final List<EnemyStatusEffect> newStatusEffects;
  final bool isCharging; // true if tower is still charging (Evoker)
  final bool didCrit;

  const AttackResult({
    this.hits = const [],
    this.newStatusEffects = const [],
    this.isCharging = false,
    this.didCrit = false,
  });
}

// ---------------------------------------------------------------------------
// TowerEffectProcessor — processes tower attacks with all passive effects
// ---------------------------------------------------------------------------

/// Processes a tower's attack by applying archetype targeting, passive effects,
/// and nth-attack triggers.  Returns an [AttackResult] describing what happened.
///
/// This class is intentionally independent of td_models / td_game_state so it
/// can be tested and reasoned about in isolation.
class TowerEffectProcessor {
  /// Process a single attack for a tower.
  ///
  /// [archetype] — the tower's archetype (melee/ranged/support/aoe).
  /// [classDef] — full class definition (includes passive effects).
  /// [towerLane] — the lane index the tower occupies.
  /// [enemies] — all enemies currently alive, as lightweight records.
  /// [baseDamage] — pre-computed base damage (archetype multipliers already applied).
  /// [attackCount] — total attacks this tower has made (for on_nth_attack).
  /// [chargeTimer] — seconds elapsed since last charge began (for charge_attack).
  /// [dt] — delta time since the last frame / tick.
  /// [rng] — random number generator (injectable for deterministic tests).
  static AttackResult processAttack({
    required TowerArchetype archetype,
    required TdClassDef classDef,
    required int towerLane,
    required List<({String id, double hp, double position, int lane})> enemies,
    required double baseDamage,
    required int attackCount,
    required double chargeTimer,
    required double dt,
    required Random rng,
  }) {
    // -- 0. Support towers don't attack ---------------------------------------
    if (archetype == TowerArchetype.support) {
      return const AttackResult();
    }

    // Gather all passive effects from the class definition.
    final passiveEffects = classDef.passive.effects;
    final trigger = classDef.passive.trigger;

    // -- 1. Check charge_attack -----------------------------------------------
    final chargeEffect = _findEffect(passiveEffects, 'charge_attack');
    if (chargeEffect != null) {
      final chargeTime =
          (chargeEffect.params['chargeTime'] as num?)?.toDouble() ?? 3.0;
      if (chargeTimer < chargeTime) {
        return const AttackResult(isCharging: true);
      }
      // Charge complete — multiplier applied below alongside other multipliers.
    }

    // -- 2. Determine which effects are active this attack --------------------
    //    on_attack  → always active
    //    on_nth_attack → only when attackCount % nth == 0
    //    passive → some are handled here, some are handled externally
    final activeEffects = <EffectDef>[];
    if (trigger == 'on_attack') {
      activeEffects.addAll(passiveEffects);
    } else if (trigger == 'on_nth_attack') {
      final nth = classDef.passive.nth > 0
          ? classDef.passive.nth
          : _nthFromEffects(passiveEffects);
      if (nth > 0 && attackCount > 0 && attackCount % nth == 0) {
        activeEffects.addAll(passiveEffects);
      }
    } else if (trigger == 'passive') {
      // Passive effects that influence targeting (cross_lane_attack,
      // charge_attack) are handled here. Others (buff_adjacent_*,
      // attack_speed_multiplier, immune_to_affix) are handled externally.
      activeEffects.addAll(passiveEffects);
    }

    // -- 3. Expand enemy pool for cross_lane_attack ---------------------------
    final crossLane = _findEffect(activeEffects, 'cross_lane_attack');
    final int crossLaneRange = crossLane?.value.toInt() ?? 0;

    var candidateEnemies = enemies.where((e) {
      if (crossLaneRange > 0) {
        return (e.lane - towerLane).abs() <= crossLaneRange;
      }
      return e.lane == towerLane;
    }).toList();

    if (candidateEnemies.isEmpty) {
      return const AttackResult();
    }

    // -- 4. Check for chain_damage (overrides normal targeting) ----------------
    final chainEffect = _findEffect(activeEffects, 'chain_damage');
    if (chainEffect != null) {
      return _processChainDamage(
        chainEffect: chainEffect,
        enemies: candidateEnemies,
        baseDamage: baseDamage,
        towerLane: towerLane,
        activeEffects: activeEffects,
        chargeEffect: chargeEffect,
        rng: rng,
      );
    }

    // -- 5. Normal targeting based on archetype --------------------------------
    List<({String id, double hp, double position, int lane})> targets;
    switch (archetype) {
      case TowerArchetype.melee:
        // Closest to goal = highest position value.
        candidateEnemies.sort((a, b) => b.position.compareTo(a.position));
        targets = [candidateEnemies.first];
      case TowerArchetype.ranged:
        // Furthest from goal = lowest position value.
        candidateEnemies.sort((a, b) => a.position.compareTo(b.position));
        targets = [candidateEnemies.first];
      case TowerArchetype.aoe:
        // All enemies in the lane(s).
        targets = List.of(candidateEnemies);
      case TowerArchetype.support:
        // Already handled above, but satisfy exhaustiveness.
        return const AttackResult();
    }

    // -- 6. Apply extra_targets -----------------------------------------------
    final extraTargets = _findEffect(activeEffects, 'extra_targets');
    if (extraTargets != null && targets.length == 1) {
      final extraCount = extraTargets.value.toInt();
      final remaining =
          candidateEnemies.where((e) => e.id != targets.first.id).toList();

      // For melee: remaining is already sorted by position DESC (closest first).
      // For ranged: remaining is already sorted by position ASC (furthest first).
      // Either way, the sort from step 5 carries over.
      for (var i = 0; i < extraCount && i < remaining.length; i++) {
        targets.add(remaining[i]);
      }
    }

    // -- 7. Compute damage multipliers ----------------------------------------
    double damage = baseDamage;
    bool didCrit = false;

    // charge_attack multiplier
    if (chargeEffect != null) {
      damage *= chargeEffect.multiplier;
    }

    // damage_multiplier effects
    for (final eff in activeEffects) {
      if (eff.type == 'damage_multiplier') {
        damage *= eff.value;
      }
    }

    // crit_chance
    final critEffect = _findEffect(activeEffects, 'crit_chance');
    if (critEffect != null) {
      if (rng.nextDouble() < critEffect.chance) {
        damage *= critEffect.multiplier;
        didCrit = true;
      }
    }

    // -- 8. Build hits --------------------------------------------------------
    final hits = targets
        .map((e) => TowerHit(
              enemyId: e.id,
              damage: damage,
              enemyLane: e.lane,
              enemyPosition: e.position,
            ))
        .toList();

    // -- 9. Build status effects (slow, dot) ----------------------------------
    final statusEffects = <EnemyStatusEffect>[];

    for (final eff in activeEffects) {
      if (eff.type == 'slow_enemy') {
        for (final _ in targets) {
          statusEffects.add(EnemyStatusEffect(
            type: 'slow',
            sourceId: classDef.name,
            params: {'value': eff.value},
            remaining: eff.duration,
          ));
        }
      } else if (eff.type == 'dot') {
        final percentDamage = eff.value;
        final duration = eff.duration;
        final ticks = (eff.params['ticks'] as num?)?.toInt() ?? 3;
        final dotDamage = baseDamage * percentDamage;
        final tickInterval = ticks > 0 ? duration / ticks : 1.0;

        for (final _ in targets) {
          statusEffects.add(EnemyStatusEffect(
            type: 'dot',
            sourceId: classDef.name,
            params: {
              'dotDamage': dotDamage,
              'tickInterval': tickInterval,
            },
            remaining: duration,
          ));
        }
      }
      // Unknown effect types are silently skipped.
    }

    return AttackResult(
      hits: hits,
      newStatusEffects: statusEffects,
      didCrit: didCrit,
    );
  }

  // ---------------------------------------------------------------------------
  // Chain damage — overrides normal targeting
  // ---------------------------------------------------------------------------

  static AttackResult _processChainDamage({
    required EffectDef chainEffect,
    required List<({String id, double hp, double position, int lane})> enemies,
    required double baseDamage,
    required int towerLane,
    required List<EffectDef> activeEffects,
    required EffectDef? chargeEffect,
    required Random rng,
  }) {
    final bounces = (chainEffect.params['bounces'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [1.0];

    // Sort all candidates by position DESC (closest to goal first).
    enemies.sort((a, b) => b.position.compareTo(a.position));

    double damage = baseDamage;
    bool didCrit = false;

    // Apply charge multiplier if applicable.
    if (chargeEffect != null) {
      damage *= chargeEffect.multiplier;
    }

    // Apply damage_multiplier effects.
    for (final eff in activeEffects) {
      if (eff.type == 'damage_multiplier') {
        damage *= eff.value;
      }
    }

    // Apply crit chance.
    final critEffect = _findEffect(activeEffects, 'crit_chance');
    if (critEffect != null) {
      if (rng.nextDouble() < critEffect.chance) {
        damage *= critEffect.multiplier;
        didCrit = true;
      }
    }

    final hits = <TowerHit>[];
    for (var i = 0; i < bounces.length && i < enemies.length; i++) {
      final e = enemies[i];
      hits.add(TowerHit(
        enemyId: e.id,
        damage: damage * bounces[i],
        enemyLane: e.lane,
        enemyPosition: e.position,
      ));
    }

    return AttackResult(
      hits: hits,
      didCrit: didCrit,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Find the first effect of a given [type] in the list, or null.
  static EffectDef? _findEffect(List<EffectDef> effects, String type) {
    for (final e in effects) {
      if (e.type == type) return e;
    }
    return null;
  }

  /// Extract the "nth" value from effect params when the PassiveDef.nth is 0.
  static int _nthFromEffects(List<EffectDef> effects) {
    for (final e in effects) {
      final n = (e.params['nth'] as num?)?.toInt() ?? 0;
      if (n > 0) return n;
    }
    return 0;
  }
}
