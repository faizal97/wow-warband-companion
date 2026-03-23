import 'package:flutter/foundation.dart';
import '../models/character.dart';
import '../models/equipped_item.dart';
import '../models/mythic_plus_profile.dart';
import '../models/raid_progression.dart';
import 'battlenet_api_service.dart';
import 'character_cache_service.dart';

/// Manages character detail state (equipment, M+ profile) for the detail dashboard.
class CharacterDetailProvider extends ChangeNotifier {
  final BattleNetApiService _apiService;
  final CharacterCacheService _cacheService;

  CharacterEquipment? _equipment;
  MythicPlusProfile? _mythicPlusProfile;
  RaidProgression? _raidProgression;
  int? _lastCharacterId;
  bool _isEquipmentLoading = false;
  bool _isMythicPlusLoading = false;
  bool _isRaidLoading = false;

  CharacterDetailProvider(this._apiService, this._cacheService);

  CharacterEquipment? get equipment => _equipment;
  MythicPlusProfile? get mythicPlusProfile => _mythicPlusProfile;
  RaidProgression? get raidProgression => _raidProgression;
  bool get isEquipmentLoading => _isEquipmentLoading;
  bool get isMythicPlusLoading => _isMythicPlusLoading;
  bool get isRaidLoading => _isRaidLoading;

  /// Loads equipment and M+ data for a character.
  ///
  /// Checks cache first, then fires uncached API calls concurrently.
  /// M+ data is fetched in two stages: profile (rating) then season (runs).
  Future<void> loadDetails(WowCharacter character) async {
    _reset();
    _lastCharacterId = character.id;
    _isEquipmentLoading = true;
    _isMythicPlusLoading = true;
    _isRaidLoading = true;
    notifyListeners();

    // Check cache first
    final cachedEquipment = _cacheService.getCachedEquipment(character.id);
    final cachedMythicPlus = _cacheService.getCachedMythicPlus(character.id);
    final cachedRaid = _cacheService.getCachedRaidProgression(character.id);

    if (cachedEquipment != null) {
      _equipment = cachedEquipment;
      _isEquipmentLoading = false;
    }

    if (cachedMythicPlus != null) {
      _mythicPlusProfile = cachedMythicPlus;
      _isMythicPlusLoading = false;
    }

    if (cachedRaid != null) {
      _raidProgression = cachedRaid;
      _isRaidLoading = false;
    }

    notifyListeners();

    // Check if cached data needs icon enrichment
    final needsEquipIcons = cachedEquipment != null &&
        cachedEquipment.equippedItems.any((i) => i.iconUrl == null && i.mediaHref != null);
    final needsMplusIcons = cachedMythicPlus != null &&
        cachedMythicPlus.bestRuns.any((r) => r.iconUrl == null && r.dungeonId > 0);
    final needsRaidIcons = cachedRaid != null &&
        cachedRaid.instances.any((i) => i.iconUrl == null);

    // Enrich cached data with missing icons in background
    if (needsEquipIcons) {
      _enrichEquipmentIcons(character.id);
    }
    if (needsMplusIcons) {
      _enrichMythicPlusIcons(character.id);
    }
    if (needsRaidIcons) {
      _enrichRaidIcons(character.id);
    }

    // If everything was cached, skip API fetch
    if (cachedEquipment != null && cachedMythicPlus != null && cachedRaid != null) {
      return;
    }

    final realmSlug = character.realmSlug;
    final name = character.name.toLowerCase();

    // Fire uncached API calls in parallel
    final futures = <Future>[];

    if (cachedEquipment == null) {
      futures.add(_fetchEquipment(realmSlug, name, character.id));
    }

    if (cachedMythicPlus == null) {
      futures.add(_fetchMythicPlus(realmSlug, name, character.id));
    }

    if (cachedRaid == null) {
      futures.add(_fetchRaidProgression(realmSlug, name, character.id));
    }

    await Future.wait(futures);
  }

  Future<void> _fetchEquipment(
      String realmSlug, String name, int characterId) async {
    try {
      var result = await _apiService.getCharacterEquipment(realmSlug, name);
      if (result != null) {
        _equipment = result;
        _isEquipmentLoading = false;
        notifyListeners(); // Show items immediately

        // Enrich with icons in parallel (progressive update)
        result = await _apiService.enrichEquipmentIcons(result);
        _equipment = result;
        _cacheService.cacheEquipment(characterId, result);
      }
    } catch (_) {
      // Silently fail — UI shows loading state
    }
    _isEquipmentLoading = false;
    notifyListeners();
  }

  Future<void> _fetchMythicPlus(
      String realmSlug, String name, int characterId) async {
    try {
      final profile =
          await _apiService.getMythicPlusProfile(realmSlug, name);

      if (profile != null) {
        _mythicPlusProfile = profile;
        notifyListeners();

        if (profile.latestSeasonId != null) {
          final seasonData = await _apiService.getMythicPlusSeason(
              realmSlug, name, profile.latestSeasonId!);

          if (seasonData != null) {
            _mythicPlusProfile = profile.copyWith(
              bestRuns: seasonData.bestRuns,
            );
            _isMythicPlusLoading = false;
            notifyListeners();

            // Stage 3: enrich dungeon icons in parallel
            final enriched =
                await _apiService.enrichDungeonIcons(_mythicPlusProfile!);
            _mythicPlusProfile = enriched;
            _cacheService.cacheMythicPlus(characterId, enriched);
            notifyListeners();
          }
        } else {
          _cacheService.cacheMythicPlus(characterId, profile);
        }
      }
    } catch (_) {
      // Silently fail — UI shows loading state
    }
    _isMythicPlusLoading = false;
    notifyListeners();
  }

  Future<void> _fetchRaidProgression(
      String realmSlug, String name, int characterId) async {
    try {
      final progression =
          await _apiService.getRaidEncounters(realmSlug, name);

      if (progression != null && progression.instances.isNotEmpty) {
        _raidProgression = progression;
        _isRaidLoading = false;
        notifyListeners();

        // Enrich with instance icons in parallel
        final enriched = await _apiService.enrichRaidIcons(progression);
        _raidProgression = enriched;
        _cacheService.cacheRaidProgression(characterId, enriched);
        notifyListeners();
      }
    } catch (_) {
      // Silently fail — UI shows loading state
    }
    _isRaidLoading = false;
    notifyListeners();
  }

  /// Enriches cached raid instances with missing icons.
  Future<void> _enrichRaidIcons(int characterId) async {
    if (_raidProgression == null) return;
    final enriched = await _apiService.enrichRaidIcons(_raidProgression!);
    _raidProgression = enriched;
    _cacheService.cacheRaidProgression(characterId, enriched);
    notifyListeners();
  }

  /// Loads boss portrait images for a specific raid instance.
  ///
  /// Called lazily when the user navigates into a raid detail screen.
  Future<void> loadBossIcons(int raidInstanceId) async {
    if (_raidProgression == null) return;

    final instanceIndex =
        _raidProgression!.instances.indexWhere((i) => i.id == raidInstanceId);
    if (instanceIndex == -1) return;

    final instance = _raidProgression!.instances[instanceIndex];

    // Only fetch icons we don't already have
    final needsIcons =
        instance.encounters.where((e) => e.iconUrl == null).map((e) => e.id).toList();
    if (needsIcons.isEmpty) return;

    final iconMap = await _apiService.fetchBossIcons(needsIcons);
    if (iconMap.isEmpty) return;

    // Update encounters with icons
    final updatedEncounters = instance.encounters.map((e) {
      final icon = iconMap[e.id];
      return icon != null ? e.copyWith(iconUrl: icon) : e;
    }).toList();

    final updatedInstances =
        List<RaidInstance>.from(_raidProgression!.instances);
    updatedInstances[instanceIndex] =
        instance.copyWith(encounters: updatedEncounters);

    _raidProgression = _raidProgression!.copyWith(instances: updatedInstances);
    // Update cache with boss icons
    _cacheService.cacheRaidProgression(
        _lastCharacterId ?? 0, _raidProgression!);
    notifyListeners();
  }

  /// Force-refreshes boss icons by clearing cached icons and refetching.
  Future<void> forceRefreshBossIcons(int raidInstanceId) async {
    if (_raidProgression == null) return;

    final instanceIndex =
        _raidProgression!.instances.indexWhere((i) => i.id == raidInstanceId);
    if (instanceIndex == -1) return;

    final instance = _raidProgression!.instances[instanceIndex];

    // Clear existing boss icons so they refetch
    final clearedEncounters = instance.encounters
        .map((e) => RaidEncounter(
              name: e.name,
              id: e.id,
              killCounts: e.killCounts,
            ))
        .toList();

    final updatedInstances =
        List<RaidInstance>.from(_raidProgression!.instances);
    updatedInstances[instanceIndex] =
        instance.copyWith(encounters: clearedEncounters);
    _raidProgression = _raidProgression!.copyWith(instances: updatedInstances);
    notifyListeners();

    // Refetch all boss icons
    final allIds = instance.encounters.map((e) => e.id).toList();
    final iconMap = await _apiService.fetchBossIcons(allIds);

    final refreshedEncounters = clearedEncounters.map((e) {
      final icon = iconMap[e.id];
      return icon != null ? e.copyWith(iconUrl: icon) : e;
    }).toList();

    updatedInstances[instanceIndex] =
        instance.copyWith(encounters: refreshedEncounters);
    _raidProgression = _raidProgression!.copyWith(instances: updatedInstances);
    _cacheService.cacheRaidProgression(
        _lastCharacterId ?? 0, _raidProgression!);
    notifyListeners();
  }

  /// Enriches cached equipment with missing icons.
  Future<void> _enrichEquipmentIcons(int characterId) async {
    if (_equipment == null) return;
    final enriched = await _apiService.enrichEquipmentIcons(_equipment!);
    _equipment = enriched;
    _cacheService.cacheEquipment(characterId, enriched);
    notifyListeners();
  }

  /// Enriches cached M+ runs with missing dungeon icons.
  Future<void> _enrichMythicPlusIcons(int characterId) async {
    if (_mythicPlusProfile == null) return;
    final enriched = await _apiService.enrichDungeonIcons(_mythicPlusProfile!);
    _mythicPlusProfile = enriched;
    _cacheService.cacheMythicPlus(characterId, enriched);
    notifyListeners();
  }

  /// Force-refreshes detail data by clearing cache and reloading.
  Future<void> forceRefresh(WowCharacter character) async {
    _cacheService.clearEquipment(character.id);
    _cacheService.clearMythicPlus(character.id);
    _cacheService.clearRaidProgression(character.id);
    await loadDetails(character);
  }

  /// Resets all state when switching characters.
  void _reset() {
    _equipment = null;
    _mythicPlusProfile = null;
    _raidProgression = null;
    _isEquipmentLoading = false;
    _isMythicPlusLoading = false;
    _isRaidLoading = false;
  }
}
