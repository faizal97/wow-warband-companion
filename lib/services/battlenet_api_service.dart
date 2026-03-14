import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/character.dart';
import '../models/equipped_item.dart';
import '../models/mythic_plus_profile.dart';
import '../models/achievement.dart';
import '../models/raid_progression.dart';
import 'battlenet_auth_service.dart';

/// Fetches WoW character data from the Battle.net API.
///
/// API docs: https://develop.battle.net/documentation/world-of-warcraft
class BattleNetApiService {
  final BattleNetAuthService _authService;

  // Default to US region; make configurable later
  static const String _apiBase = 'https://us.api.blizzard.com';
  static const String _namespace = 'profile-us';
  static const String _locale = 'en_US';
  static const String _staticNamespace = 'static-us';

  BattleNetApiService(this._authService);

  /// Fetches all characters on the authenticated user's account.
  Future<List<WowCharacter>> getAccountCharacters() async {
    final token = await _authService.getAccessToken();
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse(
            '$_apiBase/profile/user/wow?namespace=$_namespace&locale=$_locale'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final accounts = data['wow_accounts'] as List? ?? [];
        final characters = <WowCharacter>[];

        for (final account in accounts) {
          final chars = account['characters'] as List? ?? [];
          for (final char in chars) {
            characters.add(WowCharacter.fromJson(char));
          }
        }

        // Sort by level descending, then by name
        characters.sort((a, b) {
          final levelCompare = b.level.compareTo(a.level);
          if (levelCompare != 0) return levelCompare;
          return a.name.compareTo(b.name);
        });

        return characters;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Enriches a character by fetching profile + media in parallel.
  ///
  /// Returns the character merged with spec, ilvl, avatar, render, and
  /// last login data. Falls back to the original character on error.
  Future<WowCharacter> enrichCharacter(WowCharacter character) async {
    final token = await _authService.getAccessToken();
    if (token == null) return character;

    final name = character.name.toLowerCase();
    final realmSlug = character.realmSlug;

    try {
      // Fire profile + media requests in parallel
      final results = await Future.wait([
        http.get(
          Uri.parse(
              '$_apiBase/profile/wow/character/$realmSlug/$name?namespace=$_namespace&locale=$_locale'),
          headers: {'Authorization': 'Bearer $token'},
        ),
        http.get(
          Uri.parse(
              '$_apiBase/profile/wow/character/$realmSlug/$name/character-media?namespace=$_namespace&locale=$_locale'),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ]);

      final profileResponse = results[0];
      final mediaResponse = results[1];

      String? activeSpec;
      int? equippedItemLevel;
      int? lastLoginTimestamp;
      int? achievementPoints;
      String? gender;

      if (profileResponse.statusCode == 200) {
        final data = jsonDecode(profileResponse.body);
        activeSpec = data['active_spec']?['name'] as String?;
        equippedItemLevel = data['equipped_item_level'] as int?;
        lastLoginTimestamp = data['last_login_timestamp'] as int?;
        achievementPoints = data['achievement_points'] as int?;
        gender = (data['gender']?['name'] as String?) ??
            (data['gender']?['type'] as String?);
      }

      String? avatarUrl;
      String? renderUrl;

      if (mediaResponse.statusCode == 200) {
        final mediaData = jsonDecode(mediaResponse.body);
        final assets = mediaData['assets'] as List? ?? [];
        for (final asset in assets) {
          if (asset['key'] == 'avatar') avatarUrl = asset['value'] as String?;
          if (asset['key'] == 'main-raw') {
            renderUrl = asset['value'] as String?;
          }
        }
      }

      return character.copyWith(
        activeSpec: activeSpec ?? character.activeSpec,
        equippedItemLevel: equippedItemLevel ?? character.equippedItemLevel,
        avatarUrl: avatarUrl ?? character.avatarUrl,
        renderUrl: renderUrl ?? character.renderUrl,
        lastLoginTimestamp:
            lastLoginTimestamp ?? character.lastLoginTimestamp,
        achievementPoints:
            achievementPoints ?? character.achievementPoints,
        gender: gender ?? character.gender,
      );
    } catch (_) {
      return character;
    }
  }

  /// Fetches detailed character profile including rendered avatar.
  Future<WowCharacter?> getCharacterProfile(
      String realmSlug, String characterName) async {
    final token = await _authService.getAccessToken();
    if (token == null) return null;

    final name = characterName.toLowerCase();
    try {
      // Fetch profile summary
      final response = await http.get(
        Uri.parse(
            '$_apiBase/profile/wow/character/$realmSlug/$name?namespace=$_namespace&locale=$_locale'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Fetch character media (avatar/render)
        String? avatarUrl;
        String? renderUrl;
        try {
          final mediaResponse = await http.get(
            Uri.parse(
                '$_apiBase/profile/wow/character/$realmSlug/$name/character-media?namespace=$_namespace&locale=$_locale'),
            headers: {'Authorization': 'Bearer $token'},
          );
          if (mediaResponse.statusCode == 200) {
            final mediaData = jsonDecode(mediaResponse.body);
            final assets = mediaData['assets'] as List? ?? [];
            for (final asset in assets) {
              if (asset['key'] == 'avatar') avatarUrl = asset['value'];
              if (asset['key'] == 'main-raw') renderUrl = asset['value'];
            }
          }
        } catch (_) {}

        return WowCharacter(
          id: data['id'] as int,
          name: data['name'] as String,
          realm: data['realm']?['name'] as String? ?? 'Unknown',
          realmSlug: realmSlug,
          level: data['level'] as int? ?? 0,
          characterClass:
              data['character_class']?['name'] as String? ?? 'Unknown',
          activeSpec: data['active_spec']?['name'] as String? ?? 'Unknown',
          race: data['race']?['name'] as String? ?? 'Unknown',
          faction: data['faction']?['name'] as String? ?? 'Unknown',
          avatarUrl: avatarUrl,
          renderUrl: renderUrl,
          equippedItemLevel:
              data['equipped_item_level'] as int?,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches equipped items for a character.
  Future<CharacterEquipment?> getCharacterEquipment(
      String realmSlug, String name) async {
    final token = await _authService.getAccessToken();
    if (token == null) return null;

    final charName = name.toLowerCase();
    try {
      final response = await http.get(
        Uri.parse(
            '$_apiBase/profile/wow/character/$realmSlug/$charName/equipment?namespace=$_namespace&locale=$_locale'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return CharacterEquipment.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches the Mythic+ profile (rating + season list) for a character.
  ///
  /// Does NOT include best runs — use [getMythicPlusSeason] for those.
  Future<MythicPlusProfile?> getMythicPlusProfile(
      String realmSlug, String name) async {
    final token = await _authService.getAccessToken();
    if (token == null) return null;

    final charName = name.toLowerCase();
    try {
      final response = await http.get(
        Uri.parse(
            '$_apiBase/profile/wow/character/$realmSlug/$charName/mythic-keystone-profile?namespace=$_namespace&locale=$_locale'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return MythicPlusProfile.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Enriches equipment items with icon URLs by fetching media endpoints in parallel.
  Future<CharacterEquipment> enrichEquipmentIcons(
      CharacterEquipment equipment) async {
    final token = await _authService.getAccessToken();
    if (token == null) return equipment;

    final items = List<EquippedItem>.from(equipment.equippedItems);
    final futures = <Future>[];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.iconUrl != null || item.mediaHref == null) continue;

      final index = i;
      futures.add(() async {
        try {
          final response = await http.get(
            Uri.parse(item.mediaHref!),
            headers: {'Authorization': 'Bearer $token'},
          );
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final assets = data['assets'] as List? ?? [];
            for (final asset in assets) {
              if (asset['key'] == 'icon') {
                items[index] =
                    items[index].copyWith(iconUrl: asset['value'] as String?);
                break;
              }
            }
          }
        } catch (_) {}
      }());
    }

    await Future.wait(futures);
    return CharacterEquipment(equippedItems: items);
  }

  /// Enriches M+ best runs with dungeon icons.
  ///
  /// Tries two approaches per dungeon:
  /// 1. `/data/wow/mythic-keystone/dungeon/{id}` → follow media ref
  /// 2. `/data/wow/media/dungeon/{id}` as direct fallback
  Future<MythicPlusProfile> enrichDungeonIcons(
      MythicPlusProfile profile) async {
    final token = await _authService.getAccessToken();
    if (token == null) return profile;

    final runs = List<MythicPlusBestRun>.from(profile.bestRuns);
    final uniqueIds = <int>{};
    final iconMap = <int, String>{};

    for (final run in runs) {
      if (run.iconUrl == null && run.dungeonId > 0) {
        uniqueIds.add(run.dungeonId);
      }
    }

    if (uniqueIds.isEmpty) return profile;

    final staticNamespace = _namespace.replaceAll('profile', 'static');
    final headers = {'Authorization': 'Bearer $token'};

    final futures = uniqueIds.map((dungeonId) async {
      try {
        // Try 1: Get dungeon details, follow media href
        final dungeonResponse = await http.get(
          Uri.parse(
              '$_apiBase/data/wow/mythic-keystone/dungeon/$dungeonId?namespace=dynamic-us&locale=$_locale'),
          headers: headers,
        );

        if (dungeonResponse.statusCode == 200) {
          final data = jsonDecode(dungeonResponse.body);

          // Check for direct media reference
          final mediaHref = data['media']?['key']?['href'] as String?;
          if (mediaHref != null) {
            final mediaResponse = await http.get(
              Uri.parse(mediaHref),
              headers: headers,
            );
            if (mediaResponse.statusCode == 200) {
              final mediaData = jsonDecode(mediaResponse.body);
              final assets = mediaData['assets'] as List? ?? [];
              for (final asset in assets) {
                iconMap[dungeonId] = asset['value'] as String;
                return;
              }
            }
          }

          // Check for dungeon.id (journal instance id)
          final instanceId = data['dungeon']?['id'] as int?;
          if (instanceId != null) {
            final mediaResponse = await http.get(
              Uri.parse(
                  '$_apiBase/data/wow/media/journal-instance/$instanceId?namespace=$staticNamespace&locale=$_locale'),
              headers: headers,
            );
            if (mediaResponse.statusCode == 200) {
              final mediaData = jsonDecode(mediaResponse.body);
              final assets = mediaData['assets'] as List? ?? [];
              for (final asset in assets) {
                iconMap[dungeonId] = asset['value'] as String;
                return;
              }
            }
          }
        }
      } catch (_) {}
    });

    await Future.wait(futures);

    for (var i = 0; i < runs.length; i++) {
      final icon = iconMap[runs[i].dungeonId];
      if (icon != null) {
        runs[i] = runs[i].copyWith(iconUrl: icon);
      }
    }

    return profile.copyWith(bestRuns: runs);
  }

  /// Fetches raid encounter data for a character.
  ///
  /// Returns the latest expansion's raids with per-difficulty boss kills.
  Future<RaidProgression?> getRaidEncounters(
      String realmSlug, String name) async {
    final token = await _authService.getAccessToken();
    if (token == null) return null;

    final charName = name.toLowerCase();
    try {
      final response = await http.get(
        Uri.parse(
            '$_apiBase/profile/wow/character/$realmSlug/$charName/encounters/raids?namespace=$_namespace&locale=$_locale'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return RaidProgression.fromApiJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Enriches raid instances with icons from journal-instance media.
  Future<RaidProgression> enrichRaidIcons(RaidProgression progression) async {
    final token = await _authService.getAccessToken();
    if (token == null) return progression;

    final staticNamespace = _namespace.replaceAll('profile', 'static');
    final headers = {'Authorization': 'Bearer $token'};
    final instances = List<RaidInstance>.from(progression.instances);

    final futures = <Future>[];

    for (var i = 0; i < instances.length; i++) {
      final inst = instances[i];
      if (inst.iconUrl != null) continue;

      final index = i;
      futures.add(() async {
        try {
          final response = await http.get(
            Uri.parse(
                '$_apiBase/data/wow/media/journal-instance/${inst.id}?namespace=$staticNamespace&locale=$_locale'),
            headers: headers,
          );
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final assets = data['assets'] as List? ?? [];
            for (final asset in assets) {
              if (asset['key'] == 'tile') {
                instances[index] =
                    instances[index].copyWith(iconUrl: asset['value'] as String?);
                return;
              }
            }
            // Fallback to first asset if no 'tile' key
            if (assets.isNotEmpty) {
              instances[index] = instances[index]
                  .copyWith(iconUrl: assets.first['value'] as String?);
            }
          }
        } catch (_) {}
      }());
    }

    await Future.wait(futures);
    return progression.copyWith(instances: instances);
  }

  /// Fetches a specific Mythic+ season's best runs for a character.
  Future<MythicPlusProfile?> getMythicPlusSeason(
      String realmSlug, String name, int seasonId) async {
    final token = await _authService.getAccessToken();
    if (token == null) return null;

    final charName = name.toLowerCase();
    try {
      final response = await http.get(
        Uri.parse(
            '$_apiBase/profile/wow/character/$realmSlug/$charName/mythic-keystone-profile/season/$seasonId?namespace=$_namespace&locale=$_locale'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return MythicPlusProfile.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches boss portrait images for a list of encounter IDs.
  ///
  /// Two-step: fetch journal-encounter to get creature display info,
  /// then fetch the creature-display media for the actual image.
  Future<Map<int, String>> fetchBossIcons(List<int> encounterIds) async {
    final token = await _authService.getAccessToken();
    if (token == null) return {};

    final staticNamespace = _namespace.replaceAll('profile', 'static');
    final headers = {'Authorization': 'Bearer $token'};
    final iconMap = <int, String>{};

    final futures = encounterIds.map((id) async {
      try {
        // Step 1: Fetch journal encounter to get creature display info
        final encounterResponse = await http.get(
          Uri.parse(
              '$_apiBase/data/wow/journal-encounter/$id?namespace=$staticNamespace&locale=$_locale'),
          headers: headers,
        );

        if (encounterResponse.statusCode != 200) return;

        final encounterData = jsonDecode(encounterResponse.body);
        final creatures = encounterData['creatures'] as List? ?? [];
        if (creatures.isEmpty) return;

        // Get the first creature's display media href
        final creature = creatures.first;
        final displayHref =
            creature['creature_display']?['key']?['href'] as String?;

        if (displayHref != null) {
          // Step 2: Fetch creature display media
          final mediaResponse = await http.get(
            Uri.parse(displayHref),
            headers: headers,
          );
          if (mediaResponse.statusCode == 200) {
            final mediaData = jsonDecode(mediaResponse.body);
            final assets = mediaData['assets'] as List? ?? [];
            // Prefer 'avatar' (close-up head), then 'zoom', then 'render'
            for (final key in ['avatar', 'zoom', 'render']) {
              for (final asset in assets) {
                if (asset['key'] == key) {
                  iconMap[id] = asset['value'] as String;
                  return;
                }
              }
            }
            if (assets.isNotEmpty) {
              iconMap[id] = assets.first['value'] as String;
            }
          }
        }
      } catch (_) {}
    });

    await Future.wait(futures);
    return iconMap;
  }

  /// Fetches the top-level achievement category index.
  Future<List<AchievementCategoryRef>> getAchievementCategoriesIndex() async {
    final token = await _authService.getAccessToken();
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse(
            '$_apiBase/data/wow/achievement-category/index?namespace=$_staticNamespace&locale=$_locale'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final categories = data['categories'] as List? ?? [];
        return categories
            .map((e) => AchievementCategoryRef.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Fetches a specific achievement category with subcategories and achievement refs.
  Future<AchievementCategory?> getAchievementCategory(int categoryId) async {
    final token = await _authService.getAccessToken();
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse(
            '$_apiBase/data/wow/achievement-category/$categoryId?namespace=$_staticNamespace&locale=$_locale'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return AchievementCategory.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches a single achievement definition with criteria tree.
  Future<Achievement?> getAchievement(int achievementId) async {
    final token = await _authService.getAccessToken();
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse(
            '$_apiBase/data/wow/achievement/$achievementId?namespace=$_staticNamespace&locale=$_locale'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Achievement.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches achievement icon URL from media endpoint.
  Future<String?> getAchievementMedia(int achievementId) async {
    final token = await _authService.getAccessToken();
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse(
            '$_apiBase/data/wow/media/achievement/$achievementId?namespace=$_staticNamespace&locale=$_locale'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final assets = data['assets'] as List? ?? [];
        for (final asset in assets) {
          if (asset['key'] == 'icon') {
            return asset['value'] as String?;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches account-wide achievement progress for a character.
  Future<AccountAchievementProgress?> getCharacterAchievements(
      String realmSlug, String characterName) async {
    final token = await _authService.getAccessToken();
    if (token == null) return null;

    final name = characterName.toLowerCase();
    try {
      final response = await http.get(
        Uri.parse(
            '$_apiBase/profile/wow/character/$realmSlug/$name/achievements?namespace=$_namespace&locale=$_locale'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return AccountAchievementProgress.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches multiple achievement definitions in parallel.
  Future<List<Achievement>> getAchievements(List<int> ids) async {
    final results = await Future.wait(
      ids.map((id) => getAchievement(id)),
    );
    return results.whereType<Achievement>().toList();
  }

  /// Enriches achievements with icon URLs by fetching media endpoints in parallel.
  Future<List<Achievement>> enrichAchievementIcons(List<Achievement> achievements) async {
    final token = await _authService.getAccessToken();
    if (token == null) return achievements;

    final result = List<Achievement>.from(achievements);
    final futures = <Future>[];

    for (var i = 0; i < result.length; i++) {
      final ach = result[i];
      if (ach.iconUrl != null) continue;

      final href = ach.mediaHref;
      if (href == null) continue;

      final index = i;
      futures.add(() async {
        try {
          final response = await http.get(
            Uri.parse(href),
            headers: {'Authorization': 'Bearer $token'},
          );
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final assets = data['assets'] as List? ?? [];
            for (final asset in assets) {
              if (asset['key'] == 'icon') {
                result[index] = result[index].copyWith(iconUrl: asset['value'] as String?);
                break;
              }
            }
          }
        } catch (_) {}
      }());
    }

    await Future.wait(futures);
    return result;
  }
}
