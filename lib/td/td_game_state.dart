import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/character.dart';
import 'data/effect_types.dart';
import 'data/td_balance_config.dart';
import 'data/td_class_registry.dart';
import 'data/td_hero_registry.dart';
import 'data/td_run_state.dart';
import 'effects/tower_effects.dart';
import 'effects/enemy_effects.dart';
import 'effects/boss_effects.dart';
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
  TdBalanceConfig config = TdBalanceConfig.defaults;
  TdRunState? runState;
  int get totalWaves => config.totalWaves;

  // ---- run parameters ----
  late KeystoneRun keystone;
  late List<TdTower> towers;

  // ---- live state ----
  List<TdEnemy> enemies = [];
  List<SanguinePool> sanguinePools = [];
  List<TdHitEvent> hitEvents = [];
  TdGamePhase phase = TdGamePhase.setup;
  int currentWave = 0;
  late int lives;
  int get maxLives => config.startingLives;
  int enemiesKilled = 0;

  // ---- boss mechanic state ----
  Map<String, dynamic> _bossState = {};
  List<FireZone> _fireZones = [];
  bool _bossReflecting = false;

  /// Fire zones visible to the UI for rendering.
  List<FireZone> get fireZones => _fireZones;

  // ---- lane preview (pre-computed for UI) ----
  List<int> _nextWaveLaneCounts = [0, 0, 0];
  List<int> get nextWaveLaneCounts => _nextWaveLaneCounts;

  // ---- internal ----
  int _enemyIdCounter = 0;
  final Map<int, double> _towerCooldowns = {};
  final Random _rng = Random();

  /// Seed for the next wave's lane assignment, so preview matches reality.
  int _nextWaveSeed = 0;

  /// Star rating based on lives remaining (only valid in victory phase).
  int get starRating {
    if (phase != TdGamePhase.victory) return 0;
    if (lives >= maxLives) return 3;     // Flawless: 0 lives lost
    if (lives >= maxLives * 0.75) return 2; // Clean: 75%+ lives
    return 1;                              // Scraped by
  }

  /// Keystone level change after the run.
  /// Victory: +1 to +3 based on stars. Defeat: -1 (min stays at 2).
  int get keystoneLevelChange {
    if (phase == TdGamePhase.victory) return starRating;
    if (phase == TdGamePhase.defeat) return -1;
    return 0;
  }

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Initialise a new run with the selected characters and keystone level.
  void startRun(
    List<WowCharacter> selectedCharacters,
    int keystoneLevel, {
    required TdDungeonDef dungeon,
    required TdClassRegistry classRegistry,
    TdHeroRegistry? heroRegistry,
    TdBalanceConfig? balanceConfig,
    TdRunState? runState,
  }) {
    config = balanceConfig ?? config;
    this.runState = runState;
    keystone = KeystoneRun.generate(keystoneLevel, dungeon: dungeon);

    towers = List.generate(selectedCharacters.length, (i) {
      var classDef = heroRegistry?.getHeroClassDef(
              selectedCharacters[i].name, classRegistry) ??
          classRegistry.getClass(selectedCharacters[i].characterClass);
      // Apply Empower upgrade: swap to empowered passive
      final upgrades = runState?.getUpgrades(selectedCharacters[i].id);
      if (upgrades != null && upgrades.hasEmpower && classDef.empoweredPassive != null) {
        classDef = TdClassDef(
          name: classDef.name,
          archetype: classDef.archetype,
          passive: classDef.empoweredPassive!,
          empoweredPassive: classDef.empoweredPassive,
          attackColor: classDef.attackColor,
        );
      }
      return TdTower(
        character: selectedCharacters[i],
        classDef: classDef,
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
    _bossState = {};
    _fireZones = [];
    _bossReflecting = false;
    _nextWaveLaneCounts = [0, 0, 0];
    _nextWaveSeed = 0;

    // Pre-compute wave 1 lane preview so setup phase can show it
    _computeWave1Preview();

    notifyListeners();
  }

  /// Pre-compute wave 1 preview (called during startRun for setup phase).
  void _computeWave1Preview() {
    _nextWaveSeed = _rng.nextInt(1 << 30);
    final pattern = keystone.dungeon.lanePattern;
    final previewRng = Random(_nextWaveSeed);
    final enemyCount = (config.spawnBaseCount + 1 * config.spawnCountPerWave + keystone.dungeon.enemyCountModifier)
        .clamp(config.spawnMinCount, config.spawnMaxCount);
    final counts = [0, 0, 0];
    for (var i = 0; i < enemyCount; i++) {
      counts[_assignLaneWith(pattern, i, enemyCount, previewRng)]++;
    }
    _nextWaveLaneCounts = counts;
  }

  /// Transition from setup to the first wave.
  void beginGame() {
    phase = TdGamePhase.playing;
    currentWave = 1;
    _spawnWave();
    notifyListeners();
  }

  /// Move a tower to a lane (0-2) and slot (0=front, 1=mid, 2=back).
  /// Returns false if the slot is already occupied.
  bool moveTower(int towerIndex, int newLane, {int slot = 1}) {
    if (towerIndex < 0 || towerIndex >= towers.length) return false;
    towers[towerIndex].laneIndex = newLane.clamp(0, 2);
    towers[towerIndex].slotIndex = slot.clamp(0, 2);
    notifyListeners();
    return true;
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

    // 1. Move enemies (apply speed * speedMultiplier * slow effects * dt)
    for (final e in enemies) {
      if (!e.isDead) {
        var slowFactor = 1.0;
        for (final effect in e.statusEffects) {
          if (effect.type == 'slow') {
            slowFactor *= (1.0 - effect.slowAmount);
          }
        }
        e.position += e.speed * e.speedMultiplier * slowFactor * dt;
      }
    }

    // 2. Process enemy modifier ticks (lane_switch, phase, ranged_attack,
    //    accelerate, frost_aura)
    _processEnemyModifiers(dt);

    // 3. Process enemy status effects (DoT damage ticks, slow decay)
    _processStatusEffects(dt);

    // 4. Check enemies reaching the end — lose lives
    for (final e in enemies) {
      if (!e.isDead && e.reachedEnd) {
        var leakCost = e.isBoss ? 5 : 1;
        // Fortify upgrade: reduces boss leak cost only
        if (e.isBoss && runState != null) {
          final hasFortify = towers.any((t) =>
              t.laneIndex == e.laneIndex &&
              (runState!.getUpgrades(t.character.id)?.hasFortify ?? false));
          if (hasFortify) {
            leakCost = (leakCost - config.fortifyBossLeakReduction).clamp(1, leakCost);
          }
        }
        lives -= leakCost;
        e.hp = 0; // remove from play
      }
    }

    // 5. Check defeat
    if (lives <= 0) {
      lives = 0;
      phase = TdGamePhase.defeat;
      notifyListeners();
      return;
    }

    // 6. Tower attacks (delegate to TowerEffectProcessor)
    _processTowerAttacks(dt);

    // 7. Process boss mechanics (delegate to BossEffectProcessor)
    _processBossMechanics(dt);

    // 8. Update fire zones (damage towers, decay timers)
    _updateFireZones(dt);

    // 9. Process death: affixes + enemy resurrect + boss split_on_death
    _processDeaths();

    // 10. Update sanguine pools
    _updateSanguinePools(dt);

    // 11. Update tower debuff timers + cleanse_adjacent
    for (final t in towers) {
      if (t.isDebuffed) {
        t.debuffTimer -= dt;
        if (t.debuffTimer <= 0) {
          t.debuffTimer = 0;
          t.isDebuffed = false;
        }
      }
      // Cleanse adjacent towers (empowered Paladin)
      if (t.laneIndex >= 0) {
        for (final eff in t.classDef.passive.effects) {
          if (eff.type == 'cleanse_adjacent') {
            for (final adj in towers) {
              if (adj != t &&
                  adj.isDebuffed &&
                  (adj.laneIndex - t.laneIndex).abs() <= 1) {
                adj.isDebuffed = false;
                adj.debuffTimer = 0;
              }
            }
          }
        }
      }
    }

    // 12. Age hit events and remove expired
    for (final h in hitEvents) {
      h.age += dt;
    }
    hitEvents.removeWhere((h) => h.isExpired);

    // 13. Remove dead enemies
    enemies.removeWhere((e) => e.isDead);

    // 14. Check wave complete
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
  // Enemy modifier processing
  // -----------------------------------------------------------------------

  void _processEnemyModifiers(double dt) {
    for (final enemy in enemies) {
      if (enemy.isDead || enemy.modifiers.isEmpty) continue;

      final results = EnemyEffectProcessor.processTick(
        modifiers: enemy.modifiers,
        state: enemy.modifierState,
        position: enemy.position,
        laneIndex: enemy.laneIndex,
        dt: dt,
        rng: _rng,
      );

      for (final result in results) {
        switch (result) {
          case SwitchLaneResult(:final newLane):
            enemy.laneIndex = newLane;
          case AttackTowerResult(:final lane, :final damage):
            for (final t in towers) {
              if (t.laneIndex == lane && !t.isImmuneToDebuff) {
                t.isDebuffed = true;
                t.debuffTimer = (t.debuffTimer + damage * 0.1).clamp(0, 3);
              }
            }
          case SetSpeedResult(:final multiplier):
            enemy.speedMultiplier = multiplier;
          case SlowTowersResult():
            // frost_aura effect — applied as a temporary attack speed debuff,
            // handled elsewhere via flag reading
            break;
        }
      }
    }
  }

  // -----------------------------------------------------------------------
  // Status effect processing (DoTs, slows)
  // -----------------------------------------------------------------------

  void _processStatusEffects(double dt) {
    for (final enemy in enemies) {
      if (enemy.isDead) continue;

      // Process each status effect
      enemy.statusEffects.removeWhere((effect) {
        effect.remaining -= dt;
        if (effect.remaining <= 0) return true; // remove expired

        if (effect.type == 'dot') {
          // Apply DoT damage — proportional damage per frame
          final tickInterval = effect.tickInterval;
          enemy.hp -= effect.dotDamage * (dt / tickInterval);
          enemy.hp = enemy.hp.clamp(0, enemy.maxHp);
        }
        // Slow effects are read directly by movement code

        return false;
      });
    }
  }

  // -----------------------------------------------------------------------
  // Tower attack logic
  // -----------------------------------------------------------------------

  void _processTowerAttacks(double dt) {
    // Compute buff multipliers from support towers
    final damageBuff = <int, double>{}; // lane -> multiplier
    final speedBuff = <int, double>{}; // lane -> multiplier

    for (final tower in towers) {
      if (tower.laneIndex < 0) continue;
      for (final effect in tower.classDef.passive.effects) {
        if (effect.type == 'buff_adjacent_damage') {
          for (var lane = 0; lane < 3; lane++) {
            if ((lane - tower.laneIndex).abs() <= 1) {
              damageBuff[lane] =
                  (damageBuff[lane] ?? 1.0) * (1.0 + effect.value);
            }
          }
        }
        if (effect.type == 'buff_adjacent_speed') {
          for (var lane = 0; lane < 3; lane++) {
            if ((lane - tower.laneIndex).abs() <= 1) {
              speedBuff[lane] =
                  (speedBuff[lane] ?? 1.0) * (1.0 - effect.value);
            }
          }
        }
      }
    }

    for (var i = 0; i < towers.length; i++) {
      final tower = towers[i];
      if (tower.laneIndex < 0) continue;
      if (tower.archetype == TowerArchetype.support) continue;

      // Always advance charge timer for charge_attack towers (every frame)
      final hasChargeAttack = tower.classDef.passive.effects
          .any((e) => e.type == 'charge_attack');
      if (hasChargeAttack && (_towerCooldowns[i] ?? 0) > 0) {
        // Accumulate charge time every tick while on cooldown
        tower.chargeTimer += dt;
      }

      // Advance cooldown (apply speed buff)
      final cooldownMult = speedBuff[tower.laneIndex] ?? 1.0;
      final remaining = (_towerCooldowns[i] ?? 0) - dt;
      if (remaining > 0) {
        _towerCooldowns[i] = remaining;
        continue;
      }
      _towerCooldowns[i] = tower.attackIntervalWith(config) * cooldownMult;

      // Compute damage with buff + Sharpen upgrade
      final dmgMult = damageBuff[tower.laneIndex] ?? 1.0;
      final sharpenMult = runState?.getUpgrades(tower.character.id)
              ?.sharpenMultiplier(config) ?? 1.0;
      var baseDamage = tower.effectiveDamage * dmgMult * sharpenMult;

      // Apply archetype damage modifier from config
      switch (tower.archetype) {
        case TowerArchetype.ranged:
          baseDamage *= config.rangedDamageMult;
        case TowerArchetype.aoe:
          baseDamage *= config.aoeDamageMult;
        default:
          break;
      }

      // Build enemy list for processor
      final enemyRecords = enemies
          .where((e) => !e.isDead && e.position >= 0)
          .map((e) =>
              (id: e.id, hp: e.hp, position: e.position, lane: e.laneIndex))
          .toList();

      // Increment attack counter
      tower.attackCount++;

      final result = TowerEffectProcessor.processAttack(
        archetype: tower.archetype,
        classDef: tower.classDef,
        towerLane: tower.laneIndex,
        enemies: enemyRecords,
        baseDamage: baseDamage,
        attackCount: tower.attackCount,
        chargeTimer: tower.chargeTimer,
        dt: dt,
        rng: _rng,
      );

      if (result.isCharging) {
        // Keep short cooldown so we re-check soon, but charge accumulates above
        _towerCooldowns[i] = 0.1;
        continue;
      }
      tower.chargeTimer = 0; // reset after firing

      // Apply hits
      final towerX = tower.slotPosition;
      for (final hit in result.hits) {
        final enemy = enemies.firstWhere((e) => e.id == hit.enemyId,
            orElse: () => enemies.first);

        // Apply damage through enemy modifier filter
        final actualDamage = EnemyEffectProcessor.modifyIncomingDamage(
          modifiers: enemy.modifiers,
          state: enemy.modifierState,
          rawDamage: hit.damage,
          position: enemy.position,
        );

        // Check reflect
        if (_bossReflecting && enemy.isBoss) {
          // Damage the tower instead (unless immune)
          if (!tower.isImmuneToDebuff) {
            tower.isDebuffed = true;
            tower.debuffTimer = 0.5;
          }
        } else {
          enemy.hp = (enemy.hp - actualDamage).clamp(0, enemy.maxHp);
        }

        hitEvents.add(TdHitEvent(
          towerLane: tower.laneIndex,
          towerX: towerX,
          enemyId: hit.enemyId,
          enemyLane: hit.enemyLane,
          enemyX: hit.enemyPosition,
          damage: actualDamage,
          archetype: tower.archetype,
          attackColor: tower.attackColor,
          isCrit: result.didCrit,
          isAoe: tower.archetype == TowerArchetype.aoe,
        ));
      }

      // Apply status effects
      for (final effect in result.newStatusEffects) {
        final enemy =
            enemies.where((e) => e.id == effect.sourceId).firstOrNull;
        if (enemy != null) {
          enemy.statusEffects.add(effect);
        }
      }
    }
  }

  // -----------------------------------------------------------------------
  // Boss mechanics
  // -----------------------------------------------------------------------

  void _processBossMechanics(double dt) {
    final boss = enemies.where((e) => e.isBoss && !e.isDead).firstOrNull;
    if (boss == null) return;

    final events = BossEffectProcessor.processTick(
      modifiers: keystone.dungeon.bossModifiersForLevel(keystone.level),
      state: _bossState,
      bossHpFraction: boss.hpFraction,
      bossLane: boss.laneIndex,
      towerCount: towers.where((t) => t.laneIndex >= 0).length,
      dt: dt,
      rng: _rng,
    );

    for (final event in events) {
      switch (event) {
        case SpawnAddEvent(:final hp, :final speed, :final laneIndex):
          enemies.add(TdEnemy(
            id: 'e${_enemyIdCounter++}',
            maxHp: boss.maxHp * hp,
            speed: speed,
            laneIndex: laneIndex,
          ));
        case FireZoneEvent(:final laneIndex, :final duration):
          _fireZones.add(FireZone(laneIndex: laneIndex, timer: duration));
        case BossTeleportEvent(:final newLane):
          boss.laneIndex = newLane;
        case KnockbackTowerEvent(:final towerIndex, :final newLane):
          if (towerIndex < towers.length) {
            // Find an open slot in the new lane
            final openSlots = [0, 1, 2]
                .where((s) => !towers.any(
                    (t) => t.laneIndex == newLane && t.slotIndex == s))
                .toList();
            final newSlot = openSlots.isNotEmpty
                ? openSlots[_rng.nextInt(openSlots.length)]
                : towers[towerIndex].slotIndex;
            towers[towerIndex].laneIndex = newLane;
            towers[towerIndex].slotIndex = newSlot;
          }
        case ReflectDamageToggleEvent(:final active):
          _bossReflecting = active;
        case WindPushEvent(:final laneIndex, :final pushAmount):
          for (final e in enemies) {
            if (e.laneIndex == laneIndex && !e.isDead) {
              e.position += pushAmount;
            }
          }
        case StackingDamageTickEvent(:final damagePerTower):
          for (final t in towers) {
            if (t.laneIndex >= 0 && !t.isImmuneToDebuff) {
              t.debuffTimer += damagePerTower;
              if (t.debuffTimer > 1.0) {
                t.isDebuffed = true;
              }
            }
          }
        case SplitOnDeathEvent():
          // Handled in death processing, not here
          break;
      }
    }

    // Check enrage state
    if (_bossState['enraged'] == true) {
      final mult = (_bossState['enrage_speed_mult'] as double?) ?? 2.0;
      boss.speedMultiplier = mult;
    }
  }

  // -----------------------------------------------------------------------
  // Fire zone update
  // -----------------------------------------------------------------------

  void _updateFireZones(double dt) {
    for (final zone in _fireZones) {
      zone.timer -= dt;
      // Damage/debuff towers in the zone's lane
      for (final t in towers) {
        if (t.laneIndex == zone.laneIndex && !t.isImmuneToDebuff) {
          t.isDebuffed = true;
          t.debuffTimer = 0.5; // short debuff pulses
        }
      }
    }
    _fireZones.removeWhere((z) => z.isExpired);
  }

  // -----------------------------------------------------------------------
  // Wave spawning
  // -----------------------------------------------------------------------

  void _spawnWave() {
    final dungeon = keystone.dungeon;
    final waveScale = 1.0 + (currentWave - 1) * config.waveHpScalePerWave;
    final baseHp =
        config.baseEnemyHp * keystone.hpMultiplierWith(config) * dungeon.hpMultiplier * waveScale;
    final baseSpeed = config.baseEnemySpeed * dungeon.speedMultiplier;

    if (currentWave == totalWaves) {
      _spawnBossWave(baseHp, baseSpeed, dungeon);
    } else {
      _spawnRegularWave(baseHp, baseSpeed, dungeon);
    }

    // Pre-compute next wave lane preview
    _computeNextWaveLanePreview();
  }

  void _spawnRegularWave(
      double baseHp, double baseSpeed, TdDungeonDef dungeon) {
    final count =
        (config.spawnBaseCount + currentWave * config.spawnCountPerWave + dungeon.enemyCountModifier)
            .clamp(config.spawnMinCount, config.spawnMaxCount);
    final hpMod = keystone.hasFortified ? config.fortifiedHpMult : 1.0;

    // Use the same seed as the preview so lane assignments match
    final laneRng = Random(_nextWaveSeed);

    for (var i = 0; i < count; i++) {
      final modifiers =
          EnemyEffectProcessor.rollSpawnModifiers(
              dungeon.enemyModifiersForLevel(keystone.level), _rng);
      final modifierState = EnemyEffectProcessor.initModifierState(modifiers);

      enemies.add(TdEnemy(
        id: 'e${_enemyIdCounter++}',
        maxHp: baseHp * hpMod,
        speed: baseSpeed + _rng.nextDouble() * config.spawnSpeedVariance,
        laneIndex: _assignLaneWith(dungeon.lanePattern, i, count, laneRng),
        modifiers: modifiers,
        modifierState: modifierState,
      )..position = -i * config.spawnStaggerDistance);
    }
  }

  void _spawnBossWave(double baseHp, double baseSpeed, TdDungeonDef dungeon) {
    final bossHp = baseHp * config.bossHpMultiplier * (keystone.hasTyrannical ? config.tyrannicalHpMult : 1.0);
    final bossSpeed = config.bossSpeed * dungeon.speedMultiplier;

    // Use the same seed as preview for deterministic lane assignment
    final laneRng = Random(_nextWaveSeed);
    final bossLane = laneRng.nextInt(3);

    // Initialize boss state from dungeon boss modifiers
    _bossState = BossEffectProcessor.initBossState(dungeon.bossModifiersForLevel(keystone.level));

    enemies.add(TdEnemy(
      id: 'e${_enemyIdCounter++}',
      maxHp: bossHp,
      speed: bossSpeed,
      laneIndex: bossLane,
      isBoss: true,
    ));

    // Adds across lanes, staggered — with same modifiers as regular enemies
    for (var i = 0; i < config.bossAddsCount; i++) {
      final modifiers =
          EnemyEffectProcessor.rollSpawnModifiers(
              dungeon.enemyModifiersForLevel(keystone.level), _rng);
      final modifierState = EnemyEffectProcessor.initModifierState(modifiers);

      enemies.add(TdEnemy(
        id: 'e${_enemyIdCounter++}',
        maxHp: baseHp * config.bossAddsHpFraction,
        speed: baseSpeed + _rng.nextDouble() * config.bossAddsSpeedVariance,
        laneIndex: laneRng.nextInt(3),
        modifiers: modifiers,
        modifierState: modifierState,
      )..position = -(i + 1) * config.bossAddsStaggerDistance);
    }
  }

  // -----------------------------------------------------------------------
  // Lane assignment
  // -----------------------------------------------------------------------

  /// Assign a lane using a specific [rng] — allows preview and spawn to share
  /// the same seed for deterministic results.
  int _assignLaneWith(LanePatternDef pattern, int index, int totalCount, Random rng) {
    switch (pattern.type) {
      case 'spread':
        return rng.nextInt(3);
      case 'heavy_center':
        final weight =
            (pattern.params['centerWeight'] as num?)?.toDouble() ?? 0.6;
        return rng.nextDouble() < weight ? 1 : (rng.nextBool() ? 0 : 2);
      case 'sequential':
        return index % 3;
      case 'zerg':
        return rng.nextInt(3); // all lanes, just more enemies
      case 'packs':
        final packSize =
            (pattern.params['packSize'] as num?)?.toInt() ?? 3;
        return (index ~/ packSize) % 3;
      case 'weakest_lane':
        // Guarantee minimum 2 enemies per lane, then flood weakest
        if (index < 6) return index % 3; // first 6 enemies: 2 per lane
        // Remaining enemies go to lane with fewest towers
        final counts = [0, 0, 0];
        for (final t in towers) {
          if (t.laneIndex >= 0) counts[t.laneIndex]++;
        }
        final minCount = counts.reduce((a, b) => a < b ? a : b);
        final weakLanes = [
          for (var i = 0; i < 3; i++)
            if (counts[i] == minCount) i,
        ];
        return weakLanes[rng.nextInt(weakLanes.length)];
      case 'drift':
      case 'lane_switch':
        return rng.nextInt(3); // random start, modifier handles switching
      default:
        return rng.nextInt(3);
    }
  }

  // -----------------------------------------------------------------------
  // Next wave lane preview
  // -----------------------------------------------------------------------

  void _computeNextWaveLanePreview() {
    final nextWave = currentWave + 1;
    if (nextWave > totalWaves) {
      _nextWaveLaneCounts = [0, 0, 0];
      return;
    }

    // Generate a seed for this wave — the actual spawn will use the same seed
    _nextWaveSeed = _rng.nextInt(1 << 30);

    final counts = [0, 0, 0];
    final previewRng = Random(_nextWaveSeed);

    final isBossWave = nextWave == totalWaves;
    if (isBossWave) {
      // Boss wave: 1 boss + adds
      final bossLane = previewRng.nextInt(3);
      counts[bossLane]++;
      for (var i = 0; i < config.bossAddsCount; i++) {
        counts[previewRng.nextInt(3)]++;
      }
    } else {
      final enemyCount =
          (config.spawnBaseCount + nextWave * config.spawnCountPerWave + keystone.dungeon.enemyCountModifier)
              .clamp(config.spawnMinCount, config.spawnMaxCount);
      final pattern = keystone.dungeon.lanePattern;
      for (var i = 0; i < enemyCount; i++) {
        counts[_assignLaneWith(pattern, i, enemyCount, previewRng)]++;
      }
    }

    _nextWaveLaneCounts = counts;
  }

  // -----------------------------------------------------------------------
  // Death processing (affixes + resurrection + boss split)
  // -----------------------------------------------------------------------

  void _processDeaths() {
    final newEnemies = <TdEnemy>[];

    for (final e in enemies) {
      if (e.hp != 0) continue; // only process freshly dead (hp == 0)

      // Check enemy resurrection
      if (!e.isBoss && e.modifiers.isNotEmpty) {
        final deathResult = EnemyEffectProcessor.processOnDeath(
          modifiers: e.modifiers,
          state: e.modifierState,
          position: e.position,
          laneIndex: e.laneIndex,
          maxHp: e.maxHp,
          rng: _rng,
        );
        if (deathResult is EnemyResurrectResult) {
          newEnemies.add(TdEnemy(
            id: 'e${_enemyIdCounter++}',
            maxHp: deathResult.hp,
            speed: e.speed,
            laneIndex: deathResult.laneIndex,
            modifiers: e.modifiers,
            modifierState: {'has_resurrected': true},
          )..position = deathResult.position);
          e.hp = -1;
          continue;
        }
      }

      // Check boss split on death
      if (e.isBoss) {
        final split = BossEffectProcessor.processOnDeath(
          modifiers: keystone.dungeon.bossModifiersForLevel(keystone.level),
          bossMaxHp: e.maxHp,
          bossSpeed: e.speed,
          bossLane: e.laneIndex,
          bossPosition: e.position,
        );
        if (split != null) {
          for (var i = 0; i < split.count; i++) {
            newEnemies.add(TdEnemy(
              id: 'e${_enemyIdCounter++}',
              maxHp: split.hpEach,
              speed: split.speed,
              laneIndex: split.laneIndex,
            )..position = split.position + i * 0.05);
          }
        }
      }

      // Process M+ affixes on death
      _processDeathAffixes(e);
      e.hp = -1;
      enemiesKilled++;
    }

    enemies.addAll(newEnemies);
  }

  // -----------------------------------------------------------------------
  // Death affix processing
  // -----------------------------------------------------------------------

  void _processDeathAffixes(TdEnemy enemy) {
    // Bolstering — surviving enemies in same lane get faster.
    if (keystone.hasBolstering) {
      for (final e in enemies) {
        if (!e.isDead && e.laneIndex == enemy.laneIndex && e != enemy) {
          e.speedMultiplier *= config.bolsteringSpeedBuff;
        }
      }
    }

    // Bursting — towers in the dead enemy's lane are debuffed for 2 seconds.
    if (keystone.hasBursting) {
      for (final t in towers) {
        if (t.laneIndex == enemy.laneIndex) {
          // Check Paladin passive immunity
          if (!t.isImmuneToAffix('bursting')) {
            t.isDebuffed = true;
            t.debuffTimer = config.burstingDebuffDuration;
          }
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
            (e.position - pool.position).abs() <= config.sanguineHealRange) {
          e.hp = (e.hp + e.maxHp * config.sanguineHealPerSecond * dt).clamp(0, e.maxHp);
        }
      }
    }

    sanguinePools.removeWhere((p) => p.isExpired);
  }
}
