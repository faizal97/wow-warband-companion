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
  int _loadGeneration = 0;

  CharacterProvider(this._apiService, this._authService, this._cacheService);

  List<WowCharacter> get characters => _characters;
  WowCharacter? get selectedCharacter => _selectedCharacter;
  bool get isLoading => _isLoading;
  bool get hasCharacters => _characters.isNotEmpty;

  /// Bumps the load generation, causing any in-flight load to be discarded.
  void bumpLoadGeneration() {
    _loadGeneration++;
  }

  /// Load characters from the Battle.net API.
  Future<void> loadCharacters() async {
    final generation = _loadGeneration;

    _isLoading = true;
    notifyListeners();

    final chars = await _apiService.getAccountCharacters();
    if (_loadGeneration != generation) return;
    _characters = chars;

    // Auto-select the first (highest level) character
    if (_characters.isNotEmpty && _selectedCharacter == null) {
      _selectedCharacter = _characters.first;
    }

    _isLoading = false;
    notifyListeners();

    // Enrich characters in the background (after list is displayed)
    if (_characters.isNotEmpty) {
      _enrichAllCharacters();
    }
  }

  /// Enriches all characters with detailed profile data.
  ///
  /// Checks the cache first; uncached characters are fetched in parallel.
  /// Updates the UI progressively as each character is enriched.
  Future<void> _enrichAllCharacters() async {
    final toFetch = <int>[]; // indices of characters needing API fetch
    final generation = _loadGeneration;

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
      if (_loadGeneration != generation) return;
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

  Future<void> logout() async {
    await _authService.logout();
    _cacheService.clearAll();
    _characters = [];
    _selectedCharacter = null;
    notifyListeners();
  }
}
