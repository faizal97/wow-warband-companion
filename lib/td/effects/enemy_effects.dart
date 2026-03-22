import 'dart:math';

import '../data/effect_types.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

/// Result of processing an enemy modifier each tick.
sealed class EnemyTickResult {
  const EnemyTickResult();

  const factory EnemyTickResult.switchLane(int newLane) = SwitchLaneResult;
  const factory EnemyTickResult.attackTower(int lane, double damage) =
      AttackTowerResult;
  const factory EnemyTickResult.setSpeedMultiplier(double multiplier) =
      SetSpeedResult;
  const factory EnemyTickResult.slowTowersInLane(int lane, double percent) =
      SlowTowersResult;
}

class SwitchLaneResult extends EnemyTickResult {
  final int newLane;
  const SwitchLaneResult(this.newLane);
}

class AttackTowerResult extends EnemyTickResult {
  final int lane;
  final double damage;
  const AttackTowerResult(this.lane, this.damage);
}

class SetSpeedResult extends EnemyTickResult {
  final double multiplier;
  const SetSpeedResult(this.multiplier);
}

class SlowTowersResult extends EnemyTickResult {
  final int lane;
  final double percent;
  const SlowTowersResult(this.lane, this.percent);
}

/// Result of processing an enemy death.
sealed class EnemyDeathResult {
  const EnemyDeathResult();

  const factory EnemyDeathResult.died() = EnemyDiedResult;
  const factory EnemyDeathResult.resurrect({
    required double hp,
    required double position,
    required int laneIndex,
  }) = EnemyResurrectResult;
}

class EnemyDiedResult extends EnemyDeathResult {
  const EnemyDiedResult();
}

class EnemyResurrectResult extends EnemyDeathResult {
  final double hp;
  final double position;
  final int laneIndex;
  const EnemyResurrectResult({
    required this.hp,
    required this.position,
    required this.laneIndex,
  });
}

// ---------------------------------------------------------------------------
// EnemyEffectProcessor
// ---------------------------------------------------------------------------

/// Handles enemy modifier effects from dungeon data.
///
/// Enemies carry [EffectDef] modifiers that modify their behavior during
/// gameplay (damage reduction, shields, resurrect, lane switching, etc.).
/// All methods are static and operate on the enemy's modifier list and its
/// mutable [modifierState] map.
class EnemyEffectProcessor {
  /// Initialize modifier state when an enemy spawns.
  /// Called once per enemy on creation. Sets up initial values for each
  /// modifier.
  static Map<String, dynamic> initModifierState(List<EffectDef> modifiers) {
    final state = <String, dynamic>{};
    for (final mod in modifiers) {
      switch (mod.type) {
        case 'shield':
          state['shield_hits'] = (mod.params['hits'] as num?)?.toInt() ?? 0;
        case 'phase':
          state['phase_timer'] = 0.0; // starts visible
          state['phase_invuln'] = false;
        case 'lane_switch':
          state['has_switched'] = false;
        case 'resurrect':
          state['has_resurrected'] = false;
        case 'ranged_attack':
          state['attack_timer'] = 0.0;
        case 'frost_aura':
          // No init state needed -- applies each tick
          break;
        case 'accelerate':
          // No init state needed -- computed from position
          break;
        // Unknown modifiers: silently skip
      }
    }
    return state;
  }

  /// Process enemy modifiers each tick.
  /// Returns a list of effects to apply to the game (tower debuffs, etc).
  static List<EnemyTickResult> processTick({
    required List<EffectDef> modifiers,
    required Map<String, dynamic> state,
    required double position,
    required int laneIndex,
    required double dt,
    required Random rng,
  }) {
    final results = <EnemyTickResult>[];

    for (final mod in modifiers) {
      switch (mod.type) {
        case 'phase':
          // Toggle invulnerability on a timer
          final interval =
              (mod.params['interval'] as num?)?.toDouble() ?? 3.0;
          final invulnDuration =
              (mod.params['invulnDuration'] as num?)?.toDouble() ?? 0.5;
          var timer = (state['phase_timer'] as double?) ?? 0.0;
          timer += dt;
          if (state['phase_invuln'] == true) {
            // Currently invulnerable -- check if duration expired
            if (timer >= invulnDuration) {
              state['phase_invuln'] = false;
              state['phase_timer'] = 0.0;
            } else {
              state['phase_timer'] = timer;
            }
          } else {
            // Currently vulnerable -- check if interval elapsed
            if (timer >= interval) {
              state['phase_invuln'] = true;
              state['phase_timer'] = 0.0;
            } else {
              state['phase_timer'] = timer;
            }
          }

        case 'lane_switch':
          // Switch lanes at position threshold
          final threshold =
              (mod.params['positionThreshold'] as num?)?.toDouble() ?? 0.5;
          final chance =
              (mod.params['chance'] as num?)?.toDouble() ?? 0.4;
          if (state['has_switched'] != true && position >= threshold) {
            if (rng.nextDouble() < chance) {
              // Pick a different lane
              final currentLane = laneIndex;
              int newLane;
              do {
                newLane = rng.nextInt(3);
              } while (newLane == currentLane);
              results.add(EnemyTickResult.switchLane(newLane));
            }
            state['has_switched'] = true;
          }

        case 'ranged_attack':
          // Periodically damage towers in the lane
          final interval =
              (mod.params['interval'] as num?)?.toDouble() ?? 3.0;
          final damage =
              (mod.params['damage'] as num?)?.toDouble() ?? 5.0;
          var timer = (state['attack_timer'] as double?) ?? 0.0;
          timer += dt;
          if (timer >= interval) {
            state['attack_timer'] = 0.0;
            results.add(EnemyTickResult.attackTower(laneIndex, damage));
          } else {
            state['attack_timer'] = timer;
          }

        case 'accelerate':
          // Speed increases based on position (0->1)
          final startMult =
              (mod.params['startSpeedMult'] as num?)?.toDouble() ?? 0.5;
          final endMult =
              (mod.params['endSpeedMult'] as num?)?.toDouble() ?? 1.5;
          final speedMult =
              startMult + (endMult - startMult) * position.clamp(0, 1);
          results.add(EnemyTickResult.setSpeedMultiplier(speedMult));

        case 'frost_aura':
          // Slow towers in lane (handled by game state reading the modifier)
          final slowPercent =
              (mod.params['slowPercent'] as num?)?.toDouble() ?? 0.05;
          results.add(EnemyTickResult.slowTowersInLane(laneIndex, slowPercent));
      }
    }

    return results;
  }

  /// Modify incoming damage based on enemy modifiers.
  /// Returns the actual damage to apply (may be 0 if shielded/invulnerable/
  /// spectral).
  static double modifyIncomingDamage({
    required List<EffectDef> modifiers,
    required Map<String, dynamic> state,
    required double rawDamage,
    required double position,
  }) {
    var damage = rawDamage;

    for (final mod in modifiers) {
      switch (mod.type) {
        case 'spectral':
          // Reduced damage until position threshold
          final reduction =
              (mod.params['damageReduction'] as num?)?.toDouble() ?? 0.5;
          final threshold =
              (mod.params['untilPosition'] as num?)?.toDouble() ?? 0.5;
          if (position < threshold) {
            damage *= (1.0 - reduction);
          }

        case 'shield':
          // Absorb hits
          final remaining = (state['shield_hits'] as int?) ?? 0;
          if (remaining > 0) {
            state['shield_hits'] = remaining - 1;
            return 0; // blocked entirely
          }

        case 'phase':
          // Invulnerable during phase
          if (state['phase_invuln'] == true) {
            return 0;
          }
      }
    }

    return damage;
  }

  /// Process on-death behavior. Returns a resurrection if applicable.
  static EnemyDeathResult processOnDeath({
    required List<EffectDef> modifiers,
    required Map<String, dynamic> state,
    required double position,
    required int laneIndex,
    required double maxHp,
    required Random rng,
  }) {
    for (final mod in modifiers) {
      if (mod.type == 'resurrect') {
        final chance = (mod.params['chance'] as num?)?.toDouble() ?? 0.3;
        final hpFraction =
            (mod.params['hpFraction'] as num?)?.toDouble() ?? 0.4;
        final hasResurrected = state['has_resurrected'] as bool? ?? false;

        if (!hasResurrected && rng.nextDouble() < chance) {
          state['has_resurrected'] = true;
          return EnemyDeathResult.resurrect(
            hp: maxHp * hpFraction,
            position: position,
            laneIndex: laneIndex,
          );
        }
      }
    }
    return const EnemyDeathResult.died();
  }

  /// Check if an enemy should apply a modifier on spawn (chance-based).
  /// For modifiers like 'shield' with a 'chance' param, roll to see if this
  /// enemy gets it.
  static List<EffectDef> rollSpawnModifiers(
    List<EffectDef> dungeonModifiers,
    Random rng,
  ) {
    final applied = <EffectDef>[];
    for (final mod in dungeonModifiers) {
      final chance = (mod.params['chance'] as num?)?.toDouble();
      if (chance != null && chance < 1.0) {
        if (rng.nextDouble() < chance) {
          applied.add(mod);
        }
      } else {
        // No chance param or chance >= 1.0: always apply
        applied.add(mod);
      }
    }
    return applied;
  }
}
