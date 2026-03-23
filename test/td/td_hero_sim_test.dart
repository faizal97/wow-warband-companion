// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'td_sim.dart';

// ---------------------------------------------------------------------------
// TD Hero Simulation Tests
// ---------------------------------------------------------------------------
//
// Compares legendary hero compositions vs normal class compositions across
// all dungeons and keystone levels.
//
// Run all:     flutter test test/td/td_hero_sim_test.dart --reporter expanded
// Run one:     flutter test test/td/td_hero_sim_test.dart --name "hero comp vs class comp"
// ---------------------------------------------------------------------------

void main() {
  late TdSim sim;

  setUpAll(() {
    sim = TdSim();
    final heroes = sim.heroRegistry.getHeroes();
    print('\nLoaded ${sim.allClasses.length} classes: ${sim.allClasses.join(', ')}');
    print('Loaded ${sim.allDungeonKeys.length} dungeons: ${sim.allDungeonNames.join(', ')}');
    print('Loaded ${heroes.length} heroes: ${heroes.map((h) => h.name).join(', ')}');
  });

  // ── Hero comp vs class comp — all dungeons at +2 ──────────────────────────
  test('hero comp vs class comp — all dungeons at +2', () {
    final heroes = sim.heroRegistry.getHeroes();
    final heroNames = heroes.map((h) => h.name).toList();
    final classComp =
        heroes.map((h) => h.characterClass.toLowerCase()).toList();
    // Hero ilvl is 250 — match it for fair comparison
    const ilvl = 250;

    print('\n${"=" * 85}');
    print('HERO COMP VS CLASS COMP — All Dungeons at +2 (ilvl $ilvl)');
    print('Hero comp: ${heroNames.join(", ")}');
    print('Class comp: ${classComp.join(", ")}');
    print('${"=" * 85}');
    print('${"Dungeon".padRight(30)} '
        '${"Heroes%".padRight(10)} '
        '${"Class%".padRight(10)} '
        '${"H.Lives".padRight(10)} '
        '${"C.Lives".padRight(10)} '
        'Winner');
    print('-' * 85);

    var heroWins = 0;
    var classWins = 0;
    var ties = 0;

    for (final key in sim.allDungeonKeys) {
      final heroResult = sim.batch(
        comp: heroNames,
        dungeon: key,
        level: 2,
        ilvl: ilvl,
        affixes: [],
        useHeroes: true,
      );
      final classResult = sim.batch(
        comp: classComp,
        dungeon: key,
        level: 2,
        ilvl: ilvl,
        affixes: [],
      );

      final winner = heroResult.clearRate > classResult.clearRate
          ? 'HEROES'
          : classResult.clearRate > heroResult.clearRate
              ? 'CLASS'
              : heroResult.avgLives > classResult.avgLives
                  ? 'HEROES'
                  : classResult.avgLives > heroResult.avgLives
                      ? 'CLASS'
                      : 'TIE';

      if (winner == 'HEROES') heroWins++;
      if (winner == 'CLASS') classWins++;
      if (winner == 'TIE') ties++;

      print('${heroResult.dungeon.padRight(30)} '
          '${heroResult.clearRateStr.padRight(10)} '
          '${classResult.clearRateStr.padRight(10)} '
          '${heroResult.avgLives.toStringAsFixed(1).padRight(10)} '
          '${classResult.avgLives.toStringAsFixed(1).padRight(10)} '
          '$winner');
    }

    print('-' * 85);
    print('Summary: Heroes $heroWins, Class $classWins, Ties $ties');
  });

  // ── Hero comp keystone scaling ────────────────────────────────────────────
  test('hero comp keystone scaling +2 to +12', () {
    final heroes = sim.heroRegistry.getHeroes();
    final heroNames = heroes.map((h) => h.name).toList();
    final classComp =
        heroes.map((h) => h.characterClass.toLowerCase()).toList();
    const ilvl = 250;
    final levels = [2, 3, 4, 5, 6, 7, 8, 10, 12];

    print('\n${"=" * 75}');
    print('HERO VS CLASS SCALING — Windrunner Spire (ilvl $ilvl)');
    print('${"=" * 75}');
    print('${"Level".padRight(8)} '
        '${"Heroes%".padRight(10)} '
        '${"Class%".padRight(10)} '
        '${"H.Lives".padRight(10)} '
        '${"C.Lives".padRight(10)} '
        'Delta');
    print('-' * 75);

    for (final level in levels) {
      final heroResult = sim.batch(
        comp: heroNames,
        dungeon: 'windrunner_spire',
        level: level,
        ilvl: ilvl,
        affixes: [],
        useHeroes: true,
      );
      final classResult = sim.batch(
        comp: classComp,
        dungeon: 'windrunner_spire',
        level: level,
        ilvl: ilvl,
        affixes: [],
      );

      final delta = heroResult.clearRate - classResult.clearRate;
      final deltaStr =
          delta > 0 ? '+$delta%' : (delta < 0 ? '$delta%' : '0%');

      print('+$level'.padRight(8) +
          heroResult.clearRateStr.padRight(10) +
          classResult.clearRateStr.padRight(10) +
          heroResult.avgLives.toStringAsFixed(1).padRight(10) +
          classResult.avgLives.toStringAsFixed(1).padRight(10) +
          deltaStr);
    }
  });

  // ── Individual hero power ranking ─────────────────────────────────────────
  test('individual hero power ranking', () {
    final heroes = sim.heroRegistry.getHeroes();
    const ilvl = 250;

    print('\n${"=" * 90}');
    print(
        'INDIVIDUAL HERO POWER — 5x same hero vs 5x same class, +2 Windrunner Spire (ilvl $ilvl)');
    print('${"=" * 90}');
    print('${"Hero".padRight(25)} '
        '${"Class".padRight(15)} '
        '${"Hero%".padRight(8)} '
        '${"Class%".padRight(8)} '
        '${"H.Lives".padRight(10)} '
        '${"C.Lives".padRight(10)} '
        'Delta');
    print('-' * 90);

    final rankings = <(String, String, BatchResult, BatchResult)>[];

    for (final hero in heroes) {
      final heroResult = sim.batch(
        comp: List.filled(5, hero.name),
        dungeon: 'windrunner_spire',
        level: 2,
        ilvl: ilvl,
        affixes: [],
        runs: 20,
        useHeroes: true,
      );
      final classResult = sim.batch(
        comp: List.filled(5, hero.characterClass.toLowerCase()),
        dungeon: 'windrunner_spire',
        level: 2,
        ilvl: ilvl,
        affixes: [],
        runs: 20,
      );

      rankings.add((hero.name, hero.characterClass, heroResult, classResult));
    }

    // Sort by hero clear rate descending, then by delta
    rankings.sort((a, b) {
      final cmp = b.$3.clearRate.compareTo(a.$3.clearRate);
      if (cmp != 0) return cmp;
      return b.$3.avgLives.compareTo(a.$3.avgLives);
    });

    for (final (name, cls, heroR, classR) in rankings) {
      final delta = heroR.clearRate - classR.clearRate;
      final deltaStr =
          delta > 0 ? '+$delta%' : (delta < 0 ? '$delta%' : '0%');

      print('${name.padRight(25)} '
          '${cls.padRight(15)} '
          '${heroR.clearRateStr.padRight(8)} '
          '${classR.clearRateStr.padRight(8)} '
          '${heroR.avgLives.toStringAsFixed(1).padRight(10)} '
          '${classR.avgLives.toStringAsFixed(1).padRight(10)} '
          '$deltaStr');
    }
  });

  // ── Hero comp full matrix — all dungeons x key levels ─────────────────────
  test('hero comp full matrix — all dungeons x key levels', () {
    final heroes = sim.heroRegistry.getHeroes();
    final heroNames = heroes.map((h) => h.name).toList();
    final classComp =
        heroes.map((h) => h.characterClass.toLowerCase()).toList();
    const ilvl = 250;
    final levels = [2, 5, 7, 10];

    print('\n${"=" * 90}');
    print('HERO VS CLASS MATRIX — Clear rates (Heroes / Class), ilvl $ilvl');
    print('${"=" * 90}');

    final header = StringBuffer('Dungeon'.padRight(30));
    for (final lvl in levels) {
      header.write('+$lvl'.padLeft(16));
    }
    print(header);
    print('-' * 90);

    for (final key in sim.allDungeonKeys) {
      final dung = sim.findDungeon(key);
      final row = StringBuffer(dung.name.padRight(30));
      for (final level in levels) {
        final heroR = sim.batch(
          comp: heroNames,
          dungeon: key,
          level: level,
          ilvl: ilvl,
          affixes: [],
          runs: 10,
          useHeroes: true,
        );
        final classR = sim.batch(
          comp: classComp,
          dungeon: key,
          level: level,
          ilvl: ilvl,
          affixes: [],
          runs: 10,
        );
        row.write('${heroR.clearRateStr}/${classR.clearRateStr}'.padLeft(16));
      }
      print(row);
    }
  });
}
