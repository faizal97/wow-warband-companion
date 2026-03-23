// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wow_warband_companion/models/character.dart';
import 'package:wow_warband_companion/td/data/td_balance_config.dart';
import 'package:wow_warband_companion/td/data/td_class_registry.dart';
import 'package:wow_warband_companion/td/data/effect_types.dart';
import 'package:wow_warband_companion/td/models/td_models.dart';
import 'package:wow_warband_companion/td/td_game_state.dart';

import 'td_sim.dart';

// ---------------------------------------------------------------------------
// Balance Tuning Simulation
// ---------------------------------------------------------------------------
//
// Compares current balance vs proposed tuning across all key levels.
// Run: flutter test test/td/td_balance_tuning_test.dart --reporter expanded
// ---------------------------------------------------------------------------

/// Run a single sim with custom balance config.
({bool cleared, int lives, int waves}) _runWithConfig({
  required TdBalanceConfig config,
  required List<WowCharacter> characters,
  required TdDungeonDef dungeon,
  required TdClassRegistry classRegistry,
  required int level,
  int seed = 42,
}) {
  final game = TdGameState();
  game.startRun(characters, level,
      dungeon: dungeon, classRegistry: classRegistry, balanceConfig: config);

  final ks = KeystoneRun(level: level, affixes: const [], dungeon: dungeon);
  game.keystone = ks;

  // Deploy towers: 2-2-1+ lane split, all mid slot
  for (var i = 0; i < game.towers.length; i++) {
    final lane = i < 2 ? 0 : i < 4 ? 1 : 2;
    game.moveTower(i, lane, slot: 1);
  }

  game.beginGame();

  const dt = 1.0 / 60.0;
  const maxTicks = 60 * 300;
  var tick = 0;

  while (tick < maxTicks) {
    game.tick(dt);
    tick++;
    if (game.phase == TdGamePhase.victory || game.phase == TdGamePhase.defeat) {
      break;
    }
    if (game.phase == TdGamePhase.betweenWaves) {
      game.nextWave();
    }
  }

  return (
    cleared: game.phase == TdGamePhase.victory,
    lives: game.lives,
    waves: game.currentWave,
  );
}

/// Batch run with custom config.
({int clearRate, double avgLives, int bestLives, int worstLives}) _batchWithConfig({
  required TdBalanceConfig config,
  required List<WowCharacter> characters,
  required TdDungeonDef dungeon,
  required TdClassRegistry classRegistry,
  required int level,
  int runs = 20,
}) {
  var clears = 0;
  var totalLives = 0;
  var bestLives = 0;
  var worstLives = 999;

  for (var i = 0; i < runs; i++) {
    final r = _runWithConfig(
      config: config,
      characters: characters,
      dungeon: dungeon,
      classRegistry: classRegistry,
      level: level,
      seed: 1000 + i * 37,
    );
    if (r.cleared) clears++;
    totalLives += r.lives;
    if (r.lives > bestLives) bestLives = r.lives;
    if (r.lives < worstLives) worstLives = r.lives;
  }

  return (
    clearRate: (clears / runs * 100).round(),
    avgLives: totalLives / runs,
    bestLives: bestLives,
    worstLives: worstLives,
  );
}

void main() {
  late TdClassRegistry classRegistry;
  late Map<String, TdDungeonDef> dungeons;
  late List<WowCharacter> heroComp;
  late List<WowCharacter> classComp;

  setUpAll(() {
    // Load class registry from disk
    final classFile = File('assets/td/classes.json');
    final classData = jsonDecode(classFile.readAsStringSync()) as Map<String, dynamic>;
    final classes = classData['classes'] as Map<String, dynamic>? ?? {};
    final fallbackJson = classData['_fallback'] as Map<String, dynamic>?;

    // Build a simple registry
    classRegistry = _SimpleClassRegistry(classes, fallbackJson);

    // Load dungeons
    final dungeonFile = File('assets/td/dungeons.json');
    final dungeonData = jsonDecode(dungeonFile.readAsStringSync()) as Map<String, dynamic>;
    final raw = dungeonData['dungeons'] as Map<String, dynamic>? ?? {};
    dungeons = raw.map((key, value) =>
        MapEntry(key, TdDungeonDef.fromJson(key, value as Map<String, dynamic>)));

    // Hero comp (8 heroes at ilvl 250)
    heroComp = [
      _char('Warrior', ilvl: 250),
      _char('Demon Hunter', ilvl: 250),
      _char('Mage', ilvl: 250),
      _char('Hunter', ilvl: 250),
      _char('Priest', ilvl: 250),
      _char('Druid', ilvl: 250),
      _char('Shaman', ilvl: 250),
      _char('Mage', ilvl: 250, name: 'Mage2'),
    ];

    // Balanced 5-man comp at ilvl 250
    classComp = [
      _char('Warrior', ilvl: 250),
      _char('Mage', ilvl: 250),
      _char('Priest', ilvl: 250),
      _char('Hunter', ilvl: 250),
      _char('Monk', ilvl: 250),
    ];

    print('Loaded ${classes.length} classes, ${dungeons.length} dungeons');
  });

  test('CURRENT vs PROPOSED balance — keystone scaling comparison', () {
    const current = TdBalanceConfig();
    const proposed = TdBalanceConfig(
      startingLives: 15,
      baseEnemyHp: 400,
      linearRate: 0.10,
      exponentialQuadratic: 0.02,
    );

    final dungeon = dungeons['windrunner_spire']!;
    final levels = [2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15];

    print('\n${"=" * 95}');
    print('KEYSTONE SCALING — Windrunner Spire, 8-tower comp (ilvl 250), no affixes');
    print('CURRENT: 25 lives, 200 HP, linearRate=0.12, expQuad=0.05');
    print('PROPOSED: 15 lives, 400 HP, linearRate=0.10, expQuad=0.02');
    print('${"=" * 95}');
    print('${"Level".padRight(8)} '
        '${"C.Clear%".padRight(10)} ${"C.Lives".padRight(10)} '
        '${"P.Clear%".padRight(10)} ${"P.Lives".padRight(10)} '
        '${"C.HP".padRight(10)} ${"P.HP".padRight(10)}');
    print('-' * 95);

    for (final level in levels) {
      final currentR = _batchWithConfig(
        config: current, characters: heroComp, dungeon: dungeon,
        classRegistry: classRegistry, level: level,
      );
      final proposedR = _batchWithConfig(
        config: proposed, characters: heroComp, dungeon: dungeon,
        classRegistry: classRegistry, level: level,
      );

      // Calculate HP multipliers
      final cHpMult = level <= current.linearPhaseEnd
          ? 1.0 + (level - 2) * current.linearRate
          : current.exponentialBase + (level - current.linearPhaseEnd) * current.exponentialLinear +
              (level - current.linearPhaseEnd) * (level - current.linearPhaseEnd) * current.exponentialQuadratic;
      final pHpMult = level <= proposed.linearPhaseEnd
          ? 1.0 + (level - 2) * proposed.linearRate
          : proposed.exponentialBase + (level - proposed.linearPhaseEnd) * proposed.exponentialLinear +
              (level - proposed.linearPhaseEnd) * (level - proposed.linearPhaseEnd) * proposed.exponentialQuadratic;

      final cHp = (current.baseEnemyHp * cHpMult).round();
      final pHp = (proposed.baseEnemyHp * pHpMult).round();

      print('+$level'.padRight(8) +
          '${currentR.clearRate}%'.padRight(10) +
          '${currentR.avgLives.toStringAsFixed(1)}'.padRight(10) +
          '${proposedR.clearRate}%'.padRight(10) +
          '${proposedR.avgLives.toStringAsFixed(1)}'.padRight(10) +
          '$cHp'.padRight(10) +
          '$pHp'.padRight(10));
    }
  });

  test('PROPOSED balance — 5-man comp scaling', () {
    const proposed = TdBalanceConfig(
      startingLives: 15,
      baseEnemyHp: 400,
      linearRate: 0.10,
      exponentialQuadratic: 0.02,
    );

    final dungeon = dungeons['windrunner_spire']!;
    final levels = [2, 3, 4, 5, 6, 7, 8, 10, 12, 15];

    print('\n${"=" * 75}');
    print('PROPOSED — 5-man comp (ilvl 250), Windrunner Spire');
    print('${"=" * 75}');
    print('${"Level".padRight(8)} ${"Clear%".padRight(10)} ${"AvgLives".padRight(10)} ${"Best".padRight(8)} ${"Worst".padRight(8)}');
    print('-' * 75);

    for (final level in levels) {
      final r = _batchWithConfig(
        config: proposed, characters: classComp, dungeon: dungeon,
        classRegistry: classRegistry, level: level,
      );
      print('+$level'.padRight(8) +
          '${r.clearRate}%'.padRight(10) +
          r.avgLives.toStringAsFixed(1).padRight(10) +
          '${r.bestLives}'.padRight(8) +
          '${r.worstLives}'.padRight(8));
    }
  });

  test('PROPOSED balance — all dungeons at +5 and +10', () {
    const proposed = TdBalanceConfig(
      startingLives: 15,
      baseEnemyHp: 400,
      linearRate: 0.10,
      exponentialQuadratic: 0.02,
    );

    print('\n${"=" * 85}');
    print('PROPOSED — 8-hero comp (ilvl 250), all dungeons at +5 and +10');
    print('${"=" * 85}');
    print('${"Dungeon".padRight(30)} ${"Clear+5".padRight(10)} ${"Lives+5".padRight(10)} ${"Clear+10".padRight(10)} ${"Lives+10".padRight(10)}');
    print('-' * 85);

    for (final key in dungeons.keys) {
      final r5 = _batchWithConfig(
        config: proposed, characters: heroComp, dungeon: dungeons[key]!,
        classRegistry: classRegistry, level: 5,
      );
      final r10 = _batchWithConfig(
        config: proposed, characters: heroComp, dungeon: dungeons[key]!,
        classRegistry: classRegistry, level: 10,
      );
      print('${dungeons[key]!.name.padRight(30)} '
          '${r5.clearRate}%'.padRight(10) +
          r5.avgLives.toStringAsFixed(1).padRight(10) +
          '${r10.clearRate}%'.padRight(10) +
          r10.avgLives.toStringAsFixed(1).padRight(10));
    }
  });

  test('try different tuning variants', () {
    final dungeon = dungeons['windrunner_spire']!;
    final levels = [2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 20];

    final variants = <String, TdBalanceConfig>{
      'CURRENT': const TdBalanceConfig(),
      'N (best so far)': const TdBalanceConfig(
        startingLives: 20, baseEnemyHp: 250, linearPhaseEnd: 20, linearRate: 0.10,
        exponentialBase: 2.8, exponentialQuadratic: 0.02,
      ),
      'O: N + waveScale 0.15': const TdBalanceConfig(
        startingLives: 20, baseEnemyHp: 250, linearPhaseEnd: 20, linearRate: 0.10,
        exponentialBase: 2.8, exponentialQuadratic: 0.02,
        waveHpScalePerWave: 0.15,
      ),
      'P: N + waveScale 0.12': const TdBalanceConfig(
        startingLives: 20, baseEnemyHp: 250, linearPhaseEnd: 20, linearRate: 0.10,
        exponentialBase: 2.8, exponentialQuadratic: 0.02,
        waveHpScalePerWave: 0.12,
      ),
      'Q: 20L,270hp,lin20,r0.09,ws0.15': const TdBalanceConfig(
        startingLives: 20, baseEnemyHp: 270, linearPhaseEnd: 20, linearRate: 0.09,
        exponentialBase: 2.62, exponentialQuadratic: 0.02,
        waveHpScalePerWave: 0.15,
      ),
      'R: 20L,260hp,lin20,r0.10,ws0.12': const TdBalanceConfig(
        startingLives: 20, baseEnemyHp: 260, linearPhaseEnd: 20, linearRate: 0.10,
        exponentialBase: 2.8, exponentialQuadratic: 0.02,
        waveHpScalePerWave: 0.12,
      ),
    };

    print('\n${"=" * 95}');
    print('VARIANT COMPARISON — 8-hero comp (ilvl 250), Windrunner Spire');
    print('${"=" * 95}');

    for (final entry in variants.entries) {
      print('\n--- ${entry.key} ---');
      print('${"Level".padRight(8)} ${"Clear%".padRight(10)} ${"AvgLives".padRight(10)}');
      print('-' * 30);

      for (final level in levels) {
        final r = _batchWithConfig(
          config: entry.value, characters: heroComp, dungeon: dungeon,
          classRegistry: classRegistry, level: level,
        );
        print('+$level'.padRight(8) +
            '${r.clearRate}%'.padRight(10) +
            r.avgLives.toStringAsFixed(1).padRight(10));
      }
    }
  });
}

// Helpers

WowCharacter _char(String className, {int ilvl = 250, String? name}) {
  return WowCharacter(
    id: (name ?? className).hashCode,
    name: name ?? className,
    realm: 'Sim',
    realmSlug: 'sim',
    level: 90,
    characterClass: className,
    activeSpec: 'Spec',
    race: 'Human',
    faction: 'Alliance',
    equippedItemLevel: ilvl,
  );
}

class _SimpleClassRegistry extends TdClassRegistry {
  final Map<String, TdClassDef> _classes = {};
  final TdClassDef? _fallback;

  _SimpleClassRegistry(Map<String, dynamic> classesJson, Map<String, dynamic>? fallbackJson)
      : _fallback = fallbackJson != null ? TdClassDef.fromJson('_fallback', fallbackJson) : null {
    for (final entry in classesJson.entries) {
      _classes[entry.key.toLowerCase()] = TdClassDef.fromJson(entry.key.toLowerCase(), entry.value);
    }
  }

  @override
  TdClassDef getClass(String className) => _classes[className.toLowerCase()] ?? fallback;
  @override
  TdClassDef get fallback => _fallback ?? TdClassDef.fromJson('unknown', {});
  @override
  List<String> get allClassNames => _classes.keys.toList();
  @override
  bool get isLoaded => true;
}
