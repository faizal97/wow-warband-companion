import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:wow_warband_companion/td/data/effect_types.dart';
import 'package:wow_warband_companion/td/effects/tower_effects.dart';

void main() {
  late Random rng;

  setUp(() {
    rng = Random(42); // deterministic for tests
  });

  /// Helper to create enemy records for testing.
  List<({String id, double hp, double position, int lane})> makeEnemies(
    int count, {
    int lane = 0,
  }) {
    return List.generate(
      count,
      (i) => (
        id: 'e$i',
        hp: 100.0,
        position: 0.1 * (i + 1), // spread across lane
        lane: lane,
      ),
    );
  }

  /// Helper to create a class def with a specific archetype and passive effects.
  TdClassDef makeClass(
    String archetype, {
    List<Map<String, dynamic>> effects = const [],
    String trigger = 'on_attack',
    int nth = 0,
  }) {
    return TdClassDef.fromJson('test', {
      'archetype': archetype,
      'passive': {
        'name': 'Test',
        'description': 'Test passive',
        'trigger': trigger,
        'nth': nth,
        'effects': effects,
      },
      'attack_color': '#FFFFFF',
    });
  }

  group('Basic targeting', () {
    test('melee hits closest enemy (highest position)', () {
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.melee,
        classDef: makeClass('melee'),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: makeEnemies(3),
        baseDamage: 50,
        attackCount: 1,
        chargeTimer: 0,
        dt: 0.1,
        rng: rng,
      );
      expect(result.hits.length, 1);
      expect(result.hits.first.enemyId, 'e2'); // highest position = 0.3
    });

    test('ranged hits furthest enemy (lowest position)', () {
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.ranged,
        classDef: makeClass('ranged'),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: makeEnemies(3),
        baseDamage: 50,
        attackCount: 1,
        chargeTimer: 0,
        dt: 0.1,
        rng: rng,
      );
      expect(result.hits.length, 1);
      expect(result.hits.first.enemyId, 'e0'); // lowest position = 0.1
    });

    test('aoe hits all enemies in lane', () {
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.aoe,
        classDef: makeClass('aoe'),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: makeEnemies(5),
        baseDamage: 30,
        attackCount: 1,
        chargeTimer: 0,
        dt: 0.1,
        rng: rng,
      );
      expect(result.hits.length, 5);
    });

    test('support returns empty result', () {
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.support,
        classDef: makeClass('support'),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: makeEnemies(3),
        baseDamage: 50,
        attackCount: 1,
        chargeTimer: 0,
        dt: 0.1,
        rng: rng,
      );
      expect(result.hits, isEmpty);
    });

    test('only targets enemies in same lane', () {
      final enemies = [
        (id: 'same', hp: 100.0, position: 0.5, lane: 0),
        (id: 'other', hp: 100.0, position: 0.9, lane: 1),
      ];
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.melee,
        classDef: makeClass('melee'),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: enemies,
        baseDamage: 50,
        attackCount: 1,
        chargeTimer: 0,
        dt: 0.1,
        rng: rng,
      );
      expect(result.hits.length, 1);
      expect(result.hits.first.enemyId, 'same');
    });
  });

  group('Passive effects', () {
    test('extra_targets hits additional enemies', () {
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.melee,
        classDef: makeClass('melee', effects: [
          {'type': 'extra_targets', 'value': 1},
        ]),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: makeEnemies(3),
        baseDamage: 50,
        attackCount: 1,
        chargeTimer: 0,
        dt: 0.1,
        rng: rng,
      );
      expect(result.hits.length, 2);
    });

    test('extra_targets capped by available enemies', () {
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.melee,
        classDef: makeClass('melee', effects: [
          {'type': 'extra_targets', 'value': 10},
        ]),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: makeEnemies(2),
        baseDamage: 50,
        attackCount: 1,
        chargeTimer: 0,
        dt: 0.1,
        rng: rng,
      );
      expect(result.hits.length, 2); // only 2 enemies available
    });

    test('damage_multiplier on nth attack', () {
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.melee,
        classDef: makeClass('melee',
            trigger: 'on_nth_attack',
            nth: 4,
            effects: [
              {'type': 'damage_multiplier', 'value': 3.0},
            ]),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: makeEnemies(1),
        baseDamage: 50,
        attackCount: 4, // 4th attack (4 % 4 == 0)
        chargeTimer: 0,
        dt: 0.1,
        rng: rng,
      );
      expect(result.hits.first.damage, 150.0); // 50 * 3.0
    });

    test('on_nth_attack does not fire on non-nth attacks', () {
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.melee,
        classDef: makeClass('melee',
            trigger: 'on_nth_attack',
            nth: 4,
            effects: [
              {'type': 'damage_multiplier', 'value': 3.0},
            ]),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: makeEnemies(1),
        baseDamage: 50,
        attackCount: 3, // not a multiple of 4
        chargeTimer: 0,
        dt: 0.1,
        rng: rng,
      );
      expect(result.hits.first.damage, 50.0); // no multiplier
    });

    test('slow_enemy creates status effect', () {
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.melee,
        classDef: makeClass('melee', effects: [
          {'type': 'slow_enemy', 'value': 0.2, 'duration': 2.0},
        ]),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: makeEnemies(1),
        baseDamage: 50,
        attackCount: 1,
        chargeTimer: 0,
        dt: 0.1,
        rng: rng,
      );
      expect(result.newStatusEffects.length, 1);
      expect(result.newStatusEffects.first.type, 'slow');
      expect(result.newStatusEffects.first.slowAmount, 0.2);
      expect(result.newStatusEffects.first.remaining, 2.0);
    });

    test('dot creates status effect', () {
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.ranged,
        classDef: makeClass('ranged', effects: [
          {'type': 'dot', 'value': 0.3, 'duration': 3.0, 'ticks': 3},
        ]),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: makeEnemies(1),
        baseDamage: 50,
        attackCount: 1,
        chargeTimer: 0,
        dt: 0.1,
        rng: rng,
      );
      expect(result.newStatusEffects.length, 1);
      expect(result.newStatusEffects.first.type, 'dot');
      expect(result.newStatusEffects.first.dotDamage, 15.0); // 50 * 0.3
      expect(result.newStatusEffects.first.tickInterval, 1.0); // 3.0 / 3
    });

    test('unknown effect type is silently skipped', () {
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.melee,
        classDef: makeClass('melee', effects: [
          {'type': 'future_effect_xyz', 'value': 99},
        ]),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: makeEnemies(1),
        baseDamage: 50,
        attackCount: 1,
        chargeTimer: 0,
        dt: 0.1,
        rng: rng,
      );
      expect(result.hits.length, 1); // still attacks normally
      expect(result.hits.first.damage, 50); // no modification
    });

    test('cross_lane_attack targets enemies in adjacent lanes', () {
      final enemies = [
        (id: 'e_lane0', hp: 100.0, position: 0.5, lane: 0),
        (id: 'e_lane1', hp: 100.0, position: 0.5, lane: 1),
        (id: 'e_lane2', hp: 100.0, position: 0.5, lane: 2),
      ];
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.aoe,
        classDef: makeClass('aoe', effects: [
          {'type': 'cross_lane_attack', 'value': 1},
        ]),
        towerLane: 1, // center lane
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: enemies,
        baseDamage: 30,
        attackCount: 1,
        chargeTimer: 0,
        dt: 0.1,
        rng: rng,
      );
      // AoE + cross_lane_attack with range 1 should hit all 3 lanes
      expect(result.hits.length, 3);
    });

    test('charge_attack returns isCharging when not fully charged', () {
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.ranged,
        classDef: makeClass('ranged', trigger: 'passive', effects: [
          {'type': 'charge_attack', 'chargeTime': 3.0, 'multiplier': 2.5},
        ]),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: makeEnemies(1),
        baseDamage: 50,
        attackCount: 1,
        chargeTimer: 1.0, // only 1 second into a 3 second charge
        dt: 0.1,
        rng: rng,
      );
      expect(result.isCharging, true);
      expect(result.hits, isEmpty);
    });

    test('charge_attack fires with multiplier when fully charged', () {
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.ranged,
        classDef: makeClass('ranged', trigger: 'passive', effects: [
          {'type': 'charge_attack', 'chargeTime': 3.0, 'multiplier': 2.5},
        ]),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: makeEnemies(1),
        baseDamage: 50,
        attackCount: 1,
        chargeTimer: 3.0, // fully charged
        dt: 0.1,
        rng: rng,
      );
      expect(result.isCharging, false);
      expect(result.hits.length, 1);
      expect(result.hits.first.damage, 125.0); // 50 * 2.5
    });
  });

  group('No enemies', () {
    test('returns empty result when no enemies', () {
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.melee,
        classDef: makeClass('melee'),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: [],
        baseDamage: 50,
        attackCount: 1,
        chargeTimer: 0,
        dt: 0.1,
        rng: rng,
      );
      expect(result.hits, isEmpty);
    });

    test('returns empty when no enemies in tower lane', () {
      final enemies = makeEnemies(3, lane: 2); // all in lane 2
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.melee,
        classDef: makeClass('melee'),
        towerLane: 0, // tower in lane 0
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: enemies,
        baseDamage: 50,
        attackCount: 1,
        chargeTimer: 0,
        dt: 0.1,
        rng: rng,
      );
      expect(result.hits, isEmpty);
    });
  });

  group('Chain damage', () {
    test('chain_damage hits multiple enemies with decay', () {
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.ranged,
        classDef: makeClass('ranged', effects: [
          {
            'type': 'chain_damage',
            'bounces': [1.0, 0.7, 0.5],
          },
        ]),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: makeEnemies(5),
        baseDamage: 100,
        attackCount: 1,
        chargeTimer: 0,
        dt: 0.1,
        rng: rng,
      );
      expect(result.hits.length, 3);
      expect(result.hits[0].damage, 100.0); // 1.0 * 100
      expect(result.hits[1].damage, 70.0); // 0.7 * 100
      expect(result.hits[2].damage, 50.0); // 0.5 * 100
    });

    test('chain_damage capped by enemy count', () {
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.ranged,
        classDef: makeClass('ranged', effects: [
          {
            'type': 'chain_damage',
            'bounces': [1.0, 0.7, 0.5, 0.3],
          },
        ]),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: makeEnemies(2),
        baseDamage: 100,
        attackCount: 1,
        chargeTimer: 0,
        dt: 0.1,
        rng: rng,
      );
      expect(result.hits.length, 2); // only 2 enemies
    });
  });

  group('Crit chance', () {
    test('crit_chance applies multiplier on crit', () {
      // Use a seeded RNG and check behavior
      final deterministicRng = Random(42);
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.melee,
        classDef: makeClass('melee', effects: [
          {'type': 'crit_chance', 'chance': 1.0, 'multiplier': 2.0},
        ]),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: makeEnemies(1),
        baseDamage: 50,
        attackCount: 1,
        chargeTimer: 0,
        dt: 0.1,
        rng: deterministicRng,
      );
      // chance=1.0 guarantees a crit
      expect(result.didCrit, true);
      expect(result.hits.first.damage, 100.0); // 50 * 2.0
    });

    test('crit_chance does not apply with 0 chance', () {
      final deterministicRng = Random(42);
      final result = TowerEffectProcessor.processAttack(
        archetype: TowerArchetype.melee,
        classDef: makeClass('melee', effects: [
          {'type': 'crit_chance', 'chance': 0.0, 'multiplier': 2.0},
        ]),
        towerLane: 0,
        towerPosition: 0.5,
        attackRange: 1.0,
        enemies: makeEnemies(1),
        baseDamage: 50,
        attackCount: 1,
        chargeTimer: 0,
        dt: 0.1,
        rng: deterministicRng,
      );
      expect(result.didCrit, false);
      expect(result.hits.first.damage, 50.0);
    });
  });
}
