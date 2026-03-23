import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Tower Archetype
// ---------------------------------------------------------------------------

/// Broad category describing a tower class's role.
enum TowerArchetype {
  melee,
  ranged,
  support,
  aoe;

  /// Parse a string to [TowerArchetype], case-insensitive. Defaults to [melee].
  static TowerArchetype fromString(String value) {
    switch (value.toLowerCase().trim()) {
      case 'melee':
        return TowerArchetype.melee;
      case 'ranged':
        return TowerArchetype.ranged;
      case 'support':
        return TowerArchetype.support;
      case 'aoe':
        return TowerArchetype.aoe;
      default:
        return TowerArchetype.melee;
    }
  }
}

// ---------------------------------------------------------------------------
// EffectDef — a single composable effect
// ---------------------------------------------------------------------------

/// A single composable effect parsed from JSON.
///
/// The [type] field identifies the effect (e.g. "extra_targets", "slow_enemy").
/// All remaining JSON fields are stored in [params] so that new parameters
/// added to the data files are automatically available without code changes.
class EffectDef {
  final String type;
  final Map<String, dynamic> params;

  const EffectDef({
    required this.type,
    this.params = const {},
  });

  // -- Convenience getters for common params --------------------------------

  double get value => (params['value'] as num?)?.toDouble() ?? 0;
  double get duration => (params['duration'] as num?)?.toDouble() ?? 0;
  double get chance => (params['chance'] as num?)?.toDouble() ?? 0;
  double get radius => (params['radius'] as num?)?.toDouble() ?? 0;
  double get multiplier => (params['multiplier'] as num?)?.toDouble() ?? 1;
  int get stacks => (params['stacks'] as num?)?.toInt() ?? 0;
  String get target => params['target'] as String? ?? '';

  // -- JSON -----------------------------------------------------------------

  factory EffectDef.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'unknown';
    final params = Map<String, dynamic>.from(json)..remove('type');
    return EffectDef(type: type, params: params);
  }

  @override
  String toString() => 'EffectDef($type, $params)';
}

// ---------------------------------------------------------------------------
// PassiveDef — a class passive ability
// ---------------------------------------------------------------------------

/// Describes a tower class's passive ability and the effects it applies.
class PassiveDef {
  final String name;
  final String description;

  /// When the passive triggers: "on_attack", "on_nth_attack", "on_kill",
  /// "passive", etc.
  final String trigger;

  /// For "on_nth_attack" triggers, the N value (e.g. every 3rd attack).
  final int nth;

  final List<EffectDef> effects;

  const PassiveDef({
    required this.name,
    this.description = '',
    this.trigger = 'passive',
    this.nth = 0,
    this.effects = const [],
  });

  factory PassiveDef.fromJson(Map<String, dynamic> json) {
    return PassiveDef(
      name: json['name'] as String? ?? 'Unknown',
      description: json['description'] as String? ?? '',
      trigger: json['trigger'] as String? ?? 'passive',
      nth: (json['nth'] as num?)?.toInt() ?? 0,
      effects: (json['effects'] as List<dynamic>?)
              ?.map((e) => EffectDef.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
    );
  }

  @override
  String toString() => 'PassiveDef($name, trigger=$trigger)';
}

// ---------------------------------------------------------------------------
// TdClassDef — a class definition from classes.json
// ---------------------------------------------------------------------------

/// Full definition of a tower class, parsed from classes.json.
class TdClassDef {
  final String name;
  final TowerArchetype archetype;
  final PassiveDef passive;
  final PassiveDef? empoweredPassive;
  final Color attackColor;

  const TdClassDef({
    required this.name,
    required this.archetype,
    required this.passive,
    this.empoweredPassive,
    this.attackColor = const Color(0xFFFFFFFF),
  });

  factory TdClassDef.fromJson(String name, Map<String, dynamic> json) {
    return TdClassDef(
      name: name,
      archetype: TowerArchetype.fromString(json['archetype'] as String? ?? 'melee'),
      passive: json['passive'] != null
          ? PassiveDef.fromJson(Map<String, dynamic>.from(json['passive'] as Map))
          : const PassiveDef(name: 'None'),
      empoweredPassive: json['empoweredPassive'] != null
          ? PassiveDef.fromJson(Map<String, dynamic>.from(json['empoweredPassive'] as Map))
          : null,
      attackColor: _parseColor((json['attackColor'] ?? json['attack_color']) as String?),
    );
  }

  @override
  String toString() => 'TdClassDef($name, $archetype)';
}

// ---------------------------------------------------------------------------
// LanePatternDef — how enemies distribute across lanes
// ---------------------------------------------------------------------------

/// Describes the lane distribution pattern for a dungeon's enemies.
class LanePatternDef {
  /// Pattern type: "spread", "drift", "heavy_center", "sequential", "zerg",
  /// "packs", "weakest_lane", "lane_switch", etc.
  final String type;
  final Map<String, dynamic> params;

  const LanePatternDef({
    required this.type,
    this.params = const {},
  });

  factory LanePatternDef.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'spread';
    final params = Map<String, dynamic>.from(json)..remove('type');
    return LanePatternDef(type: type, params: params);
  }

  @override
  String toString() => 'LanePatternDef($type)';
}

// ---------------------------------------------------------------------------
// ParticleDef — particle effect config from dungeons.json
// ---------------------------------------------------------------------------

/// Particle effect config from dungeons.json.
class ParticleDef {
  final String type; // wisps, snow, embers, void, wind, leaves, sparks
  final Color color;
  final int count;
  final double speed;
  final double size;
  final double opacity;

  const ParticleDef({
    this.type = 'wisps',
    this.color = const Color(0xFFFFFFFF),
    this.count = 10,
    this.speed = 0.3,
    this.size = 3.0,
    this.opacity = 0.2,
  });

  factory ParticleDef.fromJson(Map<String, dynamic> json) {
    return ParticleDef(
      type: json['type'] as String? ?? 'wisps',
      color: _parseColor(json['color'] as String?),
      count: (json['count'] as num?)?.toInt() ?? 10,
      speed: (json['speed'] as num?)?.toDouble() ?? 0.3,
      size: (json['size'] as num?)?.toDouble() ?? 3.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 0.2,
    );
  }
}

// ---------------------------------------------------------------------------
// TdDungeonDef — a dungeon definition from dungeons.json
// ---------------------------------------------------------------------------

/// Full definition of a dungeon, parsed from dungeons.json.
class TdDungeonDef {
  final String key;
  final String name;
  final String shortName;
  final String theme;
  final Color enemyColor;
  final Color bossColor;
  final String enemyIcon;
  final String bossIcon;
  final String? enemyImage;
  final String? bossImage;
  final String? backgroundImage;
  final double hpMultiplier;
  final double speedMultiplier;
  final int enemyCountModifier;
  final LanePatternDef lanePattern;
  final List<EffectDef> enemyModifiers;
  final List<EffectDef> bossModifiers;
  final ParticleDef? particles;

  /// Level-based modifier overrides. Keys are keystone levels (as strings).
  /// At spawn, the game picks the highest tier <= current keystoneLevel.
  final Map<int, ({List<EffectDef>? enemyMods, List<EffectDef>? bossMods})> modifierScaling;

  const TdDungeonDef({
    required this.key,
    required this.name,
    this.shortName = '',
    this.theme = '',
    this.enemyColor = const Color(0xFFFF0000),
    this.bossColor = const Color(0xFFFF4444),
    this.enemyIcon = 'skull',
    this.bossIcon = 'skull',
    this.enemyImage,
    this.bossImage,
    this.backgroundImage,
    this.hpMultiplier = 1.0,
    this.speedMultiplier = 1.0,
    this.enemyCountModifier = 0,
    this.lanePattern = const LanePatternDef(type: 'spread'),
    this.enemyModifiers = const [],
    this.bossModifiers = const [],
    this.particles,
    this.modifierScaling = const {},
  });

  /// Get enemy modifiers scaled for the given keystone level.
  List<EffectDef> enemyModifiersForLevel(int keystoneLevel) {
    if (modifierScaling.isEmpty) return enemyModifiers;
    int bestLevel = 0;
    List<EffectDef>? best;
    for (final entry in modifierScaling.entries) {
      if (entry.key <= keystoneLevel && entry.key > bestLevel && entry.value.enemyMods != null) {
        bestLevel = entry.key;
        best = entry.value.enemyMods;
      }
    }
    return best ?? enemyModifiers;
  }

  /// Get boss modifiers scaled for the given keystone level.
  List<EffectDef> bossModifiersForLevel(int keystoneLevel) {
    if (modifierScaling.isEmpty) return bossModifiers;
    int bestLevel = 0;
    List<EffectDef>? best;
    for (final entry in modifierScaling.entries) {
      if (entry.key <= keystoneLevel && entry.key > bestLevel && entry.value.bossMods != null) {
        bestLevel = entry.key;
        best = entry.value.bossMods;
      }
    }
    return best ?? bossModifiers;
  }

  factory TdDungeonDef.fromJson(String key, Map<String, dynamic> json) {
    return TdDungeonDef(
      key: key,
      name: json['name'] as String? ?? key,
      shortName: (json['shortName'] ?? json['short_name']) as String? ?? '',
      theme: json['theme'] as String? ?? '',
      enemyColor: _parseColor((json['enemyColor'] ?? json['enemy_color']) as String?),
      bossColor: _parseColor((json['bossColor'] ?? json['boss_color']) as String?),
      enemyIcon: (json['enemyIcon'] ?? json['enemy_icon']) as String? ?? 'skull',
      bossIcon: (json['bossIcon'] ?? json['boss_icon']) as String? ?? 'skull',
      enemyImage: (json['enemyImage'] ?? json['enemy_image']) as String?,
      bossImage: (json['bossImage'] ?? json['boss_image']) as String?,
      backgroundImage: (json['backgroundImage'] ?? json['background_image']) as String?,
      hpMultiplier: ((json['hpMultiplier'] ?? json['hp_multiplier']) as num?)?.toDouble() ?? 1.0,
      speedMultiplier: ((json['speedMultiplier'] ?? json['speed_multiplier']) as num?)?.toDouble() ?? 1.0,
      enemyCountModifier: ((json['enemyCountModifier'] ?? json['enemy_count_modifier']) as num?)?.toInt() ?? 0,
      lanePattern: (json['lanePattern'] ?? json['lane_pattern']) != null
          ? LanePatternDef.fromJson(Map<String, dynamic>.from((json['lanePattern'] ?? json['lane_pattern']) as Map))
          : const LanePatternDef(type: 'spread'),
      enemyModifiers: _parseEffectList(json['enemyModifiers'] ?? json['enemy_modifiers']),
      bossModifiers: _parseEffectList(json['bossModifiers'] ?? json['boss_modifiers']),
      particles: json['particles'] != null
          ? ParticleDef.fromJson(Map<String, dynamic>.from(json['particles'] as Map))
          : null,
      modifierScaling: _parseModifierScaling(json['modifierScaling']),
    );
  }

  static Map<int, ({List<EffectDef>? enemyMods, List<EffectDef>? bossMods})>
      _parseModifierScaling(dynamic raw) {
    if (raw == null || raw is! Map) return const {};
    final result = <int, ({List<EffectDef>? enemyMods, List<EffectDef>? bossMods})>{};
    for (final entry in (raw as Map<String, dynamic>).entries) {
      final level = int.tryParse(entry.key);
      if (level == null) continue;
      final tier = entry.value as Map<String, dynamic>;
      result[level] = (
        enemyMods: tier.containsKey('enemyModifiers')
            ? _parseEffectList(tier['enemyModifiers'])
            : null,
        bossMods: tier.containsKey('bossModifiers')
            ? _parseEffectList(tier['bossModifiers'])
            : null,
      );
    }
    return result;
  }

  @override
  String toString() => 'TdDungeonDef($key, $name)';
}

// ---------------------------------------------------------------------------
// TdRotationDef — rotation from rotation.json
// ---------------------------------------------------------------------------

/// Describes which dungeons are available in the current rotation.
class TdRotationDef {
  final int version;
  final String season;
  final List<String> dungeonKeys;

  const TdRotationDef({
    this.version = 1,
    this.season = '',
    this.dungeonKeys = const [],
  });

  factory TdRotationDef.fromJson(Map<String, dynamic> json) {
    return TdRotationDef(
      version: (json['version'] as num?)?.toInt() ?? 1,
      season: json['season'] as String? ?? '',
      dungeonKeys: ((json['dungeons'] ?? json['dungeon_keys']) as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  @override
  String toString() => 'TdRotationDef(v$version, $season, ${dungeonKeys.length} dungeons)';
}

// ---------------------------------------------------------------------------
// Icon mapping utility
// ---------------------------------------------------------------------------

/// Maps string icon names (used in dungeon JSON) to Material [IconData].
class TdIcons {
  TdIcons._();

  static const Map<String, IconData> iconMap = {
    'ghost': Icons.blur_on_rounded,
    'fire': Icons.local_fire_department,
    'demon': Icons.coronavirus_rounded,
    'portal': Icons.blur_circular_rounded,
    'beast': Icons.pets_rounded,
    'troll': Icons.sports_mma_rounded,
    'undead': Icons.dangerous_rounded,
    'skull': Icons.dangerous_rounded,
    'arcane': Icons.auto_awesome_rounded,
    'void': Icons.dark_mode_rounded,
    'frost': Icons.ac_unit_rounded,
    'death_knight': Icons.shield_rounded,
    'tentacle': Icons.pest_control_rounded,
    'wind': Icons.air_rounded,
    'bird': Icons.flight_rounded,
  };

  /// Look up an icon by name. Returns a question-mark icon as fallback.
  static IconData getIcon(String name) {
    return iconMap[name.toLowerCase().trim()] ?? Icons.help_outline_rounded;
  }
}

// ---------------------------------------------------------------------------
// Class icon mapping utility
// ---------------------------------------------------------------------------

/// Maps WoW class names to their icon asset paths.
class TdClassIcons {
  TdClassIcons._();

  static const Map<String, String> _classFileMap = {
    'warrior': 'warrior',
    'rogue': 'rogue',
    'death knight': 'deathknight',
    'paladin': 'paladin',
    'monk': 'monk',
    'demon hunter': 'demon_hunter',
    'mage': 'mage',
    'hunter': 'hunter',
    'warlock': 'warlock',
    'evoker': 'evoker',
    'priest': 'priest',
    'druid': 'druid',
    'shaman': 'shaman',
  };

  /// Get the asset path for a WoW class icon.
  /// Returns null if the class is not recognized.
  static String? assetPath(String className) {
    final filename = _classFileMap[className.toLowerCase().trim()];
    if (filename == null) return null;
    return 'assets/td/icons/classes/$filename.png';
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Parse a hex color string (e.g. "#C69B6D", "C69B6D", "#FFC69B6D") into a
/// [Color]. Returns white if the input is null or unparseable.
Color _parseColor(String? hex) {
  if (hex == null || hex.isEmpty) return const Color(0xFFFFFFFF);

  String cleaned = hex.trim();
  if (cleaned.startsWith('#')) {
    cleaned = cleaned.substring(1);
  }

  // 6-char hex → add FF alpha prefix
  if (cleaned.length == 6) {
    cleaned = 'FF$cleaned';
  }

  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return const Color(0xFFFFFFFF);

  return Color(value);
}

/// Parse a JSON list of effect objects into [List<EffectDef>].
List<EffectDef> _parseEffectList(dynamic json) {
  if (json == null || json is! List) return const [];
  return json
      .map((e) => EffectDef.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
}
