import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Global balance constants loaded from assets/td/balance.json.
/// All tuning knobs for the TD game in one place — edit the JSON
/// to patch balance without changing code.
class TdBalanceConfig {
  // General
  final int startingLives;
  final int totalWaves;
  final double baseEnemyHp;
  final double baseEnemySpeed;
  final double waveHpScalePerWave;

  // Boss
  final double bossHpMultiplier;
  final double bossSpeed;
  final int bossAddsCount;
  final double bossAddsHpFraction;
  final double bossAddsSpeedVariance;
  final double bossAddsStaggerDistance;

  // Enemy spawn
  final int spawnBaseCount;
  final int spawnCountPerWave;
  final int spawnMinCount;
  final int spawnMaxCount;
  final double spawnSpeedVariance;
  final double spawnStaggerDistance;

  // Archetype damage multipliers
  final double meleeDamageMult;
  final double rangedDamageMult;
  final double aoeDamageMult;

  // Archetype attack intervals
  final double meleeAttackInterval;
  final double rangedAttackInterval;
  final double supportAttackInterval;
  final double aoeAttackInterval;

  // Keystone scaling
  final int linearPhaseEnd;
  final double linearRate;
  final double exponentialBase;
  final double exponentialLinear;
  final double exponentialQuadratic;

  // Affix thresholds
  final int oneAffixLevel;
  final int twoAffixLevel;
  final int threeAffixLevel;

  // Affix values
  final double fortifiedHpMult;
  final double tyrannicalHpMult;
  final double bolsteringSpeedBuff;
  final double burstingDebuffDuration;
  final double sanguinePoolDuration;
  final double sanguineHealPerSecond;
  final double sanguineHealRange;

  // Tower
  final double debuffDamageReduction;

  // Valor
  final int cleanClearThreshold;
  final int standardClearMin;
  final int cleanClearReward;
  final int standardClearReward;
  final int scrapedByReward;
  final int depleteReward;
  final int sharpenCost;
  final int sharpenMaxStacks;
  final double sharpenDamageBonus;
  final int fortifyCost;
  final int fortifyBossLeakReduction;
  final int empowerCost;
  final int sixthTowerLevel;

  const TdBalanceConfig({
    this.startingLives = 20,
    this.totalWaves = 5,
    this.baseEnemyHp = 260,
    this.baseEnemySpeed = 0.10,
    this.waveHpScalePerWave = 0.12,
    this.bossHpMultiplier = 6.0,
    this.bossSpeed = 0.04,
    this.bossAddsCount = 3,
    this.bossAddsHpFraction = 0.4,
    this.bossAddsSpeedVariance = 0.05,
    this.bossAddsStaggerDistance = 0.12,
    this.spawnBaseCount = 6,
    this.spawnCountPerWave = 2,
    this.spawnMinCount = 4,
    this.spawnMaxCount = 20,
    this.spawnSpeedVariance = 0.06,
    this.spawnStaggerDistance = 0.10,
    this.meleeDamageMult = 1.0,
    this.rangedDamageMult = 1.0,
    this.aoeDamageMult = 0.5,
    this.meleeAttackInterval = 0.8,
    this.rangedAttackInterval = 1.0,
    this.supportAttackInterval = 2.0,
    this.aoeAttackInterval = 1.3,
    this.linearPhaseEnd = 20,
    this.linearRate = 0.10,
    this.exponentialBase = 2.8,
    this.exponentialLinear = 0.25,
    this.exponentialQuadratic = 0.02,
    this.oneAffixLevel = 4,
    this.twoAffixLevel = 7,
    this.threeAffixLevel = 11,
    this.fortifiedHpMult = 1.3,
    this.tyrannicalHpMult = 1.5,
    this.bolsteringSpeedBuff = 1.1,
    this.burstingDebuffDuration = 2.0,
    this.sanguinePoolDuration = 4.0,
    this.sanguineHealPerSecond = 0.15,
    this.sanguineHealRange = 0.05,
    this.debuffDamageReduction = 0.5,
    this.cleanClearThreshold = 16,
    this.standardClearMin = 8,
    this.cleanClearReward = 3,
    this.standardClearReward = 2,
    this.scrapedByReward = 1,
    this.depleteReward = 0,
    this.sharpenCost = 1,
    this.sharpenMaxStacks = 3,
    this.sharpenDamageBonus = 0.15,
    this.fortifyCost = 1,
    this.fortifyBossLeakReduction = 1,
    this.empowerCost = 2,
    this.sixthTowerLevel = 5,
  });

  /// The default config (matches constructor defaults).
  static const TdBalanceConfig defaults = TdBalanceConfig();

  /// Load from assets/td/balance.json.
  static Future<TdBalanceConfig> load() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/td/balance.json');
      return fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (e) {
      return defaults;
    }
  }

  /// Parse from JSON map (also used by simulation tests).
  static TdBalanceConfig fromJson(Map<String, dynamic> json) {
    final general = json['general'] as Map<String, dynamic>? ?? {};
    final boss = json['boss'] as Map<String, dynamic>? ?? {};
    final spawn = json['enemySpawn'] as Map<String, dynamic>? ?? {};
    final archetypes = json['archetypes'] as Map<String, dynamic>? ?? {};
    final melee = archetypes['melee'] as Map<String, dynamic>? ?? {};
    final ranged = archetypes['ranged'] as Map<String, dynamic>? ?? {};
    final support = archetypes['support'] as Map<String, dynamic>? ?? {};
    final aoe = archetypes['aoe'] as Map<String, dynamic>? ?? {};
    final scaling = json['keystoneScaling'] as Map<String, dynamic>? ?? {};
    final affixes = json['affixes'] as Map<String, dynamic>? ?? {};
    final thresholds = affixes['thresholds'] as Map<String, dynamic>? ?? {};
    final fort = affixes['fortified'] as Map<String, dynamic>? ?? {};
    final tyran = affixes['tyrannical'] as Map<String, dynamic>? ?? {};
    final bolst = affixes['bolstering'] as Map<String, dynamic>? ?? {};
    final burst = affixes['bursting'] as Map<String, dynamic>? ?? {};
    final sang = affixes['sanguine'] as Map<String, dynamic>? ?? {};
    final tower = json['tower'] as Map<String, dynamic>? ?? {};
    final valor = json['valor'] as Map<String, dynamic>? ?? {};

    return TdBalanceConfig(
      startingLives: (general['startingLives'] as num?)?.toInt() ?? 25,
      totalWaves: (general['totalWaves'] as num?)?.toInt() ?? 5,
      baseEnemyHp: (general['baseEnemyHp'] as num?)?.toDouble() ?? 200,
      baseEnemySpeed: (general['baseEnemySpeed'] as num?)?.toDouble() ?? 0.10,
      waveHpScalePerWave: (general['waveHpScalePerWave'] as num?)?.toDouble() ?? 0.2,
      bossHpMultiplier: (boss['hpMultiplier'] as num?)?.toDouble() ?? 6.0,
      bossSpeed: (boss['speed'] as num?)?.toDouble() ?? 0.04,
      bossAddsCount: (boss['addsCount'] as num?)?.toInt() ?? 3,
      bossAddsHpFraction: (boss['addsHpFraction'] as num?)?.toDouble() ?? 0.4,
      bossAddsSpeedVariance: (boss['addsSpeedVariance'] as num?)?.toDouble() ?? 0.05,
      bossAddsStaggerDistance: (boss['addsStaggerDistance'] as num?)?.toDouble() ?? 0.12,
      spawnBaseCount: (spawn['baseCount'] as num?)?.toInt() ?? 6,
      spawnCountPerWave: (spawn['countPerWave'] as num?)?.toInt() ?? 2,
      spawnMinCount: (spawn['minCount'] as num?)?.toInt() ?? 4,
      spawnMaxCount: (spawn['maxCount'] as num?)?.toInt() ?? 20,
      spawnSpeedVariance: (spawn['speedVariance'] as num?)?.toDouble() ?? 0.06,
      spawnStaggerDistance: (spawn['staggerDistance'] as num?)?.toDouble() ?? 0.10,
      meleeDamageMult: (melee['damageMult'] as num?)?.toDouble() ?? 1.0,
      rangedDamageMult: (ranged['damageMult'] as num?)?.toDouble() ?? 1.0,
      aoeDamageMult: (aoe['damageMult'] as num?)?.toDouble() ?? 0.5,
      meleeAttackInterval: (melee['attackInterval'] as num?)?.toDouble() ?? 0.8,
      rangedAttackInterval: (ranged['attackInterval'] as num?)?.toDouble() ?? 1.0,
      supportAttackInterval: (support['attackInterval'] as num?)?.toDouble() ?? 2.0,
      aoeAttackInterval: (aoe['attackInterval'] as num?)?.toDouble() ?? 1.3,
      linearPhaseEnd: (scaling['linearPhaseEnd'] as num?)?.toInt() ?? 10,
      linearRate: (scaling['linearRate'] as num?)?.toDouble() ?? 0.12,
      exponentialBase: (scaling['exponentialBase'] as num?)?.toDouble() ?? 1.96,
      exponentialLinear: (scaling['exponentialLinear'] as num?)?.toDouble() ?? 0.25,
      exponentialQuadratic: (scaling['exponentialQuadratic'] as num?)?.toDouble() ?? 0.05,
      oneAffixLevel: (thresholds['oneAffix'] as num?)?.toInt() ?? 4,
      twoAffixLevel: (thresholds['twoAffixes'] as num?)?.toInt() ?? 7,
      threeAffixLevel: (thresholds['threeAffixes'] as num?)?.toInt() ?? 11,
      fortifiedHpMult: (fort['hpMultiplier'] as num?)?.toDouble() ?? 1.3,
      tyrannicalHpMult: (tyran['hpMultiplier'] as num?)?.toDouble() ?? 1.5,
      bolsteringSpeedBuff: (bolst['speedBuff'] as num?)?.toDouble() ?? 1.1,
      burstingDebuffDuration: (burst['debuffDuration'] as num?)?.toDouble() ?? 2.0,
      sanguinePoolDuration: (sang['poolDuration'] as num?)?.toDouble() ?? 4.0,
      sanguineHealPerSecond: (sang['healPerSecond'] as num?)?.toDouble() ?? 0.15,
      sanguineHealRange: (sang['healRange'] as num?)?.toDouble() ?? 0.05,
      debuffDamageReduction: (tower['debuffDamageReduction'] as num?)?.toDouble() ?? 0.5,
      cleanClearThreshold: (valor['cleanClearThreshold'] as num?)?.toInt() ?? 20,
      standardClearMin: (valor['standardClearMin'] as num?)?.toInt() ?? 10,
      cleanClearReward: (valor['cleanClearReward'] as num?)?.toInt() ?? 3,
      standardClearReward: (valor['standardClearReward'] as num?)?.toInt() ?? 2,
      scrapedByReward: (valor['scrapedByReward'] as num?)?.toInt() ?? 1,
      depleteReward: (valor['depleteReward'] as num?)?.toInt() ?? 0,
      sharpenCost: (valor['sharpenCost'] as num?)?.toInt() ?? 1,
      sharpenMaxStacks: (valor['sharpenMaxStacks'] as num?)?.toInt() ?? 3,
      sharpenDamageBonus: (valor['sharpenDamageBonus'] as num?)?.toDouble() ?? 0.15,
      fortifyCost: (valor['fortifyCost'] as num?)?.toInt() ?? 1,
      fortifyBossLeakReduction: (valor['fortifyBossLeakReduction'] as num?)?.toInt() ?? 1,
      empowerCost: (valor['empowerCost'] as num?)?.toInt() ?? 2,
      sixthTowerLevel: (valor['sixthTowerLevel'] as num?)?.toInt() ?? 5,
    );
  }
}
