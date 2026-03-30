import 'dart:math';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../models/character.dart';
import 'data/effect_types.dart';
import 'data/td_balance_config.dart';
import 'data/td_class_registry.dart';
import 'data/td_hero_registry.dart';
import 'data/td_run_state.dart';
import 'effects/ability_effects.dart';
import 'effects/tower_effects.dart';
import 'effects/enemy_effects.dart';
import 'effects/boss_effects.dart';
import 'models/td_combat_log.dart';
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

  // ---- ability state ----
  List<SummonedPet> summonedPets = [];
  List<LaneBlock> laneBlocks = [];
  List<BurnZone> abilityBurnZones = [];
  /// Whether abilities auto-cast (true for simulations, false for player control).
  bool autocastAbilities = true;
  /// Stun timers per lane (enemies can't move while > 0).
  final Map<int, double> _laneStunTimers = {};

  // ---- SFX event queue (consumed each frame by the UI) ----
  List<TdSfxEvent> sfxEvents = [];

  // ---- Combat log (persistent, capped at _maxCombatLogEntries) ----
  static const int _maxCombatLogEntries = 500;
  final List<TdCombatLogEntry> combatLog = [];

  // Combat log color constants
  static const _logColorCrit = Color(0xFFFF8000);
  static const _logColorDeath = Color(0xFF888888);
  static const _logColorBoss = Color(0xFFFF5E5B);
  static const _logColorWave = Color(0xFFFFD700);
  static const _logColorAffix = Color(0xFFFFA500);
  static const _logColorLeak = Color(0xFFFF5E5B);
  static const _logColorDot = Color(0xFFA335EE);
  static const _logColorSlow = Color(0xFF4FC3F7);
  static const _logColorBuff = Color(0xFF00C853);
  static const _logColorInfo = Color(0xFF8888A0);
  static const _logColorHeal = Color(0xFF66BB6A);

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
          activeAbility: classDef.activeAbility,
          ultimateAbility: classDef.ultimateAbility,
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
    summonedPets = [];
    laneBlocks = [];
    abilityBurnZones = [];
    _laneStunTimers.clear();
    _nextWaveLaneCounts = [0, 0, 0];
    _nextWaveSeed = 0;
    sfxEvents = [];

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

  /// Helper to emit an SFX event.
  void _emitSfx(TdSfxEventType type, {String? className}) {
    sfxEvents.add(TdSfxEvent(
      type: type,
      className: className,
      dungeonKey: keystone.dungeon.key,
    ));
  }

  /// Append a combat log entry (capped at [_maxCombatLogEntries]).
  void _logCombat(String message, Color color) {
    combatLog.add(TdCombatLogEntry(message: message, color: color));
    if (combatLog.length > _maxCombatLogEntries) {
      combatLog.removeAt(0);
    }
  }

  /// Format a buff for the combat log.
  String _buffLabel(TowerAbilityBuff buff) {
    switch (buff.type) {
      case 'damage_multiplier':
        return '+${((buff.value - 1) * 100).round()}% dmg';
      case 'attack_speed_multiplier':
        return '+${((1 - buff.value) * 100).abs().round()}% atk speed';
      case 'guaranteed_crit':
        return '${buff.value.toStringAsFixed(1)}x guaranteed crit';
      case 'immune_to_debuff':
        return 'debuff immunity';
      case 'immune_to_damage':
        return 'damage immunity';
      case 'cross_lane_attack':
        return 'cross-lane attacks';
      default:
        return buff.type.replaceAll('_', ' ');
    }
  }

  /// Log an ability cast with damage info when the ability dealt damage.
  void _logAbility(TdTower tower, String abilityName, AbilityResult result, Color color, {bool isUltimate = false}) {
    final name = tower.character.name;
    final verb = isUltimate ? 'unleashes' : 'casts';
    final bang = isUltimate ? '!' : '';

    if (result.hits.isEmpty) {
      _logCombat('$name $verb $abilityName$bang', color);
      return;
    }

    final totalDmg = result.hits.fold<double>(0, (sum, h) => sum + h.damage);
    final hitCount = result.hits.length;
    final hasBoss = result.hits.any((h) {
      final e = enemies.where((e) => e.id == h.enemyId).firstOrNull;
      return e?.isBoss ?? false;
    });

    final target = hasBoss
        ? 'Boss'
        : hitCount > 1
            ? '$hitCount enemies'
            : 'enemy';
    _logCombat('$name $verb $abilityName on $target for ${totalDmg.round()}$bang', color);
  }

  /// Transition from setup to the first wave.
  void beginGame() {
    phase = TdGamePhase.playing;
    currentWave = 1;
    _emitSfx(TdSfxEventType.gameStart);
    _logCombat('══ ${keystone.dungeonName.toUpperCase()} +${keystone.level} ══', _logColorWave);
    _spawnWave();
    notifyListeners();
  }

  /// Move a tower to a lane (0-2) and slot (0=front, 1=mid, 2=back).
  /// Returns false if the slot is already occupied.
  bool moveTower(int towerIndex, int newLane, {int slot = 1}) {
    if (towerIndex < 0 || towerIndex >= towers.length) return false;
    final wasPlaced = towers[towerIndex].laneIndex >= 0;
    towers[towerIndex].laneIndex = newLane.clamp(0, 2);
    towers[towerIndex].slotIndex = slot.clamp(0, 2);
    _emitSfx(wasPlaced ? TdSfxEventType.towerMove : TdSfxEventType.towerPlace);
    notifyListeners();
    return true;
  }

  /// Advance to the next wave from the between-waves phase.
  void nextWave() {
    if (phase != TdGamePhase.betweenWaves) return;
    currentWave++;
    phase = TdGamePhase.playing;
    _emitSfx(TdSfxEventType.nextWave);
    _spawnWave();
    notifyListeners();
  }

  /// Main game-loop tick. Call every frame with [dt] in seconds.
  void tick(double dt) {
    if (phase != TdGamePhase.playing) return;
    sfxEvents.clear();

    // 1. Move enemies (apply speed * speedMultiplier * slow effects * dt)
    // Also apply lane blocks and stuns
    for (final e in enemies) {
      if (!e.isDead) {
        // Check lane block
        final blocked = laneBlocks.any((b) => b.laneIndex == e.laneIndex);
        // Check lane stun
        final stunned = (_laneStunTimers[e.laneIndex] ?? 0) > 0;
        if (blocked || stunned) continue; // can't move

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
        lives = (lives - leakCost).clamp(0, maxLives);
        e.hp = 0; // remove from play
        _emitSfx(TdSfxEventType.enemyLeak);
        _logCombat('${e.isBoss ? 'Boss' : 'Enemy'} leaked! Lives: $lives', _logColorLeak);
      }
    }

    // 5. Check defeat
    if (lives <= 0) {
      phase = TdGamePhase.defeat;
      _emitSfx(TdSfxEventType.defeat);
      _logCombat('══ KEYSTONE DEPLETED ══', _logColorBoss);
      notifyListeners();
      return;
    }

    // 6. Tower attacks (delegate to TowerEffectProcessor)
    _processTowerAttacks(dt);

    // 6.5 Process abilities: cooldowns, charges, auto-cast, active effects
    _processAbilities(dt);

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
        _emitSfx(TdSfxEventType.victory);
        _logCombat('══ KEYSTONE COMPLETE! ══', _logColorWave);
      } else {
        phase = TdGamePhase.betweenWaves;
        _emitSfx(TdSfxEventType.waveComplete);
        _logCombat('── Wave $currentWave complete ──', _logColorWave);
      }
    }

    notifyListeners();
  }

  // -----------------------------------------------------------------------
  // Enemy modifier processing
  // -----------------------------------------------------------------------

  void _processEnemyModifiers(double dt) {
    // Batch attack damage per lane for logging
    final attackDmgByLane = <int, double>{};

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
            _emitSfx(TdSfxEventType.laneSwitch);
            _logCombat('Enemy switches to lane ${newLane + 1}', _logColorInfo);
          case AttackTowerResult(:final lane, :final damage):
            for (final t in towers) {
              if (t.laneIndex == lane && !t.isImmuneToDebuff) {
                t.isDebuffed = true;
                t.debuffTimer = (t.debuffTimer + damage * 0.1).clamp(0, 3);
              }
            }
            attackDmgByLane[lane] = (attackDmgByLane[lane] ?? 0) + damage;
          case SetSpeedResult(:final multiplier):
            enemy.speedMultiplier = multiplier;
            if (multiplier > 1.0) {
              _emitSfx(TdSfxEventType.enemyAccelerate);
              _logCombat('Enemy accelerates to ${(multiplier * 100).round()}% speed', _logColorInfo);
            }
          case SlowTowersResult():
            // frost_aura effect — applied as a temporary attack speed debuff,
            // handled elsewhere via flag reading
            break;
        }
      }
    }

    // Log batched enemy attacks (one line per tick instead of per-enemy)
    if (attackDmgByLane.isNotEmpty) {
      final parts = attackDmgByLane.entries
          .map((e) => 'lane ${e.key + 1}: ${e.value.round()}')
          .join(', ');
      _logCombat('Enemies attack towers ($parts)', _logColorBoss);
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

      // Advance cooldown (apply speed buff + ability speed buff)
      final cooldownMult = (speedBuff[tower.laneIndex] ?? 1.0) * tower.abilitySpeedMultiplier;
      final remaining = (_towerCooldowns[i] ?? 0) - dt;
      if (remaining > 0) {
        _towerCooldowns[i] = remaining;
        continue;
      }
      _towerCooldowns[i] = tower.attackIntervalWith(config) * cooldownMult;

      // Compute damage with buff + Sharpen upgrade + ability buffs
      final dmgMult = damageBuff[tower.laneIndex] ?? 1.0;
      final sharpenMult = runState?.getUpgrades(tower.character.id)
              ?.sharpenMultiplier(config) ?? 1.0;
      final abilityDmgMult = tower.abilityDamageMultiplier;
      var baseDamage = tower.effectiveDamage * dmgMult * sharpenMult * abilityDmgMult;

      // Apply archetype damage modifier from config
      switch (tower.archetype) {
        case TowerArchetype.ranged:
          baseDamage *= config.rangedDamageMult;
        case TowerArchetype.aoe:
          baseDamage *= config.aoeDamageMult;
        default:
          break;
      }

      // Apply transform stacking damage (Voidform)
      if (tower.transformArchetype != null && tower.transformStackingBonus > 0) {
        baseDamage *= (1.0 + tower.transformStackingBonus);
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
        towerPosition: tower.slotPosition,
        attackRange: config.attackRangeFor(tower.archetype),
        enemies: enemyRecords,
        baseDamage: baseDamage,
        attackCount: tower.attackCount,
        chargeTimer: tower.chargeTimer,
        dt: dt,
        rng: _rng,
        targetingOverride: tower.transformTargeting,
      );

      if (result.isCharging) {
        // Keep short cooldown so we re-check soon, but charge accumulates above
        _towerCooldowns[i] = 0.1;
        continue;
      }
      // Charge attack released — emit SFX if tower was charging
      if (hasChargeAttack && tower.chargeTimer > 0) {
        _emitSfx(TdSfxEventType.chargeRelease, className: tower.classDef.name);
        _logCombat('${tower.character.name} releases charged attack!', tower.color);
      }
      tower.chargeTimer = 0; // reset after firing

      // Apply hits
      final towerX = tower.slotPosition;
      double logTotalDamage = 0;
      int logHitCount = 0;
      bool logHitBoss = false;
      bool logReflected = false;
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
          logReflected = true;
        } else {
          enemy.hp = (enemy.hp - actualDamage).clamp(0, enemy.maxHp);
        }

        logTotalDamage += actualDamage;
        logHitCount++;
        if (enemy.isBoss) logHitBoss = true;

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

      // Consume empowered next attack (Vanish → Ambush)
      if (tower.empoweredNextAttackMult != null && result.hits.isNotEmpty) {
        tower.empoweredNextAttackMult = null;
        tower.empoweredNextAttackStun = null;
      }

      // Trigger ultimate charges
      if (result.hits.isNotEmpty) {
        tower.addUltimateCharge('on_attack');
        if (result.didCrit) tower.addUltimateCharge('on_crit');
        // on_nth_attack: charge on the nth hit
        final passive = tower.classDef.passive;
        if (passive.trigger == 'on_nth_attack' &&
            passive.nth > 0 &&
            tower.attackCount % passive.nth == 0) {
          tower.addUltimateCharge('on_nth_attack');
        }
      }

      // Trigger on_enemy_debuffed charges for status effects applied
      if (result.newStatusEffects.isNotEmpty) {
        tower.addUltimateCharge('on_enemy_debuffed');
      }

      // Emit attack SFX (once per tower per attack, not per hit)
      if (result.hits.isNotEmpty) {
        final className = tower.classDef.name;
        if (result.didCrit) {
          _emitSfx(TdSfxEventType.attackCrit, className: className);
        } else {
          _emitSfx(TdSfxEventType.attackHit, className: className);
        }

        // Check for special effects
        if (result.hits.length > 1 && tower.classDef.passive.effects.any((e) => e.type == 'chain_damage')) {
          _emitSfx(TdSfxEventType.chainDamage, className: className);
        }

        // Combat log: attack summary
        final name = tower.character.name;
        final dmg = logTotalDamage.round();
        final crossTag = result.hasCrossLaneHit ? ' ×lane' : '';
        if (logReflected) {
          _logCombat('$name\'s attack reflected by Boss!', _logColorBoss);
        } else if (result.didCrit) {
          final target = logHitBoss ? 'Boss' : logHitCount > 1 ? '$logHitCount enemies' : 'enemy';
          _logCombat('$name CRITS $target for $dmg!$crossTag', _logColorCrit);
        } else {
          final target = logHitBoss ? 'Boss' : logHitCount > 1 ? '$logHitCount enemies' : 'enemy';
          _logCombat('$name hits $target for $dmg$crossTag', tower.color);
        }
      }

      // Increment transform stacking damage (Voidform)
      if (tower.transformArchetype != null && tower.transformStackingDmgPerHit > 0 && logHitCount > 0) {
        tower.transformStackingBonus += tower.transformStackingDmgPerHit;
      }

      // Apply status effects (with dedup: refresh existing instead of stacking)
      for (final effect in result.newStatusEffects) {
        final enemy =
            enemies.where((e) => e.id == effect.sourceId).firstOrNull;
        if (enemy != null) {
          // Check if an effect of the same type already exists on this enemy
          final existing = enemy.statusEffects
              .where((e) => e.type == effect.type && e.remaining > 0)
              .firstOrNull;
          if (existing != null) {
            // Refresh duration instead of stacking
            existing.remaining = effect.remaining;
          } else {
            enemy.statusEffects.add(effect);
            // Only log and SFX on first application
            if (effect.type == 'dot') {
              _emitSfx(TdSfxEventType.dotApply, className: tower.classDef.name);
              _logCombat('${tower.character.name} applies DoT (${effect.dotDamage.round()}/tick, ${effect.remaining.toStringAsFixed(1)}s)', _logColorDot);
            } else if (effect.type == 'slow') {
              _emitSfx(TdSfxEventType.slowApply, className: tower.classDef.name);
              final targetLabel = enemy.isBoss ? 'Boss' : 'enemy';
              _logCombat('${tower.character.name} slows $targetLabel ${(effect.slowAmount * 100).round()}% for ${effect.remaining.toStringAsFixed(1)}s', _logColorSlow);
            }
          }
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

    final modifiers = currentWave == config.miniBossWave
        ? keystone.dungeon.miniBossModifiersForLevel(keystone.level)
        : keystone.dungeon.bossModifiersForLevel(keystone.level);
    final events = BossEffectProcessor.processTick(
      modifiers: modifiers,
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
          _emitSfx(TdSfxEventType.summonAdds);
          _logCombat('Boss summons add in lane ${laneIndex + 1} (${(boss.maxHp * hp).round()} HP)', _logColorBoss);
        case FireZoneEvent(:final laneIndex, :final duration):
          _fireZones.add(FireZone(laneIndex: laneIndex, timer: duration));
          _emitSfx(TdSfxEventType.fireZoneSpawn);
          _logCombat('Fire zone in lane ${laneIndex + 1} for ${duration.toStringAsFixed(1)}s!', _logColorBoss);
        case BossTeleportEvent(:final newLane):
          boss.laneIndex = newLane;
          _emitSfx(TdSfxEventType.bossTeleport);
          _logCombat('Boss teleports to lane ${newLane + 1}!', _logColorBoss);
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
          _emitSfx(TdSfxEventType.knockbackTower);
          final kbName = towerIndex < towers.length ? towers[towerIndex].character.name : 'tower';
          _logCombat('Boss knocks $kbName to lane ${newLane + 1}!', _logColorBoss);
        case ReflectDamageToggleEvent(:final active):
          _bossReflecting = active;
          _emitSfx(active ? TdSfxEventType.reflectDamageOn : TdSfxEventType.reflectDamageOff);
          _logCombat(active ? 'Boss reflects damage!' : 'Boss stops reflecting', _logColorBoss);
        case WindPushEvent(:final laneIndex, :final pushAmount):
          for (final e in enemies) {
            if (e.laneIndex == laneIndex && !e.isDead) {
              e.position += pushAmount;
            }
          }
          _emitSfx(TdSfxEventType.windPush);
          _logCombat('Wind pushes enemies in lane ${laneIndex + 1} (+${(pushAmount * 100).round()}%)', _logColorBoss);
        case StackingDamageTickEvent(:final damagePerTower):
          for (final t in towers) {
            if (t.laneIndex >= 0 && !t.isImmuneToDebuff) {
              t.debuffTimer += damagePerTower;
              if (t.debuffTimer > 1.0) {
                t.isDebuffed = true;
              }
            }
          }
          _emitSfx(TdSfxEventType.stackingDamageTick);
          _logCombat('Stacking damage tick (${damagePerTower.toStringAsFixed(1)}/tower)', _logColorBoss);
        case SplitOnDeathEvent():
          // Handled in death processing, not here
          break;
      }
    }

    // Check enrage state
    final wasEnraged = _bossState['_sfx_enrage_emitted'] == true;
    if (_bossState['enraged'] == true) {
      final mult = (_bossState['enrage_speed_mult'] as double?) ?? 2.0;
      boss.speedMultiplier = mult;
      if (!wasEnraged) {
        _emitSfx(TdSfxEventType.bossEnrage);
        _logCombat('★ BOSS ENRAGES!', _logColorBoss);
        _bossState['_sfx_enrage_emitted'] = true;
      }
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
  // Ability processing
  // -----------------------------------------------------------------------

  void _processAbilities(double dt) {
    // Tick down lane stun timers
    for (final key in _laneStunTimers.keys.toList()) {
      _laneStunTimers[key] = (_laneStunTimers[key]! - dt);
      if (_laneStunTimers[key]! <= 0) _laneStunTimers.remove(key);
    }

    // Tick down lane blocks
    for (final block in laneBlocks) {
      block.remaining -= dt;
    }
    laneBlocks.removeWhere((b) => b.isExpired);

    // Process ability burn zones (Meteor)
    for (final zone in abilityBurnZones) {
      zone.remaining -= dt;
      zone.tickCooldown -= dt;
      if (zone.tickCooldown <= 0) {
        zone.tickCooldown = zone.tickInterval;
        for (final e in enemies) {
          if (!e.isDead && e.laneIndex == zone.laneIndex) {
            e.hp = (e.hp - zone.damagePerTick).clamp(0, e.maxHp);
          }
        }
      }
    }
    abilityBurnZones.removeWhere((z) => z.isExpired);

    // Process summoned pets
    for (final pet in summonedPets) {
      pet.remaining -= dt;
      pet.cooldown -= dt;
      if (pet.cooldown <= 0 && !pet.isExpired) {
        pet.cooldown = pet.attackInterval;
        _petAttack(pet);
      }
    }
    summonedPets.removeWhere((p) => p.isExpired);

    // Per-tower ability processing
    for (var i = 0; i < towers.length; i++) {
      final tower = towers[i];
      if (tower.laneIndex < 0) continue;

      // Tick active ability cooldown
      if (tower.activeCooldownRemaining > 0) {
        tower.activeCooldownRemaining -= dt;
        if (tower.activeCooldownRemaining < 0) tower.activeCooldownRemaining = 0;
      }

      // Tick active ability duration
      if (tower.activeAbilityActive) {
        tower.activeAbilityTimer -= dt;
        if (tower.activeAbilityTimer <= 0) {
          tower.activeAbilityActive = false;
          tower.activeAbilityTimer = 0;
        }
      }

      // Tick ultimate duration
      if (tower.ultimateActive) {
        tower.ultimateTimer -= dt;
        if (tower.ultimateTimer <= 0) {
          tower.ultimateActive = false;
          tower.ultimateTimer = 0;
          final ultName = tower.ultimateAbility?.name;
          if (ultName != null) {
            _logCombat('${tower.character.name}\'s $ultName fades', _logColorInfo);
          }
        }
      }

      // Tick stealth
      if (tower.isStealthed) {
        tower.stealthTimer -= dt;
        if (tower.stealthTimer <= 0) {
          tower.isStealthed = false;
          tower.stealthTimer = 0;
        }
      }

      // Tick shapeshift revert
      if (tower.currentForm != null) {
        tower.shapeshiftTimer -= dt;
        if (tower.shapeshiftTimer <= 0) {
          tower.currentForm = null;
          tower.shapeshiftTimer = 0;
        }
      }

      // Tick transform revert (Voidform)
      if (tower.transformArchetype != null) {
        tower.transformTimer -= dt;
        if (tower.transformTimer <= 0) {
          tower.transformArchetype = null;
          tower.transformTargeting = null;
          tower.transformTimer = 0;
          tower.transformStackingBonus = 0;
          tower.transformStackingDmgPerHit = 0;
        }
      }

      // Tick ability buffs
      tower.abilityBuffs.removeWhere((buff) {
        buff.remaining -= dt;
        return buff.isExpired;
      });

      // on_time ultimate charge
      final ult = tower.ultimateAbility;
      if (ult != null && ult.charge != null && ult.charge!.trigger == 'on_time') {
        tower.ultimateChargeTickTimer += dt;
        if (tower.ultimateChargeTickTimer >= ult.charge!.interval) {
          tower.ultimateChargeTickTimer -= ult.charge!.interval;
          tower.addUltimateCharge('on_time');
        }
      }

      // on_buff_ally charge: support towers that have passive buffs get charge each tick
      if (tower.archetype == TowerArchetype.support && tower.laneIndex >= 0) {
        // Count buff ticks — approximation: charge once every 2 seconds
        if (ult != null && ult.charge != null && ult.charge!.trigger == 'on_buff_ally') {
          tower.ultimateChargeTickTimer += dt;
          if (tower.ultimateChargeTickTimer >= 2.0) {
            tower.ultimateChargeTickTimer -= 2.0;
            tower.addUltimateCharge('on_buff_ally');
          }
        }
      }

      // Auto-cast abilities (for simulation)
      if (autocastAbilities) {
        if (tower.canUseActive) {
          _autocastActive(i, tower);
        }
        if (tower.canUseUltimate) {
          _autocastUltimate(i, tower);
        }
      }
    }
  }

  /// Auto-cast active ability with simple heuristics.
  void _autocastActive(int towerIndex, TdTower tower) {
    final ability = tower.activeAbility!;
    final liveEnemies = enemies.where((e) => !e.isDead && e.position >= 0).toList();
    if (liveEnemies.isEmpty && ability.targeting != 'tower') return;

    switch (ability.targeting) {
      case 'instant':
        // Don't waste offensive instant abilities when no enemies alive
        if (liveEnemies.isEmpty) return;
        castActiveAbility(towerIndex);
      case 'enemy':
        // Pick best target based on ability type
        final inLane = liveEnemies.where((e) => e.laneIndex == tower.laneIndex).toList();
        final candidates = inLane.isNotEmpty ? inLane : liveEnemies;
        if (candidates.isEmpty) return;

        // For Execute-type abilities (condition: target_hp_below_pct), find qualifying target
        final hasHpCondition = ability.effects.any((e) =>
            e.params['condition'] is Map &&
            (e.params['condition'] as Map).containsKey('target_hp_below_pct'));
        // For pull/reposition abilities, target the enemy closest to leaking
        final hasPull = ability.effects.any((e) => e.type == 'pull_to_start');
        if (hasHpCondition) {
          final threshold = ability.effects
              .where((e) => e.params['condition'] is Map)
              .map((e) => ((e.params['condition'] as Map)['target_hp_below_pct'] as num?)?.toDouble() ?? 1.0)
              .reduce((a, b) => a > b ? a : b);
          final qualifying = candidates.where((e) => e.hpFraction <= threshold).toList();
          if (qualifying.isEmpty) return; // Don't waste Execute on full HP targets
          qualifying.sort((a, b) => a.hp.compareTo(b.hp));
          castActiveAbility(towerIndex, targetEnemyId: qualifying.first.id);
        } else if (hasPull) {
          // Target enemy closest to leaking (highest position) — maximize pull distance
          candidates.sort((a, b) => b.position.compareTo(a.position));
          final target = candidates.first;
          if (target.position < 0.15) return; // Don't waste grip on enemies near spawn
          castActiveAbility(towerIndex, targetEnemyId: target.id);
        } else {
          // Default: target highest HP enemy
          candidates.sort((a, b) => b.hp.compareTo(a.hp));
          castActiveAbility(towerIndex, targetEnemyId: candidates.first.id);
        }
      case 'lane':
        // Pick lane with most enemies
        final counts = [0, 0, 0];
        for (final e in liveEnemies) {
          counts[e.laneIndex]++;
        }
        var bestLane = tower.laneIndex;
        var bestCount = counts[bestLane];
        for (var l = 0; l < 3; l++) {
          if (counts[l] > bestCount) {
            bestLane = l;
            bestCount = counts[l];
          }
        }
        castActiveAbility(towerIndex, targetLane: bestLane);
      case 'tower':
        // Pick the most debuffed ally tower, or the highest damage ally tower
        // Exclude self and other support towers (buffing 0-DPS towers is useless)
        final candidates = towers.where((t) =>
            t.laneIndex >= 0 && t != tower &&
            t.classDef.archetype != TowerArchetype.support).toList();
        if (candidates.isEmpty) return;
        final debuffed = candidates.where((t) => t.isDebuffed).toList();
        if (debuffed.isNotEmpty) {
          castActiveAbility(towerIndex, targetTowerIndex: towers.indexOf(debuffed.first));
        } else {
          // Prefer highest effective damage tower
          candidates.sort((a, b) => b.effectiveDamage.compareTo(a.effectiveDamage));
          castActiveAbility(towerIndex, targetTowerIndex: towers.indexOf(candidates.first));
        }
    }
  }

  /// Auto-cast ultimate ability.
  void _autocastUltimate(int towerIndex, TdTower tower) {
    final ability = tower.ultimateAbility!;
    final liveEnemies = enemies.where((e) => !e.isDead && e.position >= 0).toList();
    if (liveEnemies.isEmpty && ability.targeting != 'tower') return;

    switch (ability.targeting) {
      case 'instant':
        if (liveEnemies.isEmpty) return;
        castUltimate(towerIndex);
      case 'enemy':
        // Target highest HP enemy
        final sorted = List<TdEnemy>.from(liveEnemies)..sort((a, b) => b.hp.compareTo(a.hp));
        if (sorted.isEmpty) return;
        castUltimate(towerIndex, targetEnemyId: sorted.first.id);
      case 'lane':
        // Target lane with most enemies
        final counts = [0, 0, 0];
        for (final e in liveEnemies) {
          counts[e.laneIndex]++;
        }
        var bestLane = 0;
        for (var l = 1; l < 3; l++) {
          if (counts[l] > counts[bestLane]) bestLane = l;
        }
        castUltimate(towerIndex, targetLane: bestLane);
      case 'tower':
        castUltimate(towerIndex, targetTowerIndex: towerIndex);
    }
  }

  /// Pet attack logic.
  void _petAttack(SummonedPet pet) {
    final liveEnemies = enemies.where((e) => !e.isDead && e.position >= 0).toList();
    if (liveEnemies.isEmpty) return;

    final damage = pet.baseDamage * pet.damageMultiplier;

    switch (pet.targeting) {
      case 'furthest_any_lane':
        final sorted = List<TdEnemy>.from(liveEnemies)
          ..sort((a, b) => a.position.compareTo(b.position));
        final target = sorted.first;
        target.hp = (target.hp - damage).clamp(0, target.maxHp);
        hitEvents.add(TdHitEvent(
          towerLane: pet.laneIndex ?? target.laneIndex,
          towerX: 0.5,
          enemyId: target.id,
          enemyLane: target.laneIndex,
          enemyX: target.position,
          damage: damage,
          archetype: TowerArchetype.ranged,
          attackColor: const Color(0xFFAAD372),
        ));
      case 'all_in_lane':
        if (pet.laneIndex == null) return;
        for (final e in liveEnemies) {
          if (e.laneIndex == pet.laneIndex) {
            e.hp = (e.hp - damage).clamp(0, e.maxHp);
          }
        }
    }
  }

  // -----------------------------------------------------------------------
  // Public ability cast API
  // -----------------------------------------------------------------------

  /// Cast a tower's active ability. Returns true if successfully cast.
  bool castActiveAbility(int towerIndex, {
    String? targetEnemyId,
    int? targetLane,
    int? targetTowerIndex,
  }) {
    if (towerIndex < 0 || towerIndex >= towers.length) return false;
    final tower = towers[towerIndex];
    if (!tower.canUseActive) return false;

    final ability = tower.activeAbility!;
    final baseDamage = tower.effectiveDamage;

    final result = AbilityEffectProcessor.execute(
      ability: ability,
      caster: tower,
      allEnemies: enemies,
      allTowers: towers,
      baseDamage: baseDamage,
      targetEnemyId: targetEnemyId,
      targetLane: targetLane,
      targetTowerIndex: targetTowerIndex,
      rng: _rng,
    );

    _logAbility(tower, ability.name, result, tower.color);
    _applyAbilityResult(result, towerIndex, tower, ability, targetTowerIndex: targetTowerIndex);

    // Start cooldown
    tower.activeCooldownRemaining = ability.cooldown;

    // Set active state for channeled/timed abilities
    if (ability.duration > 0) {
      tower.activeAbilityActive = true;
      tower.activeAbilityTimer = ability.duration;
    }

    return true;
  }

  /// Cast a tower's ultimate ability. Returns true if successfully cast.
  bool castUltimate(int towerIndex, {
    String? targetEnemyId,
    int? targetLane,
    int? targetTowerIndex,
  }) {
    if (towerIndex < 0 || towerIndex >= towers.length) return false;
    final tower = towers[towerIndex];
    if (!tower.canUseUltimate) return false;

    final ability = tower.ultimateAbility!;
    final baseDamage = tower.effectiveDamage;

    final result = AbilityEffectProcessor.execute(
      ability: ability,
      caster: tower,
      allEnemies: enemies,
      allTowers: towers,
      baseDamage: baseDamage,
      targetEnemyId: targetEnemyId,
      targetLane: targetLane,
      targetTowerIndex: targetTowerIndex,
      rng: _rng,
    );

    _logAbility(tower, ability.name, result, _logColorWave, isUltimate: true);
    _applyAbilityResult(result, towerIndex, tower, ability, targetTowerIndex: targetTowerIndex);

    // Reset charge
    tower.ultimateCharge = 0;

    // Set ultimate active state
    if (ability.duration > 0) {
      tower.ultimateActive = true;
      tower.ultimateTimer = ability.duration;
    }

    return true;
  }

  /// Apply the results of an ability execution to game state.
  void _applyAbilityResult(AbilityResult result, int towerIndex, TdTower tower, AbilityDef ability, {int? targetTowerIndex}) {
    // Apply hits
    for (final hit in result.hits) {
      final enemy = enemies.where((e) => e.id == hit.enemyId).firstOrNull;
      if (enemy != null) {
        // Check if ignore_modifiers applies
        final ignoreModifiers = ability.effects
            .where((e) => e.type == 'ignore_modifiers')
            .expand((e) => (e.params['modifiers'] as List<dynamic>? ?? []))
            .cast<String>()
            .toSet();

        double actualDamage;
        if (ignoreModifiers.isNotEmpty) {
          // Apply damage bypassing specified modifiers
          actualDamage = hit.damage;
        } else {
          actualDamage = EnemyEffectProcessor.modifyIncomingDamage(
            modifiers: enemy.modifiers,
            state: enemy.modifierState,
            rawDamage: hit.damage,
            position: enemy.position,
          );
        }
        enemy.hp = (enemy.hp - actualDamage).clamp(0, enemy.maxHp);

        hitEvents.add(TdHitEvent(
          towerLane: tower.laneIndex,
          towerX: tower.slotPosition,
          enemyId: hit.enemyId,
          enemyLane: hit.enemyLane,
          enemyX: hit.enemyPosition,
          damage: actualDamage,
          archetype: tower.archetype,
          attackColor: tower.attackColor,
          isCrit: false,
        ));
      }
    }

    // Apply instant kills
    for (final id in result.killedEnemyIds) {
      final enemy = enemies.where((e) => e.id == id).firstOrNull;
      if (enemy != null) {
        _logCombat('${tower.character.name} executes ${enemy.isBoss ? 'Boss' : 'enemy'}!', _logColorCrit);
        enemy.hp = 0;
      }
    }

    // Apply position resets (Death Grip, knockback)
    for (final entry in result.enemyPositionResets.entries) {
      final enemy = enemies.where((e) => e.id == entry.key).firstOrNull;
      if (enemy != null) {
        final fromPct = (enemy.position * 100).round();
        final toPct = (entry.value * 100).round();
        _logCombat('${tower.character.name} pulls ${enemy.isBoss ? 'Boss' : 'enemy'} back ($fromPct% → $toPct%)', tower.color);
        enemy.position = entry.value;
      }
    }

    // Apply status effects (batch log by type)
    var dotCount = 0;
    var slowCount = 0;
    double dotDmg = 0;
    double dotDur = 0;
    double slowAmt = 0;
    double slowDur = 0;
    for (final effect in result.statusEffects) {
      final enemy = enemies.where((e) => e.id == effect.sourceId).firstOrNull;
      if (enemy != null) {
        enemy.statusEffects.add(effect);
        if (effect.type == 'dot') {
          dotCount++;
          dotDmg = effect.dotDamage;
          dotDur = effect.remaining;
        } else if (effect.type == 'slow') {
          slowCount++;
          slowAmt = effect.slowAmount;
          slowDur = effect.remaining;
        }
      }
    }
    if (dotCount > 0) {
      final targets = dotCount > 1 ? ' to $dotCount enemies' : '';
      _logCombat('  ↳ applies DoT$targets (${dotDmg.round()}/tick, ${dotDur.toStringAsFixed(1)}s)', _logColorDot);
    }
    if (slowCount > 0) {
      final targets = slowCount > 1 ? ' on $slowCount enemies' : '';
      _logCombat('  ↳ slows$targets ${(slowAmt * 100).round()}% for ${slowDur.toStringAsFixed(1)}s', _logColorSlow);
    }

    // Apply tower buffs (to caster or target tower)
    if (result.towerBuffs.isNotEmpty) {
      final targetTower = ability.targeting == 'tower' && targetTowerIndex != null
          ? (targetTowerIndex >= 0 && targetTowerIndex < towers.length ? towers[targetTowerIndex] : tower)
          : tower;
      targetTower.abilityBuffs.addAll(result.towerBuffs);
      for (final buff in result.towerBuffs) {
        _logCombat('  ↳ ${targetTower.character.name} gains ${_buffLabel(buff)} for ${buff.remaining.toStringAsFixed(1)}s', _logColorBuff);
      }
    }

    // Apply all-tower buffs
    for (final buff in result.allTowerBuffs) {
      for (final t in towers) {
        if (t.laneIndex >= 0) {
          t.abilityBuffs.add(TowerAbilityBuff(
            type: buff.type,
            value: buff.value,
            remaining: buff.remaining,
          ));
        }
      }
      _logCombat('  ↳ all towers gain ${_buffLabel(buff)} for ${buff.remaining.toStringAsFixed(1)}s', _logColorBuff);
    }

    // Add summoned pets
    if (result.summonedPets.isNotEmpty) {
      for (final pet in result.summonedPets) {
        _logCombat('  ↳ summons pet (${pet.damageMultiplier}x dmg, ${pet.remaining.toStringAsFixed(1)}s)', _logColorBuff);
      }
    }
    summonedPets.addAll(result.summonedPets);

    // Add lane blocks
    if (result.laneBlocks.isNotEmpty) {
      for (final block in result.laneBlocks) {
        _logCombat('  ↳ blocks lane ${block.laneIndex + 1} for ${block.remaining.toStringAsFixed(1)}s', _logColorBuff);
      }
    }
    laneBlocks.addAll(result.laneBlocks);

    // Add burn zones
    if (result.burnZones.isNotEmpty) {
      for (final zone in result.burnZones) {
        _logCombat('  ↳ burn zone in lane ${zone.laneIndex + 1} (${zone.damagePerTick.round()}/tick, ${zone.remaining.toStringAsFixed(1)}s)', _logColorDot);
      }
    }
    abilityBurnZones.addAll(result.burnZones);

    // Apply stuns
    if (result.stunnedLanes.isNotEmpty) {
      final lanes = result.stunnedLanes.map((l) => '${l + 1}').join(', ');
      _logCombat('  ↳ stuns lane $lanes for ${result.stunDuration.toStringAsFixed(1)}s', _logColorSlow);
    }
    for (final lane in result.stunnedLanes) {
      _laneStunTimers[lane] = result.stunDuration;
    }

    // Reduce cooldowns (Bloodlust)
    if (result.reduceCooldowns) {
      for (final t in towers) {
        t.activeCooldownRemaining *= (1.0 - result.cooldownReductionPct);
      }
      _logCombat('  ↳ reduces all cooldowns by ${(result.cooldownReductionPct * 100).round()}%', _logColorBuff);
    }

    // Apply stealth
    if (result.applyStealthToTower) {
      tower.isStealthed = true;
      tower.stealthTimer = result.stealthDuration;
      _logCombat('  ↳ ${tower.character.name} enters stealth for ${result.stealthDuration.toStringAsFixed(1)}s', _logColorBuff);
    }

    // Empower next attack
    if (result.empowerNextAttackMult != null) {
      tower.empoweredNextAttackMult = result.empowerNextAttackMult;
      tower.empoweredNextAttackStun = result.empowerNextAttackStun;
      _logCombat('  ↳ next attack empowered ${result.empowerNextAttackMult!.toStringAsFixed(1)}x', _logColorBuff);
    }

    // Shapeshift
    if (result.shapeshiftForm != null) {
      tower.currentForm = result.shapeshiftForm;
      tower.shapeshiftTimer = result.shapeshiftDuration;
      _logCombat('  ↳ shifts to ${result.shapeshiftForm} form for ${result.shapeshiftDuration.toStringAsFixed(1)}s', _logColorBuff);
    }

    // Transform (Voidform)
    if (result.isTransform && result.transformDuration > 0) {
      // Map archetype string to enum
      final archMap = {
        'melee': TowerArchetype.melee,
        'ranged': TowerArchetype.ranged,
        'support': TowerArchetype.support,
        'aoe': TowerArchetype.aoe,
      };
      tower.transformArchetype = archMap[result.transformArchetype] ?? TowerArchetype.ranged;
      tower.transformTargeting = result.transformTargeting;
      tower.transformTimer = result.transformDuration;
      tower.transformStackingDmgPerHit = result.stackingDamagePerHit;
      tower.transformStackingBonus = 0;
      _logCombat('  ↳ transforms to ${result.transformArchetype} for ${result.transformDuration.toStringAsFixed(1)}s', _logColorBuff);
    }

    // Channeled abilities
    if (result.isChanneled) {
      tower.activeAbilityActive = true;
      tower.activeAbilityTimer = result.channelDuration;
      if (result.immuneDuringChannel) {
        tower.abilityBuffs.add(TowerAbilityBuff(
          type: 'immune_to_debuff',
          value: 1.0,
          remaining: result.channelDuration,
        ));
      }
      // Apply channel damage immediately (simplified: all hits at once)
      // Use baseDamage, not effectiveDamage — channeled abilities are not
      // reduced by tower debuffs (Bursting slows attack speed, not ability damage)
      final channelDamage = tower.baseDamage * result.channelDamagePerHit;
      final liveEnemies = enemies.where((e) => !e.isDead && e.laneIndex == tower.laneIndex).toList();
      if (liveEnemies.isNotEmpty) {
        // Target the closest enemy (melee channel)
        liveEnemies.sort((a, b) => b.position.compareTo(a.position));
        final target = liveEnemies.first;
        for (var h = 0; h < result.channelHits; h++) {
          target.hp = (target.hp - channelDamage).clamp(0, target.maxHp);
        }
        hitEvents.add(TdHitEvent(
          towerLane: tower.laneIndex,
          towerX: tower.slotPosition,
          enemyId: target.id,
          enemyLane: target.laneIndex,
          enemyX: target.position,
          damage: channelDamage * result.channelHits,
          archetype: tower.archetype,
          attackColor: tower.attackColor,
        ));
      }
      // Always log channel info (even if no enemies in lane to hit)
      final totalChannelDmg = (channelDamage * result.channelHits).round();
      _logCombat('  ↳ channels ${result.channelHits} hits for $totalChannelDmg total', tower.color);
      if (result.immuneDuringChannel) {
        _logCombat('  ↳ immune during channel (${result.channelDuration.toStringAsFixed(1)}s)', _logColorBuff);
      }
    }

    // Random cast (Convoke) — simplified: apply all random effects immediately
    if (result.isRandomCast) {
      _logCombat('  ↳ casts ${result.randomCastCount} random spells!', _logColorBuff);
      _processConvoke(tower, result.randomCastCount);
    }

    // Combo points (Shadow Blades) — set up tracking
    if (result.enableComboPoints) {
      tower.comboPoints = 0;
      _logCombat('  ↳ combo system active (finisher at ${result.comboThreshold} pts, ${result.comboFinisherMult.toStringAsFixed(1)}x)', _logColorBuff);
    }

    // Trigger on_buff_ally charge for support abilities
    if (ability.targeting == 'tower' || result.allTowerBuffs.isNotEmpty) {
      tower.addUltimateCharge('on_buff_ally');
    }
  }

  /// Simplified Convoke: cast N random effects across all lanes.
  void _processConvoke(TdTower caster, int count) {
    final liveEnemies = enemies.where((e) => !e.isDead && e.position >= 0).toList();
    final damage = caster.effectiveDamage;
    var totalDmg = 0.0;
    var dmgCasts = 0;
    var dotCasts = 0;
    var cleanseCasts = 0;
    var buffCasts = 0;

    for (var i = 0; i < count; i++) {
      final roll = _rng.nextInt(16);
      if (roll < 4 && liveEnemies.isNotEmpty) {
        // Damage random enemy
        final target = liveEnemies[_rng.nextInt(liveEnemies.length)];
        final dmg = damage * 2.0;
        target.hp = (target.hp - dmg).clamp(0, target.maxHp);
        totalDmg += dmg;
        dmgCasts++;
      } else if (roll < 7 && liveEnemies.isNotEmpty) {
        // DoT random enemy
        final target = liveEnemies[_rng.nextInt(liveEnemies.length)];
        target.statusEffects.add(EnemyStatusEffect(
          type: 'dot',
          sourceId: target.id,
          params: {'dotDamage': damage * 0.3, 'tickInterval': 1.0},
          remaining: 3.0,
        ));
        dotCasts++;
      } else if (roll < 10) {
        // Cleanse random tower
        final debuffed = towers.where((t) => t.isDebuffed).toList();
        if (debuffed.isNotEmpty) {
          final target = debuffed[_rng.nextInt(debuffed.length)];
          target.isDebuffed = false;
          target.debuffTimer = 0;
          cleanseCasts++;
        }
      } else if (roll < 13) {
        // Buff random tower damage
        final placed = towers.where((t) => t.laneIndex >= 0).toList();
        if (placed.isNotEmpty) {
          final target = placed[_rng.nextInt(placed.length)];
          target.abilityBuffs.add(TowerAbilityBuff(
            type: 'damage_multiplier', value: 1.2, remaining: 4.0,
          ));
          buffCasts++;
        }
      } else {
        // Buff random tower speed
        final placed = towers.where((t) => t.laneIndex >= 0).toList();
        if (placed.isNotEmpty) {
          final target = placed[_rng.nextInt(placed.length)];
          target.abilityBuffs.add(TowerAbilityBuff(
            type: 'attack_speed_multiplier', value: 0.8, remaining: 4.0,
          ));
          buffCasts++;
        }
      }
    }

    // Log Convoke summary
    final parts = <String>[];
    if (dmgCasts > 0) parts.add('${dmgCasts}x dmg (${totalDmg.round()})');
    if (dotCasts > 0) parts.add('${dotCasts}x DoT');
    if (cleanseCasts > 0) parts.add('${cleanseCasts}x cleanse');
    if (buffCasts > 0) parts.add('${buffCasts}x buff');
    _logCombat('  ↳ ${parts.join(', ')}', _logColorBuff);
  }

  // -----------------------------------------------------------------------
  // Wave spawning
  // -----------------------------------------------------------------------

  /// Whether [wave] is in act 2 (after mini-boss).
  bool _isAct2(int wave) => wave > config.miniBossWave;

  void _spawnWave() {
    final dungeon = keystone.dungeon;
    var waveScale = 1.0 + (currentWave - 1) * config.waveHpScalePerWave;

    // Act 2 HP bonus: enemies are individually tougher
    if (_isAct2(currentWave)) {
      waveScale *= (1.0 + config.act2HpBonus);
    }

    final baseHp =
        config.baseEnemyHp * keystone.hpMultiplierWith(config) * dungeon.hpMultiplier * waveScale;
    final baseSpeed = config.baseEnemySpeed * dungeon.speedMultiplier;

    // Initialize ability cooldowns and trigger on_wave_start charge
    for (final tower in towers) {
      if (tower.laneIndex >= 0) {
        tower.initAbilityCooldowns();
        tower.addUltimateCharge('on_wave_start');
      }
    }

    _emitSfx(TdSfxEventType.waveStart);
    _logCombat('── Wave $currentWave/$totalWaves started ──', _logColorWave);

    if (currentWave == totalWaves) {
      // Final boss (wave 10)
      _spawnBossWave(baseHp, baseSpeed, dungeon);
      _emitSfx(TdSfxEventType.bossSpawn);
      _logCombat('★ BOSS SPAWNS!', _logColorBoss);
    } else if (currentWave == config.miniBossWave) {
      // Mini-boss (wave 5)
      _spawnMiniBossWave(baseHp, baseSpeed, dungeon);
      _emitSfx(TdSfxEventType.bossSpawn);
      final name = dungeon.miniBossName ?? 'MINI-BOSS';
      _logCombat('★ $name SPAWNS!', _logColorBoss);
    } else {
      _spawnRegularWave(baseHp, baseSpeed, dungeon);
    }

    // Pre-compute next wave lane preview
    _computeNextWaveLanePreview();
  }

  void _spawnRegularWave(
      double baseHp, double baseSpeed, TdDungeonDef dungeon) {
    // Act 2 count reset: wave 6 uses effective wave 1, wave 7 uses 2, etc.
    final effectiveWave = _isAct2(currentWave)
        ? currentWave - config.miniBossWave
        : currentWave;
    final count =
        (config.spawnBaseCount + effectiveWave * config.spawnCountPerWave + dungeon.enemyCountModifier)
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

  void _spawnMiniBossWave(double baseHp, double baseSpeed, TdDungeonDef dungeon) {
    final miniBossHp = baseHp * config.miniBossHpMultiplier;
    final miniBossSpeed = config.miniBossSpeed * dungeon.speedMultiplier;

    final laneRng = Random(_nextWaveSeed);
    final bossLane = laneRng.nextInt(3);

    // Initialize boss state from dungeon mini-boss modifiers
    _bossState = BossEffectProcessor.initBossState(dungeon.miniBossModifiersForLevel(keystone.level));

    enemies.add(TdEnemy(
      id: 'e${_enemyIdCounter++}',
      maxHp: miniBossHp,
      speed: miniBossSpeed,
      laneIndex: bossLane,
      isBoss: true,
    ));

    // Mini-boss adds (fewer than final boss)
    for (var i = 0; i < config.miniBossAddsCount; i++) {
      final modifiers =
          EnemyEffectProcessor.rollSpawnModifiers(
              dungeon.enemyModifiersForLevel(keystone.level), _rng);
      final modifierState = EnemyEffectProcessor.initModifierState(modifiers);

      enemies.add(TdEnemy(
        id: 'e${_enemyIdCounter++}',
        maxHp: baseHp * config.miniBossAddsHpFraction,
        speed: baseSpeed + _rng.nextDouble() * config.miniBossAddsSpeedVariance,
        laneIndex: laneRng.nextInt(3),
        modifiers: modifiers,
        modifierState: modifierState,
      )..position = -(i + 1) * config.miniBossAddsStaggerDistance);
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
    final isMiniBossWave = nextWave == config.miniBossWave;
    if (isBossWave) {
      // Boss wave: 1 boss + adds
      final bossLane = previewRng.nextInt(3);
      counts[bossLane]++;
      for (var i = 0; i < config.bossAddsCount; i++) {
        counts[previewRng.nextInt(3)]++;
      }
    } else if (isMiniBossWave) {
      // Mini-boss wave: 1 mini-boss + fewer adds
      final bossLane = previewRng.nextInt(3);
      counts[bossLane]++;
      for (var i = 0; i < config.miniBossAddsCount; i++) {
        counts[previewRng.nextInt(3)]++;
      }
    } else {
      // Act 2 count reset
      final effectiveWave = nextWave > config.miniBossWave
          ? nextWave - config.miniBossWave
          : nextWave;
      final enemyCount =
          (config.spawnBaseCount + effectiveWave * config.spawnCountPerWave + keystone.dungeon.enemyCountModifier)
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
          _emitSfx(TdSfxEventType.resurrect);
          _logCombat('Enemy resurrects with ${deathResult.hp.round()} HP!', _logColorBoss);
          e.hp = -1;
          continue;
        }
      }

      // Check boss split on death
      if (e.isBoss) {
        final deathModifiers = currentWave == config.miniBossWave
            ? keystone.dungeon.miniBossModifiersForLevel(keystone.level)
            : keystone.dungeon.bossModifiersForLevel(keystone.level);
        final split = BossEffectProcessor.processOnDeath(
          modifiers: deathModifiers,
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
          _emitSfx(TdSfxEventType.splitOnDeath);
          _logCombat('Boss splits into ${split.count} fragments!', _logColorBoss);
        }
        _emitSfx(TdSfxEventType.bossDeath);
        final bossLabel = currentWave == config.miniBossWave
            ? (keystone.dungeon.miniBossName ?? 'MINI-BOSS')
            : 'BOSS';
        _logCombat('★ $bossLabel DEFEATED!', _logColorWave);
      } else {
        _emitSfx(TdSfxEventType.enemyDeath);
        _logCombat('Enemy slain', _logColorDeath);
      }

      // Trigger on_kill ultimate charge for towers in the same lane
      for (final t in towers) {
        if (t.laneIndex == e.laneIndex && t.laneIndex >= 0) {
          t.addUltimateCharge('on_kill');
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
      _emitSfx(TdSfxEventType.bolsteringTrigger);
      _logCombat('Bolstering: enemies +${((config.bolsteringSpeedBuff - 1) * 100).round()}% speed in lane ${enemy.laneIndex + 1}', _logColorAffix);
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
      _emitSfx(TdSfxEventType.burstingTrigger);
      _logCombat('Bursting: towers debuffed ${config.burstingDebuffDuration.toStringAsFixed(1)}s in lane ${enemy.laneIndex + 1}', _logColorAffix);
    }

    // Sanguine — drop a healing pool at the enemy's position.
    if (keystone.hasSanguine) {
      sanguinePools.add(SanguinePool(
        laneIndex: enemy.laneIndex,
        position: enemy.position,
      ));
      _emitSfx(TdSfxEventType.sanguineTrigger);
      _logCombat('Sanguine pool spawned in lane ${enemy.laneIndex + 1}', _logColorAffix);
    }
  }

  // -----------------------------------------------------------------------
  // Sanguine pool update
  // -----------------------------------------------------------------------

  double _sanguineHealSfxCooldown = 0;

  void _updateSanguinePools(double dt) {
    _sanguineHealSfxCooldown -= dt;
    bool healed = false;

    for (final pool in sanguinePools) {
      pool.timer -= dt;

      // Heal nearby enemies.
      for (final e in enemies) {
        if (!e.isDead &&
            e.laneIndex == pool.laneIndex &&
            (e.position - pool.position).abs() <= config.sanguineHealRange) {
          e.hp = (e.hp + e.maxHp * config.sanguineHealPerSecond * dt).clamp(0, e.maxHp);
          healed = true;
        }
      }
    }

    if (healed && _sanguineHealSfxCooldown <= 0) {
      _emitSfx(TdSfxEventType.sanguineHeal);
      _logCombat('Sanguine heals enemies (${(config.sanguineHealPerSecond * 100).round()}% HP/s)', _logColorHeal);
      _sanguineHealSfxCooldown = 1.0; // play at most once per second
    }

    sanguinePools.removeWhere((p) => p.isExpired);
  }
}
