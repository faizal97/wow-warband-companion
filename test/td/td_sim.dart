// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:wow_warband_companion/models/character.dart';
import 'package:wow_warband_companion/td/data/effect_types.dart';
import 'package:wow_warband_companion/td/data/td_balance_config.dart';
import 'package:wow_warband_companion/td/data/td_class_registry.dart';
import 'package:wow_warband_companion/td/data/td_hero_registry.dart';
import 'package:wow_warband_companion/td/data/td_run_state.dart';
import 'package:wow_warband_companion/td/models/td_combat_log.dart';
import 'package:wow_warband_companion/td/models/td_models.dart';
import 'package:wow_warband_companion/td/td_game_state.dart';

// ---------------------------------------------------------------------------
// TD Balance Simulation Engine
// ---------------------------------------------------------------------------
//
// Reusable simulation engine for testing any combination of:
//   - Classes (any 5 from 13)
//   - Dungeons (any of the 8)
//   - Keystone levels (2-20+)
//   - Affixes (any combination)
//   - Tower positioning (lane + slot per tower)
//   - Item levels
//
// Usage in tests:
//   final sim = TdSim();
//   final result = sim.run(comp: ['warrior', 'monk', 'priest', 'hunter', 'mage'],
//                          dungeon: 'windrunner_spire', level: 5);
//   print(result);
//
//   final batch = sim.batch(comp: [...], dungeon: '...', level: 5, runs: 20);
//   print(batch);
// ---------------------------------------------------------------------------

/// Test-friendly class registry that loads from disk instead of rootBundle.
class _DiskClassRegistry extends TdClassRegistry {
  final Map<String, TdClassDef> _diskClasses = {};
  final TdClassDef? _diskFallback;

  _DiskClassRegistry(
      Map<String, dynamic> classesJson, Map<String, dynamic>? fallbackJson)
      : _diskFallback = fallbackJson != null
            ? TdClassDef.fromJson('_fallback', fallbackJson)
            : null {
    for (final entry in classesJson.entries) {
      _diskClasses[entry.key.toLowerCase()] =
          TdClassDef.fromJson(entry.key.toLowerCase(), entry.value);
    }
  }

  @override
  TdClassDef getClass(String className) =>
      _diskClasses[className.toLowerCase()] ?? fallback;

  @override
  TdClassDef get fallback =>
      _diskFallback ?? TdClassDef.fromJson('unknown', {});

  @override
  List<String> get allClassNames => _diskClasses.keys.toList();

  @override
  bool get isLoaded => true;
}

/// Test-friendly hero registry that loads from disk instead of rootBundle.
class _DiskHeroRegistry extends TdHeroRegistry {
  final Map<String, TdClassDef> _heroClassDefs = {};
  final List<WowCharacter> _heroCharacters = [];

  _DiskHeroRegistry(List<dynamic> heroesJson, TdClassRegistry classReg) {
    for (final entry in heroesJson) {
      final json = entry as Map<String, dynamic>;
      final name = json['name'] as String? ?? '';
      final className = json['class'] as String? ?? '';
      final baseDef = classReg.getClass(className);

      // Parse passive
      final passive = json['passive'] != null
          ? PassiveDef.fromJson(
              Map<String, dynamic>.from(json['passive'] as Map))
          : const PassiveDef(name: 'None');
      final empowered = json['empoweredPassive'] != null
          ? PassiveDef.fromJson(
              Map<String, dynamic>.from(json['empoweredPassive'] as Map))
          : null;

      _heroClassDefs[name.toLowerCase()] = TdClassDef(
        name: baseDef.name,
        archetype: baseDef.archetype,
        passive: passive,
        empoweredPassive: empowered,
        attackColor: baseDef.attackColor,
        activeAbility: baseDef.activeAbility,
        ultimateAbility: baseDef.ultimateAbility,
      );

      _heroCharacters.add(WowCharacter(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: name,
        realm: 'Azeroth',
        realmSlug: 'azeroth',
        level: (json['level'] as num?)?.toInt() ?? 90,
        characterClass: className,
        activeSpec: json['spec'] as String? ?? '',
        race: json['race'] as String? ?? '',
        faction: json['faction'] as String? ?? '',
        equippedItemLevel: (json['itemLevel'] as num?)?.toInt() ?? 250,
      ));
    }
  }

  @override
  List<WowCharacter> getHeroes() => _heroCharacters;

  @override
  TdClassDef? getHeroClassDef(
      String characterName, TdClassRegistry classRegistry) {
    return _heroClassDefs[characterName.toLowerCase()];
  }

  @override
  bool get isLoaded => true;
}

// ---------------------------------------------------------------------------
// SimResult — outcome of a single simulation
// ---------------------------------------------------------------------------

class SimResult {
  final String dungeon;
  final int keystoneLevel;
  final List<String> comp;
  final List<TdAffix> affixes;
  final bool cleared;
  final int livesRemaining;
  final int wavesCompleted;
  final int totalWaves;
  final int enemiesKilled;
  final int totalTicks;
  final List<String> waveLog;
  final List<TdCombatLogEntry> combatLog;

  SimResult({
    required this.dungeon,
    required this.keystoneLevel,
    required this.comp,
    required this.affixes,
    required this.cleared,
    required this.livesRemaining,
    required this.wavesCompleted,
    required this.totalWaves,
    required this.enemiesKilled,
    required this.totalTicks,
    this.waveLog = const [],
    this.combatLog = const [],
  });

  double get timeSeconds => totalTicks / 60.0;

  @override
  String toString() => '${cleared ? "CLEAR" : "DEPLETE"} '
      '| Lives: $livesRemaining | Waves: $wavesCompleted/$totalWaves '
      '| Kills: $enemiesKilled | Time: ${timeSeconds.toStringAsFixed(1)}s';

  /// Print the full combat log to stdout.
  void printCombatLog() {
    if (combatLog.isEmpty) {
      print('  (no combat log entries)');
      return;
    }
    print('\n--- Combat Log ($dungeon +$keystoneLevel) ---');
    for (final entry in combatLog) {
      print('  ${entry.message}');
    }
    print('--- End Combat Log (${combatLog.length} entries) ---\n');
  }
}

// ---------------------------------------------------------------------------
// BatchResult — aggregated results from multiple runs
// ---------------------------------------------------------------------------

class BatchResult {
  final String dungeon;
  final int keystoneLevel;
  final List<String> comp;
  final List<TdAffix> affixes;
  final int runs;
  final int clears;
  final double avgLives;
  final double avgWaves;
  final double avgKills;
  final double avgTime;
  final int bestLives;
  final int worstLives;

  BatchResult({
    required this.dungeon,
    required this.keystoneLevel,
    required this.comp,
    required this.affixes,
    required this.runs,
    required this.clears,
    required this.avgLives,
    required this.avgWaves,
    required this.avgKills,
    required this.avgTime,
    required this.bestLives,
    required this.worstLives,
  });

  int get clearRate => (clears / runs * 100).round();

  String get clearRateStr => '$clearRate%';

  @override
  String toString() => 'Clear: $clearRateStr ($clears/$runs) '
      '| Avg Lives: ${avgLives.toStringAsFixed(1)} '
      '| Avg Waves: ${avgWaves.toStringAsFixed(1)} '
      '| Avg Kills: ${avgKills.toStringAsFixed(1)}';
}

// ---------------------------------------------------------------------------
// TdSim — the simulation engine
// ---------------------------------------------------------------------------

class TdSim {
  late final TdClassRegistry classRegistry;
  late final TdHeroRegistry heroRegistry;
  late final Map<String, TdDungeonDef> dungeons;

  TdSim() {
    // Load classes from disk
    final classFile = File('assets/td/classes.json');
    final classData =
        jsonDecode(classFile.readAsStringSync()) as Map<String, dynamic>;
    classRegistry = _DiskClassRegistry(
      classData['classes'] as Map<String, dynamic>? ?? {},
      classData['_fallback'] as Map<String, dynamic>?,
    );

    // Load dungeons from disk
    final dungeonFile = File('assets/td/dungeons.json');
    final dungeonData =
        jsonDecode(dungeonFile.readAsStringSync()) as Map<String, dynamic>;
    final raw = dungeonData['dungeons'] as Map<String, dynamic>? ?? {};
    dungeons = raw.map((key, value) =>
        MapEntry(key, TdDungeonDef.fromJson(key, value as Map<String, dynamic>)));

    // Load heroes from disk
    final heroFile = File('assets/td/heroes.json');
    final heroData =
        jsonDecode(heroFile.readAsStringSync()) as Map<String, dynamic>;
    heroRegistry = _DiskHeroRegistry(
      heroData['heroes'] as List<dynamic>? ?? [],
      classRegistry,
    );
  }

  /// All available class names.
  List<String> get allClasses => classRegistry.allClassNames;

  /// All available dungeon keys.
  List<String> get allDungeonKeys => dungeons.keys.toList();

  /// All available dungeon names.
  List<String> get allDungeonNames =>
      dungeons.values.map((d) => d.name).toList();

  /// Look up a dungeon by key or name (case-insensitive partial match).
  TdDungeonDef findDungeon(String query) {
    final q = query.toLowerCase();
    // Try exact key match first
    if (dungeons.containsKey(q)) return dungeons[q]!;
    // Try key contains
    for (final entry in dungeons.entries) {
      if (entry.key.contains(q)) return entry.value;
    }
    // Try name contains
    for (final entry in dungeons.entries) {
      if (entry.value.name.toLowerCase().contains(q)) return entry.value;
    }
    throw ArgumentError('Dungeon not found: $query. '
        'Available: ${allDungeonKeys.join(', ')}');
  }

  /// Create a mock WoW character.
  WowCharacter _makeChar(String className, {int ilvl = 600}) {
    return WowCharacter(
      id: className.hashCode,
      name: className.replaceAll(' ', ''),
      realm: 'Sim',
      realmSlug: 'sim',
      level: 80,
      characterClass: className,
      activeSpec: 'Spec',
      race: 'Human',
      faction: 'Alliance',
      equippedItemLevel: ilvl,
    );
  }

  // -------------------------------------------------------------------------
  // Single run
  // -------------------------------------------------------------------------

  /// Run a single simulation.
  ///
  /// [comp] — list of class names (e.g. ['warrior', 'monk', 'priest', ...])
  /// [dungeon] — dungeon key or partial name (e.g. 'windrunner' or 'murder_row')
  /// [level] — keystone level (2+)
  /// [affixes] — specific affixes, or null for random
  /// [ilvl] — item level for all towers (default 600)
  /// [slots] — map of towerIndex -> slotIndex (default all mid)
  /// [lanes] — map of towerIndex -> laneIndex (default 2-2-1 split)
  /// [seed] — RNG seed for determinism
  /// [verbose] — print wave-by-wave details
  /// Create a TdRunState with upgrades applied to all towers.
  ///
  /// [sharpenAll] — sharpen stacks on every tower (0-3)
  /// [fortifyAll] — apply fortify to every tower
  /// [empowerAll] — apply empower to every tower
  TdRunState makeRunState({
    required List<String> comp,
    int level = 2,
    int sharpenAll = 0,
    bool fortifyAll = false,
    bool empowerAll = false,
  }) {
    final state = TdRunState(keystoneLevel: level, valor: 999);
    const config = TdBalanceConfig.defaults;
    for (final className in comp) {
      final charId = className.hashCode;
      for (var i = 0; i < sharpenAll; i++) {
        state.purchaseUpgrade(charId, UpgradeType.sharpen, config);
      }
      if (fortifyAll) {
        state.purchaseUpgrade(charId, UpgradeType.fortify, config);
      }
      if (empowerAll) {
        state.purchaseUpgrade(charId, UpgradeType.empower, config);
      }
    }
    return state;
  }

  SimResult run({
    required List<String> comp,
    required String dungeon,
    int level = 2,
    List<TdAffix>? affixes,
    int ilvl = 600,
    Map<int, int>? slots,
    Map<int, int>? lanes,
    int seed = 42,
    bool verbose = false,
    TdRunState? runState,
    bool useHeroes = false,
  }) {
    final dung = findDungeon(dungeon);
    final game = TdGameState();

    List<WowCharacter> characters;
    TdHeroRegistry? heroReg;

    if (useHeroes) {
      final allHeroes = heroRegistry.getHeroes();
      characters = comp.map((name) {
        return allHeroes.firstWhere(
          (h) => h.name.toLowerCase() == name.toLowerCase(),
          orElse: () => _makeChar(name, ilvl: ilvl),
        );
      }).toList();
      heroReg = heroRegistry;
    } else {
      characters = comp.map((c) => _makeChar(c, ilvl: ilvl)).toList();
    }

    // Start run
    game.startRun(characters, level,
        dungeon: dung, classRegistry: classRegistry,
        heroRegistry: heroReg, runState: runState);

    // Override keystone if specific affixes requested
    final ks = affixes != null
        ? KeystoneRun(level: level, affixes: affixes, dungeon: dung)
        : game.keystone;
    if (affixes != null) {
      game.keystone = ks;
    }

    // Deploy towers
    for (var i = 0; i < game.towers.length; i++) {
      final lane = lanes?[i] ??
          (i < 2
              ? 0
              : i < 4
                  ? 1
                  : 2);
      final slot = slots?[i] ?? 1;
      game.moveTower(i, lane, slot: slot);
    }

    if (verbose) {
      print('\n--- Towers ---');
      for (var i = 0; i < game.towers.length; i++) {
        final t = game.towers[i];
        print('  [$i] ${t.character.characterClass}: '
            'Lane ${t.laneIndex}, Slot ${t.slotIndex}, '
            'Dmg ${t.baseDamage.toStringAsFixed(1)}, '
            'Interval ${t.attackInterval.toStringAsFixed(2)}s, '
            'Archetype: ${t.archetype.name}');
      }
      print('  Affixes: ${ks.affixes.map((a) => a.name).join(', ').isEmpty ? 'none' : ks.affixes.map((a) => a.name).join(', ')}');
    }

    game.beginGame();

    const dt = 1.0 / 60.0;
    const maxTicks = 60 * 300; // 5 min max
    var tick = 0;
    var lastWave = 0;
    final waveLog = <String>[];

    while (tick < maxTicks) {
      if (game.currentWave != lastWave) {
        lastWave = game.currentWave;
        final isBoss = game.enemies.any((e) => e.isBoss);
        final avgHp = game.enemies.isNotEmpty
            ? game.enemies.map((e) => e.maxHp).reduce((a, b) => a + b) /
                game.enemies.length
            : 0.0;
        final boss = game.enemies.where((e) => e.isBoss).firstOrNull;

        final log = 'Wave $lastWave${isBoss ? " (BOSS)" : ""}: '
            '${game.enemies.length} enemies, '
            'avgHP=${avgHp.toStringAsFixed(0)}'
            '${boss != null ? ", bossHP=${boss.maxHp.toStringAsFixed(0)}" : ""}'
            ', lives=${game.lives}';
        waveLog.add(log);
        if (verbose) print('  $log');
      }

      game.tick(dt);
      tick++;

      if (game.phase == TdGamePhase.victory ||
          game.phase == TdGamePhase.defeat) {
        break;
      }
      if (game.phase == TdGamePhase.betweenWaves) {
        final log = '  → Cleared wave ${game.currentWave}! '
            'Lives: ${game.lives}, Kills: ${game.enemiesKilled}';
        waveLog.add(log);
        if (verbose) print(log);
        game.nextWave();
      }
    }

    final result = SimResult(
      dungeon: dung.name,
      keystoneLevel: level,
      comp: comp,
      affixes: ks.affixes,
      cleared: game.phase == TdGamePhase.victory,
      livesRemaining: game.lives,
      wavesCompleted: game.currentWave,
      totalWaves: game.totalWaves,
      enemiesKilled: game.enemiesKilled,
      totalTicks: tick,
      waveLog: waveLog,
      combatLog: List.of(game.combatLog),
    );

    if (verbose) {
      print('\n  RESULT: $result');
      result.printCombatLog();
    }

    return result;
  }

  // -------------------------------------------------------------------------
  // Batch runs
  // -------------------------------------------------------------------------

  /// Run multiple simulations with varied seeds.
  BatchResult batch({
    required List<String> comp,
    required String dungeon,
    int level = 2,
    List<TdAffix>? affixes,
    int ilvl = 600,
    int runs = 20,
    TdRunState? runState,
    bool useHeroes = false,
  }) {
    var clears = 0;
    var totalLives = 0;
    var totalWaves = 0;
    var totalKills = 0;
    var totalTicks = 0;
    var bestLives = 0;
    var worstLives = 999;

    for (var i = 0; i < runs; i++) {
      final result = run(
        comp: comp,
        dungeon: dungeon,
        level: level,
        affixes: affixes,
        ilvl: ilvl,
        seed: 1000 + i * 37,
        runState: runState,
        useHeroes: useHeroes,
      );
      if (result.cleared) clears++;
      totalLives += result.livesRemaining;
      totalWaves += result.wavesCompleted;
      totalKills += result.enemiesKilled;
      totalTicks += result.totalTicks;
      if (result.livesRemaining > bestLives) bestLives = result.livesRemaining;
      if (result.livesRemaining < worstLives) {
        worstLives = result.livesRemaining;
      }
    }

    final dung = findDungeon(dungeon);
    return BatchResult(
      dungeon: dung.name,
      keystoneLevel: level,
      comp: comp,
      affixes: affixes ?? [],
      runs: runs,
      clears: clears,
      avgLives: totalLives / runs,
      avgWaves: totalWaves / runs,
      avgKills: totalKills / runs,
      avgTime: totalTicks / runs / 60.0,
      bestLives: bestLives,
      worstLives: worstLives,
    );
  }

  // -------------------------------------------------------------------------
  // Pre-built reports
  // -------------------------------------------------------------------------

  /// Print a dungeon difficulty ranking for a given comp.
  void reportDungeonRanking({
    required List<String> comp,
    int level = 2,
    List<TdAffix>? affixes,
    int runs = 20,
  }) {
    print('\n${'=' * 75}');
    print('DUNGEON DIFFICULTY RANKING — +$level'
        '${affixes != null && affixes.isNotEmpty ? " [${affixes.map((a) => a.name).join(', ')}]" : " (no affixes)"}');
    print('Comp: ${comp.join(', ')}');
    print('${'=' * 75}');
    print('${'Dungeon'.padRight(30)} ${'Clear%'.padRight(8)} ${'AvgLives'.padRight(10)} ${'AvgWaves'.padRight(10)} ${'AvgKills'.padRight(10)}');
    print('-' * 75);

    final results = <BatchResult>[];
    for (final key in allDungeonKeys) {
      results.add(batch(
          comp: comp, dungeon: key, level: level, affixes: affixes, runs: runs));
    }
    // Sort by clear rate then avg lives
    results.sort((a, b) {
      final cmp = b.clearRate.compareTo(a.clearRate);
      if (cmp != 0) return cmp;
      return b.avgLives.compareTo(a.avgLives);
    });

    for (final r in results) {
      print('${r.dungeon.padRight(30)} ${r.clearRateStr.padRight(8)} '
          '${r.avgLives.toStringAsFixed(1).padRight(10)} '
          '${r.avgWaves.toStringAsFixed(1).padRight(10)} '
          '${r.avgKills.toStringAsFixed(1).padRight(10)}');
    }
  }

  /// Print class solo power ranking (5x same class).
  void reportClassRanking({
    String dungeon = 'windrunner_spire',
    int level = 2,
    List<TdAffix>? affixes,
    int runs = 20,
  }) {
    final dung = findDungeon(dungeon);
    print('\n${'=' * 75}');
    print('CLASS POWER RANKING — 5x same class, +$level, ${dung.name}');
    print('${'=' * 75}');
    print('${'Class'.padRight(18)} ${'Archetype'.padRight(10)} ${'Clear%'.padRight(8)} ${'AvgLives'.padRight(10)} ${'AvgWaves'.padRight(10)}');
    print('-' * 75);

    final results = <(String, String, BatchResult)>[];
    for (final className in allClasses) {
      final classDef = classRegistry.getClass(className);
      final r = batch(
        comp: List.filled(5, className),
        dungeon: dungeon,
        level: level,
        affixes: affixes,
        runs: runs,
      );
      results.add((className, classDef.archetype.name, r));
    }
    // Sort by clear rate then avg lives
    results.sort((a, b) {
      final cmp = b.$3.clearRate.compareTo(a.$3.clearRate);
      if (cmp != 0) return cmp;
      return b.$3.avgLives.compareTo(a.$3.avgLives);
    });

    for (final (name, arch, r) in results) {
      print('${name.padRight(18)} ${arch.padRight(10)} ${r.clearRateStr.padRight(8)} '
          '${r.avgLives.toStringAsFixed(1).padRight(10)} '
          '${r.avgWaves.toStringAsFixed(1).padRight(10)}');
    }
  }

  /// Print keystone scaling report.
  void reportKeystoneScaling({
    required List<String> comp,
    String dungeon = 'windrunner_spire',
    List<int> levels = const [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15],
    int runs = 20,
  }) {
    final dung = findDungeon(dungeon);
    print('\n${'=' * 80}');
    print('KEYSTONE SCALING — ${dung.name}');
    print('Comp: ${comp.join(', ')}');
    print('${'=' * 80}');
    print('${'Level'.padRight(8)} ${'Affixes'.padRight(8)} ${'Clear%'.padRight(8)} ${'AvgLives'.padRight(10)} '
        '${'AvgWaves'.padRight(10)} ${'HPMult'.padRight(8)} ${'EnemyHP'.padRight(10)}');
    print('-' * 80);

    for (final level in levels) {
      final affixCount = level >= 7 ? 2 : (level >= 4 ? 1 : 0);
      final affixes = level >= 7
          ? [TdAffix.fortified, TdAffix.bursting]
          : (level >= 4 ? [TdAffix.fortified] : <TdAffix>[]);

      final r = batch(
        comp: comp,
        dungeon: dungeon,
        level: level,
        affixes: affixes,
        runs: runs,
      );

      final hpMult = level <= 10
          ? 1.0 + (level - 2) * 0.12
          : 1.96 + (level - 10) * 0.25 + (level - 10) * (level - 10) * 0.05;
      final baseHp = 200 * hpMult * dung.hpMultiplier;

      print('+$level'.padRight(8) +
          '$affixCount'.padRight(8) +
          r.clearRateStr.padRight(8) +
          r.avgLives.toStringAsFixed(1).padRight(10) +
          r.avgWaves.toStringAsFixed(1).padRight(10) +
          '${hpMult.toStringAsFixed(2)}x'.padRight(8) +
          baseHp.toStringAsFixed(0).padRight(10));
    }
  }

  /// Full matrix: all dungeons × specified key levels.
  void reportMatrix({
    required List<String> comp,
    List<int> levels = const [2, 5, 7, 10],
    int runs = 10,
  }) {
    print('\n${'=' * 80}');
    print('FULL MATRIX — Clear rates (%), no affixes');
    print('Comp: ${comp.join(', ')}');
    print('${'=' * 80}');

    final header = StringBuffer('Dungeon'.padRight(30));
    for (final lvl in levels) {
      header.write('+$lvl'.padLeft(8));
    }
    print(header);
    print('-' * 80);

    for (final key in allDungeonKeys) {
      final dung = dungeons[key]!;
      final row = StringBuffer(dung.name.padRight(30));
      for (final level in levels) {
        final r = batch(
            comp: comp, dungeon: key, level: level, affixes: [], runs: runs);
        row.write(r.clearRateStr.padLeft(8));
      }
      print(row);
    }
  }

  /// Compare multiple comps on a specific dungeon.
  void reportCompComparison({
    required Map<String, List<String>> comps,
    required String dungeon,
    int level = 5,
    List<TdAffix>? affixes,
    int runs = 20,
  }) {
    final dung = findDungeon(dungeon);
    print('\n${'=' * 75}');
    print('COMP COMPARISON — +$level, ${dung.name}'
        '${affixes != null && affixes.isNotEmpty ? " [${affixes.map((a) => a.name).join(', ')}]" : ""}');
    print('${'=' * 75}');
    print('${'Label'.padRight(25)} ${'Clear%'.padRight(8)} ${'AvgLives'.padRight(10)} ${'Best'.padRight(6)} ${'Worst'.padRight(6)} Classes');
    print('-' * 75);

    for (final entry in comps.entries) {
      final r = batch(
        comp: entry.value,
        dungeon: dungeon,
        level: level,
        affixes: affixes,
        runs: runs,
      );
      print('${entry.key.padRight(25)} ${r.clearRateStr.padRight(8)} '
          '${r.avgLives.toStringAsFixed(1).padRight(10)} '
          '${r.bestLives.toString().padRight(6)} '
          '${r.worstLives.toString().padRight(6)} '
          '${entry.value.join(', ')}');
    }
  }
}
