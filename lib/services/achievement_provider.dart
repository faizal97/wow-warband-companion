import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/achievement.dart';
import '../models/achievement_enrichment.dart';
import 'battlenet_api_service.dart';
import 'character_cache_service.dart';

/// A display-ready achievement merged with player progress.
class AchievementDisplay {
  final Achievement achievement;
  final bool isCompleted;
  final int? completedTimestamp;
  final Map<int, bool> criteriaProgress;
  final int completedCriteria;
  final int totalCriteria;

  const AchievementDisplay({
    required this.achievement,
    required this.isCompleted,
    this.completedTimestamp,
    this.criteriaProgress = const {},
    this.completedCriteria = 0,
    this.totalCriteria = 0,
  });

  String? get formattedDate {
    if (completedTimestamp == null) return null;
    final date = DateTime.fromMillisecondsSinceEpoch(completedTimestamp!);
    return '${date.month}/${date.day}/${date.year}';
  }
}

/// Result of merging achievement definitions with progress.
class MergedAchievements {
  final List<AchievementDisplay> completed;
  final List<AchievementDisplay> incomplete;

  const MergedAchievements({
    required this.completed,
    required this.incomplete,
  });

  List<AchievementDisplay> get all => [...incomplete, ...completed];
}

/// A search result with category context for navigation.
class AchievementSearchResult {
  final Achievement achievement;
  final int categoryId;
  final String categoryPath;

  const AchievementSearchResult({
    required this.achievement,
    required this.categoryId,
    required this.categoryPath,
  });
}

/// Manages achievement state: categories, definitions, and player progress.
class AchievementProvider extends ChangeNotifier {
  final BattleNetApiService _apiService;
  final CharacterCacheService _cacheService;

  List<AchievementCategoryRef> _topCategories = [];
  AccountAchievementProgress? _progress;
  bool _isCategoriesLoading = false;
  bool _isProgressLoading = false;
  String? _error;

  // Per-category state
  final Map<int, AchievementCategory> _categoryDetails = {};
  final Map<int, List<Achievement>> _categoryAchievements = {};
  final Map<int, bool> _categoryLoading = {};
  List<AchievementDisplay> _recentlyCompleted = [];
  bool _isRecentLoading = false;

  // Enrichment state (from Wago DB2 via worker)
  final Map<int, AchievementEnrichment> _enrichments = {};
  final Map<int, bool> _enrichmentLoading = {};

  AchievementProvider(this._apiService, this._cacheService);

  List<AchievementCategoryRef> get topCategories => _topCategories;
  AccountAchievementProgress? get progress => _progress;
  bool get isCategoriesLoading => _isCategoriesLoading;
  bool get isProgressLoading => _isProgressLoading;
  String? get error => _error;
  List<AchievementDisplay> get recentlyCompleted => _recentlyCompleted;
  bool get isRecentLoading => _isRecentLoading;

  bool isCategoryLoading(int categoryId) => _categoryLoading[categoryId] ?? false;
  bool isEnrichmentLoading(int achievementId) => _enrichmentLoading[achievementId] ?? false;
  AchievementEnrichment? getEnrichment(int achievementId) => _enrichments[achievementId];

  AchievementCategory? getCategoryDetails(int categoryId) =>
      _categoryDetails[categoryId];

  List<Achievement>? getCategoryAchievements(int categoryId) =>
      _categoryAchievements[categoryId];

  // In-game category display order. Categories not in this list appear at the end.
  static const _categoryOrder = [
    'Characters',
    'Quests',
    'Exploration',
    'Housing',
    'Delves',
    'Player vs. Player',
    'Dungeons & Raids',
    'Professions',
    'Reputation',
    'World Events',
    'Pet Battles',
    'Collections',
    'Expansion Features',
    'Feats of Strength',
    'Legacy',
  ];

  // Expansion/zone subcategory display order (WoW expansion timeline).
  static const _subcategoryOrder = [
    'Eastern Kingdoms',
    'Kalimdor',
    'Outland',
    'Northrend',
    'Cataclysm',
    'Pandaria',
    'Draenor',
    'Legion',
    'Battle for Azeroth',
    'Shadowlands',
    'Dragonflight',
    'Dragon Isles',
    'War Within',
    'Midnight',
  ];

  /// Sorts a list of category refs using a priority list, unknowns at end.
  static List<AchievementCategoryRef> _sortRefs(
    List<AchievementCategoryRef> refs,
    List<String> order,
  ) {
    final sorted = List<AchievementCategoryRef>.from(refs);
    sorted.sort((a, b) {
      final aIndex = order.indexOf(a.name);
      final bIndex = order.indexOf(b.name);
      final aOrder = aIndex == -1 ? order.length : aIndex;
      final bOrder = bIndex == -1 ? order.length : bIndex;
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);
      return a.name.compareTo(b.name);
    });
    return sorted;
  }

  /// Clears player-specific achievement data (progress, recent completions).
  /// Called on region switch — static data (categories, definitions) is kept.
  void clearProgress() {
    _progress = null;
    _recentlyCompleted = [];
    notifyListeners();
  }

  /// Loads the top-level achievement categories.
  Future<void> loadCategories() async {
    _isCategoriesLoading = true;
    _error = null;
    notifyListeners();

    try {
      final categories = await _apiService.getAchievementCategoriesIndex();
      if (categories.isNotEmpty) {
        _topCategories = _sortRefs(categories, _categoryOrder);
      } else if (_topCategories.isEmpty) {
        _error = 'Failed to load categories';
      }
    } catch (e) {
      if (_topCategories.isEmpty) {
        _error = 'No connection — check your network';
      }
    }

    _isCategoriesLoading = false;
    notifyListeners();
  }

  /// Loads account-wide achievement progress using any character.
  Future<void> loadProgress(String realmSlug, String characterName) async {
    _isProgressLoading = true;
    notifyListeners();

    try {
      final newProgress =
          await _apiService.getCharacterAchievements(realmSlug, characterName);
      if (newProgress != null) {
        _progress = newProgress;
      }
    } catch (_) {
      // Keep existing progress — offline mode
    }

    _isProgressLoading = false;
    notifyListeners();
  }

  /// Loads a specific category's details and achievement definitions.
  /// Uses cache first, fetches from API if missing/stale.
  Future<void> loadCategoryDetails(int categoryId) async {
    _categoryLoading[categoryId] = true;
    notifyListeners();

    try {
      var category = _cacheService.getCachedAchievementCategory(categoryId);
      if (category == null) {
        category = await _apiService.getAchievementCategory(categoryId);
        if (category != null) {
          _cacheService.cacheAchievementCategory(category);
        }
      }

      if (category != null) {
        if (category.subcategories.isNotEmpty) {
          category = AchievementCategory(
            id: category.id,
            name: category.name,
            subcategories: _sortRefs(category.subcategories, _subcategoryOrder),
            achievementRefs: category.achievementRefs,
          );
        }
        _categoryDetails[categoryId] = category;
      }

      if (category != null && category.achievementRefs.isNotEmpty) {
        var achievements = _cacheService.getCachedAchievements(categoryId);
        if (achievements == null) {
          final ids = category.achievementRefs.map((r) => r.id).toList();
          achievements = await _apiService.getAchievements(ids);
          achievements = await _apiService.enrichAchievementIcons(achievements);

          if (achievements.isNotEmpty) {
            _cacheService.cacheAchievements(categoryId, achievements);
          }
        }
        _categoryAchievements[categoryId] = achievements;
      }
    } catch (_) {
      // Keep any existing cached data — offline mode
    }

    _categoryLoading[categoryId] = false;
    notifyListeners();
  }

  /// Merges achievement definitions with player progress for display.
  /// Static so it can be tested without mocking the provider.
  static MergedAchievements mergeWithProgress(
    List<Achievement> achievements,
    AccountAchievementProgress? progress,
  ) {
    final completed = <AchievementDisplay>[];
    final incomplete = <AchievementDisplay>[];

    for (final ach in achievements) {
      final entry = progress?.achievements[ach.id];
      final isCompleted = entry?.isCompleted ?? false;

      int completedCriteria = 0;
      int totalCriteria = 0;

      if (ach.criteria != null && ach.criteria!.childCriteria.isNotEmpty) {
        totalCriteria = ach.criteria!.childCriteria.length;
        for (final child in ach.criteria!.childCriteria) {
          if (entry?.criteriaProgress[child.id] == true) {
            completedCriteria++;
          }
        }
      }

      final display = AchievementDisplay(
        achievement: ach,
        isCompleted: isCompleted,
        completedTimestamp: entry?.completedTimestamp,
        criteriaProgress: entry?.criteriaProgress ?? {},
        completedCriteria: completedCriteria,
        totalCriteria: totalCriteria,
      );

      if (isCompleted) {
        completed.add(display);
      } else {
        incomplete.add(display);
      }
    }

    // Preserve Blizzard's category order (matches in-game achievement panel)
    return MergedAchievements(completed: completed, incomplete: incomplete);
  }

  /// Gets merged achievements for display in a category.
  MergedAchievements? getMergedAchievements(int categoryId) {
    final achievements = _categoryAchievements[categoryId];
    if (achievements == null) return null;
    return mergeWithProgress(achievements, _progress);
  }

  /// Refresh progress data (pull-to-refresh).
  Future<void> refreshProgress(String realmSlug, String characterName) async {
    await loadProgress(realmSlug, characterName);
  }

  /// Fetches a single achievement by ID. Checks cache first.
  Future<Achievement?> fetchAchievement(int achievementId) async {
    // Check if we already have it cached
    for (final achs in _categoryAchievements.values) {
      for (final a in achs) {
        if (a.id == achievementId) return a;
      }
    }
    // Fetch from API
    return _apiService.getAchievement(achievementId);
  }

  /// Fetches Wago DB2 enrichment for an achievement (criteria types, quest lines).
  /// Returns cached data immediately if available; fetches from worker otherwise.
  Future<AchievementEnrichment?> fetchEnrichment(int achievementId) async {
    if (_enrichments.containsKey(achievementId)) return _enrichments[achievementId];
    if (_enrichmentLoading[achievementId] == true) return null;

    _enrichmentLoading[achievementId] = true;
    notifyListeners();

    try {
      final url = '${AppConfig.authProxyUrl}/achievement/$achievementId/enriched';
      debugPrint('[Enrichment] Fetching $url');
      final response = await http.get(Uri.parse(url));
      debugPrint('[Enrichment] Status: ${response.statusCode}, body length: ${response.body.length}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final enrichment = AchievementEnrichment.fromJson(data);
        _enrichments[achievementId] = enrichment;
        debugPrint('[Enrichment] Loaded ${enrichment.criteria.length} criteria for achievement $achievementId');
      }
    } catch (e) {
      debugPrint('[Enrichment] Error: $e');
      // Non-critical — detail screen shows base data without enrichment
    }

    _enrichmentLoading[achievementId] = false;
    notifyListeners();
    return _enrichments[achievementId];
  }

  /// Finds the category ID and name for a cached achievement.
  /// Returns null if the achievement isn't in any cached category.
  ({int categoryId, String categoryName})? findAchievementCategory(int achievementId) {
    for (final entry in _categoryAchievements.entries) {
      for (final ach in entry.value) {
        if (ach.id == achievementId) {
          final detail = _categoryDetails[entry.key];
          return (categoryId: entry.key, categoryName: detail?.name ?? 'Unknown');
        }
      }
    }
    return null;
  }

  /// Returns completion counts for a category (completed / total).
  /// Only works for categories whose achievements have been cached.
  ({int completed, int total})? getCategoryCounts(int categoryId) {
    final achievements = _categoryAchievements[categoryId];
    if (achievements == null || achievements.isEmpty) return null;

    int completed = 0;
    for (final ach in achievements) {
      final entry = _progress?.achievements[ach.id];
      if (entry?.isCompleted ?? false) {
        completed++;
      }
    }
    return (completed: completed, total: achievements.length);
  }

  /// Searches cached achievement definitions by name.
  List<AchievementSearchResult> searchAchievements(String query) {
    if (query.length < 2) return [];
    final lowerQuery = query.toLowerCase();
    final results = <AchievementSearchResult>[];

    for (final entry in _categoryAchievements.entries) {
      final categoryId = entry.key;
      final categoryDetail = _categoryDetails[categoryId];
      final categoryName = categoryDetail?.name ?? 'Unknown';
      final categoryPath = categoryName;

      for (final ach in entry.value) {
        if (ach.name.toLowerCase().contains(lowerQuery)) {
          results.add(AchievementSearchResult(
            achievement: ach,
            categoryId: categoryId,
            categoryPath: categoryPath,
          ));
        }
      }
    }
    return results;
  }

  /// Returns the number of cached achievement definitions available for search.
  int get searchableCacheSize {
    int count = 0;
    for (final achs in _categoryAchievements.values) {
      count += achs.length;
    }
    return count;
  }

  /// Loads the most recently completed achievements.
  Future<void> loadRecentlyCompleted() async {
    if (_progress == null) return;
    _isRecentLoading = true;
    notifyListeners();

    final entries = _progress!.achievements.values
        .where((e) => e.isCompleted && e.completedTimestamp != null)
        .toList()
      ..sort((a, b) => (b.completedTimestamp ?? 0).compareTo(a.completedTimestamp ?? 0));

    final topEntries = entries.take(5).toList();
    final results = <AchievementDisplay>[];

    for (final entry in topEntries) {
      // Check if we have the definition cached already
      Achievement? ach;
      for (final achs in _categoryAchievements.values) {
        for (final a in achs) {
          if (a.id == entry.achievementId) {
            ach = a;
            break;
          }
        }
        if (ach != null) break;
      }

      // Fetch from API if not cached
      ach ??= await _apiService.getAchievement(entry.achievementId);

      if (ach != null) {
        results.add(AchievementDisplay(
          achievement: ach,
          isCompleted: true,
          completedTimestamp: entry.completedTimestamp,
          criteriaProgress: entry.criteriaProgress,
        ));
      }
    }

    _recentlyCompleted = results;
    _isRecentLoading = false;
    notifyListeners();
  }

  /// Force-refreshes a category by clearing its cache and reloading.
  /// Force-refreshes a category by clearing its persistent cache and reloading.
  /// If the reload fails, in-memory data is re-persisted so offline mode
  /// still works on next app launch.
  Future<void> forceRefreshCategory(int categoryId) async {
    // Snapshot existing in-memory data before clearing caches
    final oldDetails = _categoryDetails[categoryId];
    final oldAchievements = _categoryAchievements[categoryId];

    // Clear persistent cache — forces loadCategoryDetails to hit the API
    _cacheService.clearAchievementCategory(categoryId);
    _cacheService.clearAchievements(categoryId);

    await loadCategoryDetails(categoryId);

    // If the reload didn't produce new data (network failure), re-persist
    // the old in-memory data so it survives the next app launch
    if (_categoryDetails[categoryId] == oldDetails && oldDetails != null) {
      _cacheService.cacheAchievementCategory(oldDetails);
    }
    if (_categoryAchievements[categoryId] == oldAchievements && oldAchievements != null) {
      _cacheService.cacheAchievements(categoryId, oldAchievements);
    }
  }

  /// Force-refreshes categories and progress (for top-level screen).
  /// Existing in-memory data is preserved if network calls fail.
  Future<void> forceRefreshAll(String realmSlug, String characterName) async {
    // Don't clear in-memory data — loadCategories and loadProgress will
    // overwrite on success and keep existing data on failure.
    await loadCategories();
    await loadProgress(realmSlug, characterName);
  }
}
