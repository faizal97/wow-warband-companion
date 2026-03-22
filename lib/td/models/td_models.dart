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

/// Mythic+ affixes that alter tower-defense gameplay.
enum TdAffix { fortified, tyrannical, bolstering, bursting, sanguine }

// ---------------------------------------------------------------------------
// KeystoneRun — configuration for a single run
// ---------------------------------------------------------------------------

/// Describes the parameters of a keystone run: level, affixes, and dungeon.
class KeystoneRun {
  final int level;
  final List<TdAffix> affixes;
  final String dungeonName;

  const KeystoneRun({
    required this.level,
    required this.affixes,
    this.dungeonName = 'Stonevault',
  });

  /// Enemy HP multiplier based on keystone level (scales from level 2+).
  double get hpMultiplier => 1.0 + (level - 2) * 0.15;

  bool get hasFortified => affixes.contains(TdAffix.fortified);
  bool get hasTyrannical => affixes.contains(TdAffix.tyrannical);
  bool get hasBolstering => affixes.contains(TdAffix.bolstering);
  bool get hasBursting => affixes.contains(TdAffix.bursting);
  bool get hasSanguine => affixes.contains(TdAffix.sanguine);

  /// Generates a random keystone run for the given [level].
  /// Levels below 7 get 1 affix; levels 7+ get 2.
  static KeystoneRun generate(int level) {
    final rng = Random();
    final allAffixes = List<TdAffix>.from(TdAffix.values)..shuffle(rng);
    final count = level >= 7 ? 2 : 1;
    return KeystoneRun(
      level: level,
      affixes: allAffixes.take(count).toList(),
    );
  }
}
