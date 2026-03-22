import 'dart:math';

import '../data/effect_types.dart';

/// Events emitted by boss mechanics for the game state to process.
sealed class BossGameEvent {
  const BossGameEvent();
}

class SpawnAddEvent extends BossGameEvent {
  final double hp;
  final double speed;
  final int laneIndex;
  const SpawnAddEvent({required this.hp, required this.speed, required this.laneIndex});
}

class FireZoneEvent extends BossGameEvent {
  final int laneIndex;
  final double duration;
  const FireZoneEvent({required this.laneIndex, required this.duration});
}

class BossTeleportEvent extends BossGameEvent {
  final int newLane;
  const BossTeleportEvent({required this.newLane});
}

class KnockbackTowerEvent extends BossGameEvent {
  final int towerIndex;
  final int newLane;
  const KnockbackTowerEvent({required this.towerIndex, required this.newLane});
}

class ReflectDamageToggleEvent extends BossGameEvent {
  final bool active;
  const ReflectDamageToggleEvent({required this.active});
}

class WindPushEvent extends BossGameEvent {
  final int laneIndex;
  final double pushAmount;
  const WindPushEvent({required this.laneIndex, required this.pushAmount});
}

class StackingDamageTickEvent extends BossGameEvent {
  final double damagePerTower;
  const StackingDamageTickEvent({required this.damagePerTower});
}

class SplitOnDeathEvent extends BossGameEvent {
  final int count;
  final double hpEach;
  final double speed;
  final int laneIndex;
  final double position;
  const SplitOnDeathEvent({
    required this.count,
    required this.hpEach,
    required this.speed,
    required this.laneIndex,
    required this.position,
  });
}

class BossEffectProcessor {
  /// Initialize boss state when boss wave starts.
  static Map<String, dynamic> initBossState(List<EffectDef> modifiers) {
    final state = <String, dynamic>{};
    for (final mod in modifiers) {
      switch (mod.type) {
        case 'fire_zone':
          state['fire_zone_timer'] = 0.0;
          break;
        case 'teleport_lanes':
          state['teleport_timer'] = 0.0;
          break;
        case 'enrage':
          state['enraged'] = false;
          break;
        case 'summon_adds':
          state['summon_timer'] = 0.0;
          break;
        case 'reflect_damage':
          state['reflect_timer'] = 0.0;
          state['reflect_active'] = false;
          break;
        case 'knockback_tower':
          state['knockback_timer'] = 0.0;
          break;
        case 'stacking_damage':
          state['stacking_elapsed'] = 0.0;
          break;
        case 'wind_push':
          state['wind_timer'] = 0.0;
          break;
        // split_on_death: no timer needed, triggers on death
      }
    }
    return state;
  }

  /// Process boss mechanics each tick.
  /// Returns events for the game state to apply.
  static List<BossGameEvent> processTick({
    required List<EffectDef> modifiers,
    required Map<String, dynamic> state,
    required double bossHpFraction, // current HP / max HP (0-1)
    required int bossLane,
    required int towerCount, // total number of towers (for knockback)
    required double dt,
    required Random rng,
  }) {
    final events = <BossGameEvent>[];

    for (final mod in modifiers) {
      switch (mod.type) {
        case 'fire_zone':
          final interval = (mod.params['interval'] as num?)?.toDouble() ?? 5.0;
          final duration = (mod.params['duration'] as num?)?.toDouble() ?? 3.0;
          var timer = (state['fire_zone_timer'] as double?) ?? 0.0;
          timer += dt;
          if (timer >= interval) {
            state['fire_zone_timer'] = 0.0;
            events.add(FireZoneEvent(laneIndex: rng.nextInt(3), duration: duration));
          } else {
            state['fire_zone_timer'] = timer;
          }
          break;

        case 'teleport_lanes':
          final interval = (mod.params['interval'] as num?)?.toDouble() ?? 4.0;
          var timer = (state['teleport_timer'] as double?) ?? 0.0;
          timer += dt;
          if (timer >= interval) {
            state['teleport_timer'] = 0.0;
            int newLane;
            do {
              newLane = rng.nextInt(3);
            } while (newLane == bossLane);
            events.add(BossTeleportEvent(newLane: newLane));
          } else {
            state['teleport_timer'] = timer;
          }
          break;

        case 'enrage':
          final threshold = (mod.params['hpThreshold'] as num?)?.toDouble() ?? 0.3;
          final speedMult =
              (mod.params['speedMultiplier'] as num?)?.toDouble() ?? 2.0;
          if (state['enraged'] != true && bossHpFraction <= threshold) {
            state['enraged'] = true;
            state['enrage_speed_mult'] = speedMult;
          }
          break;

        case 'summon_adds':
          final interval = (mod.params['interval'] as num?)?.toDouble() ?? 6.0;
          final count = (mod.params['count'] as num?)?.toInt() ?? 2;
          final hpFraction =
              (mod.params['hpFraction'] as num?)?.toDouble() ?? 0.2;
          var timer = (state['summon_timer'] as double?) ?? 0.0;
          timer += dt;
          if (timer >= interval) {
            state['summon_timer'] = 0.0;
            for (var i = 0; i < count; i++) {
              events.add(SpawnAddEvent(
                hp: hpFraction, // game state multiplies by boss maxHp
                speed: 0.10 + rng.nextDouble() * 0.05,
                laneIndex: rng.nextInt(3),
              ));
            }
          } else {
            state['summon_timer'] = timer;
          }
          break;

        case 'reflect_damage':
          final interval = (mod.params['interval'] as num?)?.toDouble() ?? 6.0;
          final duration = (mod.params['duration'] as num?)?.toDouble() ?? 2.0;
          var timer = (state['reflect_timer'] as double?) ?? 0.0;
          timer += dt;
          if (state['reflect_active'] == true) {
            if (timer >= duration) {
              state['reflect_active'] = false;
              state['reflect_timer'] = 0.0;
              events.add(const ReflectDamageToggleEvent(active: false));
            } else {
              state['reflect_timer'] = timer;
            }
          } else {
            if (timer >= interval) {
              state['reflect_active'] = true;
              state['reflect_timer'] = 0.0;
              events.add(const ReflectDamageToggleEvent(active: true));
            } else {
              state['reflect_timer'] = timer;
            }
          }
          break;

        case 'knockback_tower':
          final interval = (mod.params['interval'] as num?)?.toDouble() ?? 5.0;
          var timer = (state['knockback_timer'] as double?) ?? 0.0;
          timer += dt;
          if (timer >= interval && towerCount > 0) {
            state['knockback_timer'] = 0.0;
            events.add(KnockbackTowerEvent(
              towerIndex: rng.nextInt(towerCount),
              newLane: rng.nextInt(3),
            ));
          } else {
            state['knockback_timer'] = timer;
          }
          break;

        case 'stacking_damage':
          final dps =
              (mod.params['damagePerSecond'] as num?)?.toDouble() ?? 2.0;
          final rampRate =
              (mod.params['rampRate'] as num?)?.toDouble() ?? 1.5;
          var elapsed = (state['stacking_elapsed'] as double?) ?? 0.0;
          elapsed += dt;
          state['stacking_elapsed'] = elapsed;
          // Damage ramps: dps * (1 + elapsed * rampRate) per second
          final currentDps = dps * (1 + elapsed * rampRate * 0.1);
          events.add(StackingDamageTickEvent(damagePerTower: currentDps * dt));
          break;

        case 'wind_push':
          final interval = (mod.params['interval'] as num?)?.toDouble() ?? 4.0;
          final pushAmount =
              (mod.params['pushAmount'] as num?)?.toDouble() ?? 0.3;
          var timer = (state['wind_timer'] as double?) ?? 0.0;
          timer += dt;
          if (timer >= interval) {
            state['wind_timer'] = 0.0;
            events.add(
                WindPushEvent(laneIndex: rng.nextInt(3), pushAmount: pushAmount));
          } else {
            state['wind_timer'] = timer;
          }
          break;

        // split_on_death: handled in processOnDeath, not in tick
      }
    }

    return events;
  }

  /// Process boss death. Returns split event if applicable.
  static SplitOnDeathEvent? processOnDeath({
    required List<EffectDef> modifiers,
    required double bossMaxHp,
    required double bossSpeed,
    required int bossLane,
    required double bossPosition,
  }) {
    for (final mod in modifiers) {
      if (mod.type == 'split_on_death') {
        final count = (mod.params['count'] as num?)?.toInt() ?? 3;
        final hpFraction =
            (mod.params['hpFraction'] as num?)?.toDouble() ?? 0.3;
        return SplitOnDeathEvent(
          count: count,
          hpEach: bossMaxHp * hpFraction,
          speed: bossSpeed * 1.5, // splits are faster
          laneIndex: bossLane,
          position: bossPosition,
        );
      }
    }
    return null;
  }
}
