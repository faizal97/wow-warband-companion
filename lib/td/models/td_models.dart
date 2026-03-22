import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/character.dart';
import '../../theme/wow_class_colors.dart';

// ---------------------------------------------------------------------------
// Tower Archetype
// ---------------------------------------------------------------------------

/// Determines a tower's attack style based on the WoW class it represents.
enum TowerArchetype { melee, ranged, healer, aoe }

/// Maps a WoW class name to its tower archetype.
TowerArchetype archetypeForClass(String characterClass) {
  switch (characterClass.toLowerCase()) {
    case 'warrior':
    case 'rogue':
    case 'death knight':
    case 'paladin':
    case 'monk':
    case 'demon hunter':
      return TowerArchetype.melee;
    case 'mage':
    case 'hunter':
    case 'warlock':
    case 'evoker':
      return TowerArchetype.ranged;
    case 'priest':
    case 'druid':
      return TowerArchetype.healer;
    case 'shaman':
      return TowerArchetype.aoe;
    default:
      return TowerArchetype.melee;
  }
}

// ---------------------------------------------------------------------------
// TdTower — a WoW character placed in a lane
// ---------------------------------------------------------------------------

/// A tower is a WoW character placed in a lane. Its stats are derived from
/// the character's class and item level.
class TdTower {
  final WowCharacter character;
  final int laneIndex;

  /// Derived from [character.characterClass].
  final TowerArchetype archetype;

  /// Derived from [character.equippedItemLevel] (defaults to 600).
  final double baseDamage;

  /// Derived from [WowClassColors.forClass].
  final Color color;

  /// Whether the tower is currently debuffed (e.g. by Bursting).
  bool isDebuffed = false;

  /// Remaining debuff duration in seconds.
  double debuffTimer = 0;

  TdTower({required this.character, required this.laneIndex})
      : archetype = archetypeForClass(character.characterClass),
        baseDamage = (character.equippedItemLevel ?? 600) / 10.0,
        color = WowClassColors.forClass(character.characterClass);

  /// Returns half damage when debuffed.
  double get effectiveDamage => isDebuffed ? baseDamage / 2 : baseDamage;

  /// Seconds between attacks — varies by archetype.
  double get attackInterval {
    switch (archetype) {
      case TowerArchetype.melee:
        return 0.8;
      case TowerArchetype.ranged:
        return 1.2;
      case TowerArchetype.healer:
        return 2.0;
      case TowerArchetype.aoe:
        return 1.5;
    }
  }
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

  final int laneIndex;
  final bool isBoss;

  /// Multiplier applied to [speed] (e.g. by affixes).
  double speedMultiplier;

  TdEnemy({
    required this.id,
    required this.maxHp,
    required this.speed,
    required this.laneIndex,
    this.isBoss = false,
    this.speedMultiplier = 1.0,
  })  : hp = maxHp,
        position = 0.0;

  bool get isDead => hp <= 0;
  bool get reachedEnd => position >= 1.0;
  double get hpFraction => hp / maxHp;
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
// TdAffix — Mythic+ affixes that modify gameplay
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
  double age; // seconds since creation

  TdHitEvent({
    required this.towerLane,
    required this.towerX,
    required this.enemyId,
    required this.enemyLane,
    required this.enemyX,
    required this.damage,
    this.isAoe = false,
    this.age = 0,
  });

  /// How long the particle lives (seconds).
  static const double lifetime = 0.4;
  bool get isExpired => age >= lifetime;
  /// 0.0 → 1.0 progress through the animation.
  double get progress => (age / lifetime).clamp(0, 1);
}

/// Mythic+ affixes that alter tower-defense gameplay.
enum TdAffix { fortified, tyrannical, bolstering, bursting, sanguine }

// ---------------------------------------------------------------------------
// TdDungeon — dungeon definitions with themed enemy visuals
// ---------------------------------------------------------------------------

/// A dungeon available for tower defense runs.
class TdDungeon {
  final String name;
  final String shortName;
  final Color enemyColor;
  final Color bossColor;
  final IconData enemyIcon;
  final IconData bossIcon;

  const TdDungeon({
    required this.name,
    required this.shortName,
    required this.enemyColor,
    required this.bossColor,
    required this.enemyIcon,
    required this.bossIcon,
  });

  /// Hand-themed dungeons we know about.
  static const Map<String, TdDungeon> _known = {
    'Stonevault': TdDungeon(name: 'Stonevault', shortName: 'SV',
        enemyColor: Color(0xFF8B7355), bossColor: Color(0xFFFF8000),
        enemyIcon: Icons.terrain_rounded, bossIcon: Icons.local_fire_department),
    'City of Threads': TdDungeon(name: 'City of Threads', shortName: 'CoT',
        enemyColor: Color(0xFF7B68EE), bossColor: Color(0xFFA335EE),
        enemyIcon: Icons.bug_report_rounded, bossIcon: Icons.pest_control_rounded),
    'The Dawnbreaker': TdDungeon(name: 'The Dawnbreaker', shortName: 'DB',
        enemyColor: Color(0xFF4169E1), bossColor: Color(0xFF6A0DAD),
        enemyIcon: Icons.dark_mode_rounded, bossIcon: Icons.auto_awesome_rounded),
    'Ara-Kara, City of Echoes': TdDungeon(name: 'Ara-Kara', shortName: 'AK',
        enemyColor: Color(0xFF2E8B57), bossColor: Color(0xFF006400),
        enemyIcon: Icons.coronavirus_rounded, bossIcon: Icons.pest_control_rounded),
    'Cinderbrew Meadery': TdDungeon(name: 'Cinderbrew Meadery', shortName: 'CM',
        enemyColor: Color(0xFFCD853F), bossColor: Color(0xFFB22222),
        enemyIcon: Icons.local_bar_rounded, bossIcon: Icons.whatshot_rounded),
    'Darkflame Cleft': TdDungeon(name: 'Darkflame Cleft', shortName: 'DC',
        enemyColor: Color(0xFFB22222), bossColor: Color(0xFFFF4500),
        enemyIcon: Icons.whatshot_rounded, bossIcon: Icons.local_fire_department),
    'The Rookery': TdDungeon(name: 'The Rookery', shortName: 'RK',
        enemyColor: Color(0xFF4682B4), bossColor: Color(0xFF1E90FF),
        enemyIcon: Icons.air_rounded, bossIcon: Icons.bolt_rounded),
    'Priory of the Sacred Flame': TdDungeon(name: 'Priory of the Sacred Flame', shortName: 'PSF',
        enemyColor: Color(0xFFDAA520), bossColor: Color(0xFFFFD700),
        enemyIcon: Icons.shield_rounded, bossIcon: Icons.auto_awesome_rounded),
    // Older / future dungeons
    'Mists of Tirna Scithe': TdDungeon(name: 'Mists of Tirna Scithe', shortName: 'MTS',
        enemyColor: Color(0xFF228B22), bossColor: Color(0xFF006400),
        enemyIcon: Icons.forest_rounded, bossIcon: Icons.eco_rounded),
    'The Necrotic Wake': TdDungeon(name: 'The Necrotic Wake', shortName: 'NW',
        enemyColor: Color(0xFF708090), bossColor: Color(0xFF2F4F4F),
        enemyIcon: Icons.dangerous_rounded, bossIcon: Icons.dangerous_rounded),
    'Operation: Mechagon': TdDungeon(name: 'Operation: Mechagon', shortName: 'MECH',
        enemyColor: Color(0xFFB0C4DE), bossColor: Color(0xFF4682B4),
        enemyIcon: Icons.settings_rounded, bossIcon: Icons.precision_manufacturing_rounded),
    'Theater of Pain': TdDungeon(name: 'Theater of Pain', shortName: 'TOP',
        enemyColor: Color(0xFF8B0000), bossColor: Color(0xFFDC143C),
        enemyIcon: Icons.sports_mma_rounded, bossIcon: Icons.local_fire_department),
  };

  /// Fallback icon/color palettes for unknown dungeons — picked by hash.
  static const List<(Color, Color, IconData, IconData)> _palettes = [
    (Color(0xFF6A5ACD), Color(0xFF483D8B), Icons.castle_rounded, Icons.auto_awesome_rounded),
    (Color(0xFFCD5C5C), Color(0xFF8B0000), Icons.whatshot_rounded, Icons.local_fire_department),
    (Color(0xFF20B2AA), Color(0xFF008B8B), Icons.water_rounded, Icons.waves_rounded),
    (Color(0xFFDAA520), Color(0xFFB8860B), Icons.shield_rounded, Icons.bolt_rounded),
    (Color(0xFF778899), Color(0xFF2F4F4F), Icons.terrain_rounded, Icons.dangerous_rounded),
    (Color(0xFF9370DB), Color(0xFF6A0DAD), Icons.dark_mode_rounded, Icons.pest_control_rounded),
  ];

  /// Create a TdDungeon from a name. Uses hand-themed data if known,
  /// otherwise generates consistent colors from the name hash.
  static TdDungeon fromName(String name) {
    // Check exact match first, then substring match for partial names
    if (_known.containsKey(name)) return _known[name]!;
    for (final entry in _known.entries) {
      if (name.contains(entry.key) || entry.key.contains(name)) {
        return entry.value;
      }
    }
    // Generate from name hash
    final hash = name.hashCode.abs();
    final palette = _palettes[hash % _palettes.length];
    final initials = name.split(' ')
        .where((w) => w.isNotEmpty && w[0] == w[0].toUpperCase())
        .map((w) => w[0])
        .take(3)
        .join();
    return TdDungeon(
      name: name,
      shortName: initials.isEmpty ? name.substring(0, 2).toUpperCase() : initials,
      enemyColor: palette.$1,
      bossColor: palette.$2,
      enemyIcon: palette.$3,
      bossIcon: palette.$4,
    );
  }

  /// Build dungeon list from API names, falling back to known list.
  static List<TdDungeon> fromNames(List<String> names) {
    if (names.isEmpty) return _known.values.toList();
    return names.map((n) => fromName(n)).toList();
  }

  /// Fallback static list.
  static List<TdDungeon> get fallbackList => _known.values.toList();
}

// ---------------------------------------------------------------------------
// KeystoneRun — configuration for a single run
// ---------------------------------------------------------------------------

/// Describes the parameters of a keystone run: level, affixes, and dungeon.
class KeystoneRun {
  final int level;
  final List<TdAffix> affixes;
  final TdDungeon dungeon;

  String get dungeonName => dungeon.name;

  const KeystoneRun({
    required this.level,
    required this.affixes,
    required this.dungeon,
  });

  /// Enemy HP multiplier based on keystone level (scales from level 2+).
  double get hpMultiplier => 1.0 + (level - 2) * 0.15;

  bool get hasFortified => affixes.contains(TdAffix.fortified);
  bool get hasTyrannical => affixes.contains(TdAffix.tyrannical);
  bool get hasBolstering => affixes.contains(TdAffix.bolstering);
  bool get hasBursting => affixes.contains(TdAffix.bursting);
  bool get hasSanguine => affixes.contains(TdAffix.sanguine);

  /// Generates a random keystone run for the given [level] and [dungeon].
  static KeystoneRun generate(int level, {TdDungeon? dungeon}) {
    final rng = Random();
    final allAffixes = List<TdAffix>.from(TdAffix.values)..shuffle(rng);
    final count = level >= 7 ? 2 : 1;
    return KeystoneRun(
      level: level,
      affixes: allAffixes.take(count).toList(),
      dungeon: dungeon ?? TdDungeon.fallbackList[rng.nextInt(TdDungeon.fallbackList.length)],
    );
  }
}
