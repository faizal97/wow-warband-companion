import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/character.dart';
import 'models/td_models.dart';

// ---------------------------------------------------------------------------
// Game phase
// ---------------------------------------------------------------------------

/// The phases of a tower-defense keystone run.
enum TdGamePhase { setup, playing, betweenWaves, victory, defeat }

// ---------------------------------------------------------------------------
// TdGameState — core game engine
// ---------------------------------------------------------------------------

/// Core game-state engine for the tower-defense mini-game.
///
/// Manages waves, enemy spawning, tower attacks, affix effects, and
/// win/lose conditions. Designed to be driven by a game loop that calls
/// [tick] every frame.
class TdGameState extends ChangeNotifier {
  // ---- configuration ----
  static const int totalWaves = 5;

  // ---- run parameters ----
  late KeystoneRun keystone;
  late List<TdTower> towers;

  // ---- live state ----
  List<TdEnemy> enemies = [];
  List<SanguinePool> sanguinePools = [];
  List<TdHitEvent> hitEvents = [];
  TdGamePhase phase = TdGamePhase.setup;
  int currentWave = 0;
  int lives = 20;
  static const int maxLives = 20;
  int enemiesKilled = 0;

  // ---- internal ----
  int _enemyIdCounter = 0;
  final Map<int, double> _towerCooldowns = {};
  final Random _rng = Random();

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Initialise a new run with the selected characters and keystone level.
  void startRun(List<WowCharacter> selectedCharacters, int keystoneLevel, {TdDungeon? dungeon}) {
    keystone = KeystoneRun.generate(keystoneLevel, dungeon: dungeon);

    towers = List.generate(selectedCharacters.length, (i) {
      return TdTower(
        character: selectedCharacters[i],
        laneIndex: -1, // unassigned — player must deploy
      );
    });

    enemies = [];
    sanguinePools = [];
    hitEvents = [];
    phase = TdGamePhase.setup;
    currentWave = 0;
    lives = maxLives;
    enemiesKilled = 0;
    _enemyIdCounter = 0;
    _towerCooldowns.clear();

    notifyListeners();
  }

  /// Transition from setup to the first wave.
  void beginGame() {
    phase = TdGamePhase.playing;
    currentWave = 1;
    _spawnWave();
    notifyListeners();
  }

  /// Move a tower to a different lane (0-2).
  void moveTower(int towerIndex, int newLane) {
    if (towerIndex < 0 || towerIndex >= towers.length) return;
    final clamped = newLane.clamp(0, 2);
    final old = towers[towerIndex];

    // Preserve mutable state across the replacement.
    final replacement = TdTower(
      character: old.character,
      laneIndex: clamped,
    )
      ..isDebuffed = old.isDebuffed
      ..debuffTimer = old.debuffTimer;

    towers[towerIndex] = replacement;
    notifyListeners();
  }

  /// Advance to the next wave from the between-waves phase.
  void nextWave() {
    if (phase != TdGamePhase.betweenWaves) return;
    currentWave++;
    phase = TdGamePhase.playing;
    _spawnWave();
    notifyListeners();
  }

  /// Main game-loop tick. Call every frame with [dt] in seconds.
  void tick(double dt) {
    if (phase != TdGamePhase.playing) return;

    // 1. Move enemies
    for (final e in enemies) {
      if (!e.isDead) {
        e.position += e.speed * e.speedMultiplier * dt;
      }
    }

    // 2. Check enemies reaching the end — lose lives
    for (final e in enemies) {
      if (!e.isDead && e.reachedEnd) {
        lives -= e.isBoss ? 5 : 1;
        e.hp = 0; // remove from play
      }
    }

    // 3. Check defeat
    if (lives <= 0) {
      lives = 0;
      phase = TdGamePhase.defeat;
      notifyListeners();
      return;
    }

    // 4. Tower attacks
    _processTowerAttacks(dt);

    // 5. Process death affixes on freshly killed enemies (hp == 0)
    for (final e in enemies) {
      if (e.hp == 0) {
        _processDeathAffixes(e);
        e.hp = -1; // mark as fully processed
        enemiesKilled++;
      }
    }

    // 6. Update sanguine pools
    _updateSanguinePools(dt);

    // 7. Update tower debuff timers
    for (final t in towers) {
      if (t.isDebuffed) {
        t.debuffTimer -= dt;
        if (t.debuffTimer <= 0) {
          t.debuffTimer = 0;
          t.isDebuffed = false;
        }
      }
    }

    // 7b. Age hit events and remove expired
    for (final h in hitEvents) {
      h.age += dt;
    }
    hitEvents.removeWhere((h) => h.isExpired);

    // 8. Remove fully dead enemies
    enemies.removeWhere((e) => e.isDead);

    // 9. Check wave complete
    if (enemies.isEmpty) {
      if (currentWave >= totalWaves) {
        phase = TdGamePhase.victory;
      } else {
        phase = TdGamePhase.betweenWaves;
      }
    }

    notifyListeners();
  }

  // -----------------------------------------------------------------------
  // Tower attack logic
  // -----------------------------------------------------------------------

  void _processTowerAttacks(double dt) {
    for (var i = 0; i < towers.length; i++) {
      final tower = towers[i];

      // Healers don't attack — they passively buff adjacent towers.
      if (tower.archetype == TowerArchetype.healer) continue;

      // Advance cooldown.
      final remaining = (_towerCooldowns[i] ?? 0) - dt;
      if (remaining > 0) {
        _towerCooldowns[i] = remaining;
        continue;
      }

      // Ready to fire — reset cooldown.
      _towerCooldowns[i] = tower.attackInterval;

      // Calculate damage with healer adjacency buff.
      double damage = tower.effectiveDamage;
      final hasHealerBuff = towers.any((t) =>
          t.archetype == TowerArchetype.healer &&
          (t.laneIndex - tower.laneIndex).abs() <= 1);
      if (hasHealerBuff) {
        damage *= 1.3;
      }

      // Find targets — only enemies with position >= 0 in the tower's lane.
      final laneEnemies = enemies
          .where((e) => !e.isDead && e.laneIndex == tower.laneIndex && e.position >= 0)
          .toList();
      if (laneEnemies.isEmpty) continue;

      // Tower visual X (normalized 0-1, towers are near the goal = position ~0.95)
      const towerX = 0.95;

      switch (tower.archetype) {
        case TowerArchetype.melee:
          laneEnemies.sort((a, b) => b.position.compareTo(a.position));
          final target = laneEnemies.first;
          target.hp = (target.hp - damage).clamp(0, target.maxHp);
          hitEvents.add(TdHitEvent(
            towerLane: tower.laneIndex, towerX: towerX,
            enemyId: target.id, enemyLane: target.laneIndex,
            enemyX: target.position, damage: damage,
          ));
          break;

        case TowerArchetype.ranged:
          laneEnemies.sort((a, b) => a.position.compareTo(b.position));
          final target = laneEnemies.first;
          final dmg = damage * 0.8;
          target.hp = (target.hp - dmg).clamp(0, target.maxHp);
          hitEvents.add(TdHitEvent(
            towerLane: tower.laneIndex, towerX: towerX,
            enemyId: target.id, enemyLane: target.laneIndex,
            enemyX: target.position, damage: dmg,
          ));
          break;

        case TowerArchetype.aoe:
          for (final target in laneEnemies) {
            final dmg = damage * 0.4;
            target.hp = (target.hp - dmg).clamp(0, target.maxHp);
            hitEvents.add(TdHitEvent(
              towerLane: tower.laneIndex, towerX: towerX,
              enemyId: target.id, enemyLane: target.laneIndex,
              enemyX: target.position, damage: dmg, isAoe: true,
            ));
          }
          break;

        case TowerArchetype.healer:
          break;
      }
    }
  }

  // -----------------------------------------------------------------------
  // Wave spawning
  // -----------------------------------------------------------------------

  void _spawnWave() {
    // Base HP scales with wave number so later waves are harder.
    // A 620 ilvl melee tower does ~62 dmg every 0.8s = 77 DPS.
    // At wave 1, enemies should take ~3-4s to kill with one tower.
    final waveScale = 1.0 + (currentWave - 1) * 0.3; // +30% HP per wave
    final baseHp = 250.0 * keystone.hpMultiplier * waveScale;

    if (currentWave == totalWaves) {
      // Boss wave
      final bossHp = baseHp * 8.0 * (keystone.hasTyrannical ? 1.5 : 1.0);
      final bossLane = _rng.nextInt(3);
      enemies.add(TdEnemy(
        id: 'e${_enemyIdCounter++}',
        maxHp: bossHp,
        speed: 0.04,
        laneIndex: bossLane,
        isBoss: true,
      ));

      // 5 adds across lanes, staggered
      for (var i = 0; i < 5; i++) {
        enemies.add(TdEnemy(
          id: 'e${_enemyIdCounter++}',
          maxHp: baseHp * 0.6,
          speed: 0.10 + _rng.nextDouble() * 0.05,
          laneIndex: _rng.nextInt(3),
        )..position = -(i + 1) * 0.12);
      }
    } else {
      // Regular wave: more enemies as waves progress
      final count = 6 + currentWave * 2 + _rng.nextInt(3); // 8-17 enemies
      final hpMod = keystone.hasFortified ? 1.3 : 1.0;

      for (var i = 0; i < count; i++) {
        enemies.add(TdEnemy(
          id: 'e${_enemyIdCounter++}',
          maxHp: baseHp * hpMod,
          speed: 0.10 + _rng.nextDouble() * 0.06,
          laneIndex: _rng.nextInt(3),
        )..position = -i * 0.10);
      }
    }
  }

  // -----------------------------------------------------------------------
  // Death affix processing
  // -----------------------------------------------------------------------

  void _processDeathAffixes(TdEnemy enemy) {
    // Bolstering — surviving enemies in same lane get faster.
    if (keystone.hasBolstering) {
      for (final e in enemies) {
        if (!e.isDead && e.laneIndex == enemy.laneIndex && e != enemy) {
          e.speedMultiplier *= 1.1;
        }
      }
    }

    // Bursting — towers in the dead enemy's lane are debuffed for 2 seconds.
    if (keystone.hasBursting) {
      for (final t in towers) {
        if (t.laneIndex == enemy.laneIndex) {
          t.isDebuffed = true;
          t.debuffTimer = 2.0;
        }
      }
    }

    // Sanguine — drop a healing pool at the enemy's position.
    if (keystone.hasSanguine) {
      sanguinePools.add(SanguinePool(
        laneIndex: enemy.laneIndex,
        position: enemy.position,
      ));
    }
  }

  // -----------------------------------------------------------------------
  // Sanguine pool update
  // -----------------------------------------------------------------------

  void _updateSanguinePools(double dt) {
    for (final pool in sanguinePools) {
      pool.timer -= dt;

      // Heal nearby enemies.
      for (final e in enemies) {
        if (!e.isDead &&
            e.laneIndex == pool.laneIndex &&
            (e.position - pool.position).abs() <= 0.05) {
          e.hp = (e.hp + e.maxHp * 0.15 * dt).clamp(0, e.maxHp);
        }
      }
    }

    sanguinePools.removeWhere((p) => p.isExpired);
  }
}
