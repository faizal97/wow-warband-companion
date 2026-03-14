import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/character.dart';
import 'battlenet_api_service.dart';
import 'battlenet_auth_service.dart';
import 'character_cache_service.dart';

/// Manages character state across the app.
class CharacterProvider extends ChangeNotifier {
  final BattleNetApiService _apiService;
  final BattleNetAuthService _authService;
  final CharacterCacheService _cacheService;

  List<WowCharacter> _characters = [];
  WowCharacter? _selectedCharacter;
  bool _isLoading = false;
  bool _useMockData = true; // Toggled off after successful OAuth

  CharacterProvider(this._apiService, this._authService, this._cacheService);

  List<WowCharacter> get characters => _characters;
  WowCharacter? get selectedCharacter => _selectedCharacter;
  bool get isLoading => _isLoading;
  bool get hasCharacters => _characters.isNotEmpty;

  /// Switch to real API mode (called after successful OAuth).
  void useRealApi() {
    _useMockData = false;
  }

  /// Load characters — uses mock data in dev, real API in production.
  Future<void> loadCharacters() async {
    _isLoading = true;
    notifyListeners();

    if (_useMockData) {
      await Future.delayed(const Duration(milliseconds: 800));
      _characters = WowCharacter.mockCharacters();
    } else {
      _characters = await _apiService.getAccountCharacters();
    }

    // Auto-select the first (highest level) character
    if (_characters.isNotEmpty && _selectedCharacter == null) {
      _selectedCharacter = _characters.first;
    }

    _isLoading = false;
    notifyListeners();

    // Enrich characters in the background (after list is displayed)
    if (!_useMockData && _characters.isNotEmpty) {
      _enrichAllCharacters();
    }
  }

  /// Enriches all characters with detailed profile data.
  ///
  /// Checks the cache first; uncached characters are fetched in parallel.
  /// Updates the UI progressively as each character is enriched.
  Future<void> _enrichAllCharacters() async {
    final toFetch = <int>[]; // indices of characters needing API fetch

    // First pass: apply cached data immediately
    for (var i = 0; i < _characters.length; i++) {
      final cached = _cacheService.getCached(_characters[i].id);
      if (cached != null) {
        _characters[i] = cached;
      } else {
        toFetch.add(i);
      }
    }

    if (toFetch.isEmpty) {
      notifyListeners();
      return;
    }

    // Notify once for all cache hits
    notifyListeners();

    // Fire all uncached enrichment requests in parallel
    final futures = toFetch.map((index) async {
      final enriched = await _apiService.enrichCharacter(_characters[index]);
      _characters[index] = enriched;
      _cacheService.cache(enriched);

      // Update the selected character if it was enriched
      if (_selectedCharacter?.id == enriched.id) {
        _selectedCharacter = enriched;
      }

      // Progressive UI update
      notifyListeners();
    });

    await Future.wait(futures);
  }

  /// Force-refreshes all characters by clearing cache and reloading.
  Future<void> forceRefresh() async {
    _cacheService.clearAll();
    _selectedCharacter = null;
    await loadCharacters();
  }

  /// Select a character and fetch their detailed profile.
  Future<void> selectCharacter(WowCharacter character) async {
    _selectedCharacter = character;
    notifyListeners();

    if (!_useMockData) {
      // Fetch detailed profile with avatar/render
      final detailed = await _apiService.getCharacterProfile(
        character.realmSlug,
        character.name,
      );
      if (detailed != null) {
        _selectedCharacter = detailed;
        notifyListeners();
      }
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    _cacheService.clearAll();
    _characters = [];
    _selectedCharacter = null;
    notifyListeners();
  }
}
