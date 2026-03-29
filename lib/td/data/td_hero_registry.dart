import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../../models/character.dart';
import 'effect_types.dart';
import 'td_class_registry.dart';

class TdHeroRegistry {
  final Map<String, _HeroDef> _heroes = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Load heroes from assets/td/heroes.json
  Future<void> load() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/td/heroes.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      final heroes = data['heroes'] as List<dynamic>? ?? [];
      for (final entry in heroes) {
        final hero = _HeroDef.fromJson(entry as Map<String, dynamic>);
        _heroes[hero.name.toLowerCase()] = hero;
      }

      _loaded = true;
    } catch (e) {
      _loaded = true; // mark as loaded even on error so game doesn't hang
    }
  }

  /// Get all hero characters as WowCharacter list.
  List<WowCharacter> getHeroes() {
    return _heroes.values.map((h) => h.toCharacter()).toList();
  }

  /// Get a hero-specific class def override by character name.
  /// Returns null if the character is not a hero.
  TdClassDef? getHeroClassDef(
      String characterName, TdClassRegistry classRegistry) {
    final hero = _heroes[characterName.toLowerCase()];
    if (hero == null) return null;
    // Get the base class def for archetype and attackColor
    final baseDef = classRegistry.getClass(hero.className);
    // Return a new TdClassDef with the hero's passive override
    return TdClassDef(
      name: baseDef.name,
      archetype: baseDef.archetype,
      passive: hero.passive,
      empoweredPassive: hero.empoweredPassive,
      attackColor: baseDef.attackColor,
      activeAbility: baseDef.activeAbility,
      ultimateAbility: baseDef.ultimateAbility,
    );
  }
}

class _HeroDef {
  final int id;
  final String name;
  final String className;
  final String spec;
  final String race;
  final String faction;
  final int level;
  final int itemLevel;
  final String avatar;
  final PassiveDef passive;
  final PassiveDef? empoweredPassive;

  const _HeroDef({
    required this.id,
    required this.name,
    required this.className,
    required this.spec,
    required this.race,
    required this.faction,
    required this.level,
    required this.itemLevel,
    required this.avatar,
    required this.passive,
    this.empoweredPassive,
  });

  factory _HeroDef.fromJson(Map<String, dynamic> json) {
    return _HeroDef(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? 'Unknown',
      className: json['class'] as String? ?? 'Unknown',
      spec: json['spec'] as String? ?? 'Unknown',
      race: json['race'] as String? ?? 'Unknown',
      faction: json['faction'] as String? ?? 'Unknown',
      level: (json['level'] as num?)?.toInt() ?? 90,
      itemLevel: (json['itemLevel'] as num?)?.toInt() ?? 250,
      avatar: json['avatar'] as String? ?? '',
      passive: json['passive'] != null
          ? PassiveDef.fromJson(
              Map<String, dynamic>.from(json['passive'] as Map))
          : const PassiveDef(name: 'None'),
      empoweredPassive: json['empoweredPassive'] != null
          ? PassiveDef.fromJson(
              Map<String, dynamic>.from(json['empoweredPassive'] as Map))
          : null,
    );
  }

  WowCharacter toCharacter() {
    return WowCharacter(
      id: id,
      name: name,
      realm: 'Azeroth',
      realmSlug: 'azeroth',
      level: level,
      characterClass: className,
      activeSpec: spec,
      race: race,
      faction: faction,
      equippedItemLevel: itemLevel,
      avatarUrl: 'asset:$avatar',
    );
  }
}
