import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/character.dart';
import '../models/equipped_item.dart';
import '../models/mythic_plus_profile.dart';
import '../models/achievement.dart';
import '../models/raid_progression.dart';

/// Caches enriched character data using SharedPreferences with a TTL.
class CharacterCacheService {
  static const String _keyPrefix = 'wow_char_';
  static const String _equipPrefix = 'wow_equip_';
  static const String _mplusPrefix = 'wow_mplus_';
  static const String _raidPrefix = 'wow_raid_';
  static const String _achCatPrefix = 'wow_ach_cat_';
  static const String _achDefsPrefix = 'wow_ach_defs_';
  static const int _achTtlMinutes = 7 * 24 * 60; // 7 days for static data
  static const int _ttlMinutes = 15;

  final SharedPreferences _prefs;

  CharacterCacheService(this._prefs);

  /// Returns a cached [WowCharacter] if it exists and is not stale.
  WowCharacter? getCached(int id) {
    final raw = _prefs.getString('$_keyPrefix$id');
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = json['_cachedAt'] as int?;
      if (cachedAt == null) return null;

      final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
      if (age > _ttlMinutes * 60 * 1000) {
        _prefs.remove('$_keyPrefix$id');
        return null;
      }

      final charJson = Map<String, dynamic>.from(json)..remove('_cachedAt');
      return WowCharacter.fromJson(charJson);
    } catch (_) {
      return null;
    }
  }

  /// Stores an enriched [WowCharacter].
  void cache(WowCharacter character) {
    final json = character.toJson();
    json['_cachedAt'] = DateTime.now().millisecondsSinceEpoch;
    _prefs.setString('$_keyPrefix${character.id}', jsonEncode(json));
  }

  /// Returns cached [CharacterEquipment] if it exists and is not stale.
  CharacterEquipment? getCachedEquipment(int characterId) {
    final raw = _prefs.getString('$_equipPrefix$characterId');
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = json['_cachedAt'] as int?;
      if (cachedAt == null) return null;

      final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
      if (age > _ttlMinutes * 60 * 1000) {
        _prefs.remove('$_equipPrefix$characterId');
        return null;
      }

      final dataJson = Map<String, dynamic>.from(json)..remove('_cachedAt');
      return CharacterEquipment.fromJson(dataJson);
    } catch (_) {
      return null;
    }
  }

  /// Stores [CharacterEquipment].
  void cacheEquipment(int characterId, CharacterEquipment equipment) {
    final json = equipment.toJson();
    json['_cachedAt'] = DateTime.now().millisecondsSinceEpoch;
    _prefs.setString('$_equipPrefix$characterId', jsonEncode(json));
  }

  /// Returns cached [MythicPlusProfile] if it exists and is not stale.
  MythicPlusProfile? getCachedMythicPlus(int characterId) {
    final raw = _prefs.getString('$_mplusPrefix$characterId');
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = json['_cachedAt'] as int?;
      if (cachedAt == null) return null;

      final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
      if (age > _ttlMinutes * 60 * 1000) {
        _prefs.remove('$_mplusPrefix$characterId');
        return null;
      }

      final dataJson = Map<String, dynamic>.from(json)..remove('_cachedAt');
      return MythicPlusProfile.fromJson(dataJson);
    } catch (_) {
      return null;
    }
  }

  /// Stores [MythicPlusProfile].
  void cacheMythicPlus(int characterId, MythicPlusProfile profile) {
    final json = profile.toJson();
    json['_cachedAt'] = DateTime.now().millisecondsSinceEpoch;
    _prefs.setString('$_mplusPrefix$characterId', jsonEncode(json));
  }

  /// Removes cached equipment for a specific character.
  void clearEquipment(int characterId) {
    _prefs.remove('$_equipPrefix$characterId');
  }

  /// Removes cached M+ data for a specific character.
  void clearMythicPlus(int characterId) {
    _prefs.remove('$_mplusPrefix$characterId');
  }

  /// Returns cached [RaidProgression] if it exists and is not stale.
  RaidProgression? getCachedRaidProgression(int characterId) {
    final raw = _prefs.getString('$_raidPrefix$characterId');
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = json['_cachedAt'] as int?;
      if (cachedAt == null) return null;

      final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
      if (age > _ttlMinutes * 60 * 1000) {
        _prefs.remove('$_raidPrefix$characterId');
        return null;
      }

      final dataJson = Map<String, dynamic>.from(json)..remove('_cachedAt');
      return RaidProgression.fromJson(dataJson);
    } catch (_) {
      return null;
    }
  }

  /// Stores [RaidProgression].
  void cacheRaidProgression(int characterId, RaidProgression progression) {
    final json = progression.toJson();
    json['_cachedAt'] = DateTime.now().millisecondsSinceEpoch;
    _prefs.setString('$_raidPrefix$characterId', jsonEncode(json));
  }

  /// Removes cached raid data for a specific character.
  void clearRaidProgression(int characterId) {
    _prefs.remove('$_raidPrefix$characterId');
  }

  /// Returns cached [AchievementCategory] if it exists and is not stale.
  AchievementCategory? getCachedAchievementCategory(int categoryId) {
    final raw = _prefs.getString('$_achCatPrefix$categoryId');
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = json['_cachedAt'] as int?;
      if (cachedAt == null) return null;

      final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
      if (age > _achTtlMinutes * 60 * 1000) {
        _prefs.remove('$_achCatPrefix$categoryId');
        return null;
      }

      final dataJson = Map<String, dynamic>.from(json)..remove('_cachedAt');
      return AchievementCategory.fromJson(dataJson);
    } catch (_) {
      return null;
    }
  }

  /// Stores an [AchievementCategory].
  void cacheAchievementCategory(AchievementCategory category) {
    final json = category.toJson();
    json['_cachedAt'] = DateTime.now().millisecondsSinceEpoch;
    _prefs.setString('$_achCatPrefix${category.id}', jsonEncode(json));
  }

  /// Returns cached achievement definitions for a category.
  List<Achievement>? getCachedAchievements(int categoryId) {
    final raw = _prefs.getString('$_achDefsPrefix$categoryId');
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = json['_cachedAt'] as int?;
      if (cachedAt == null) return null;

      final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
      if (age > _achTtlMinutes * 60 * 1000) {
        _prefs.remove('$_achDefsPrefix$categoryId');
        return null;
      }

      final list = json['achievements'] as List? ?? [];
      return list
          .map((e) => Achievement.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Stores achievement definitions for a category.
  void cacheAchievements(int categoryId, List<Achievement> achievements) {
    final json = <String, dynamic>{
      'achievements': achievements.map((a) => a.toJson()).toList(),
      '_cachedAt': DateTime.now().millisecondsSinceEpoch,
    };
    _prefs.setString('$_achDefsPrefix$categoryId', jsonEncode(json));
  }

  /// Removes cached achievement category data.
  void clearAchievementCategory(int categoryId) {
    _prefs.remove('$_achCatPrefix$categoryId');
  }

  /// Removes cached achievement definitions for a category.
  void clearAchievements(int categoryId) {
    _prefs.remove('$_achDefsPrefix$categoryId');
  }

  /// Removes all cached data.
  void clearAll() {
    final keys = _prefs.getKeys().where((key) =>
        key.startsWith(_keyPrefix) ||
        key.startsWith(_equipPrefix) ||
        key.startsWith(_mplusPrefix) ||
        key.startsWith(_raidPrefix) ||
        key.startsWith(_achCatPrefix) ||
        key.startsWith(_achDefsPrefix));

    for (final key in keys.toList()) {
      _prefs.remove(key);
    }
  }
}
