import 'package:flutter/foundation.dart';
import '../models/auction_item.dart';

/// Manages auction house item search, watchlist, and price fetching.
///
/// - Search: delegates to Blizzard Item Search API via [searchFunction]
/// - Prices: fetches from Cloudflare Worker via [fetchPricesFunction]
/// - Watchlist: persisted via [saveWatchlistFunction] / [loadWatchlistFunction]
/// - Rate limit: 2 min hard floor on price refreshes
/// - Staleness: 20 min, bypassed by pull-to-refresh
class AuctionHouseProvider extends ChangeNotifier {
  final Future<List<AuctionItem>> Function(String query) searchFunction;
  final Future<({Map<int, ({int minPrice, int totalQuantity})> prices, DateTime? lastUpdated})> Function(
      List<int> itemIds) fetchPricesFunction;
  final Future<List<AuctionItem>> Function() loadWatchlistFunction;
  final Future<void> Function(List<AuctionItem>) saveWatchlistFunction;
  final Future<String?> Function(int mediaId)? enrichIconFunction;

  final Duration rateLimitDuration;
  final Duration stalenessDuration;

  List<AuctionItem> _watchlist = [];
  List<AuctionItem> _searchResults = [];
  bool _isSearching = false;
  bool _isLoadingPrices = false;
  String? _errorMessage;
  DateTime? _lastPriceFetch;

  /// When Blizzard last generated the auction data snapshot.
  DateTime? _dataLastUpdated;

  /// Cache of item ID → icon URL to avoid re-fetching across searches.
  final Map<int, String> _iconCache = {};

  AuctionHouseProvider({
    required this.searchFunction,
    required this.fetchPricesFunction,
    required this.loadWatchlistFunction,
    required this.saveWatchlistFunction,
    this.enrichIconFunction,
    this.rateLimitDuration = const Duration(minutes: 2),
    this.stalenessDuration = const Duration(minutes: 20),
  });

  List<AuctionItem> get watchlist => List.unmodifiable(_watchlist);
  List<AuctionItem> get searchResults => List.unmodifiable(_searchResults);
  bool get isSearching => _isSearching;
  bool get isLoadingPrices => _isLoadingPrices;
  String? get errorMessage => _errorMessage;
  DateTime? get dataLastUpdated => _dataLastUpdated;

  bool isInWatchlist(int itemId) => _watchlist.any((i) => i.id == itemId);

  /// Load watchlist from persistence, then fetch prices if stale.
  Future<void> init() async {
    _watchlist = await loadWatchlistFunction();
    // Populate icon cache from persisted watchlist
    for (final item in _watchlist) {
      if (item.iconUrl != null) {
        _iconCache[item.id] = item.iconUrl!;
      }
    }
    notifyListeners();
    await fetchPrices();
  }

  /// Search items by name. Debouncing is handled by the UI layer.
  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      clearSearch();
      return;
    }

    _isSearching = true;
    notifyListeners();

    try {
      _searchResults = await searchFunction(query);

      // Apply cached icons immediately
      for (var i = 0; i < _searchResults.length; i++) {
        final cached = _iconCache[_searchResults[i].id];
        if (cached != null) {
          _searchResults[i] = _searchResults[i].copyWith(iconUrl: cached);
        }
      }
    } catch (_) {
      _searchResults = [];
    } finally {
      _isSearching = false;
      notifyListeners();
    }

    // Enrich icons in background for results that need them
    _enrichSearchResultIcons();
  }

  /// Fetches icons for search results that have a mediaId but no iconUrl.
  void _enrichSearchResultIcons() {
    if (enrichIconFunction == null) return;

    for (var i = 0; i < _searchResults.length; i++) {
      final item = _searchResults[i];
      if (item.iconUrl != null || item.mediaId == null) continue;
      if (_iconCache.containsKey(item.id)) continue;

      final itemId = item.id;
      final mediaId = item.mediaId!;

      enrichIconFunction!(mediaId).then((url) {
        if (url == null) return;
        _iconCache[itemId] = url;

        // Update in search results if still present
        final idx = _searchResults.indexWhere((i) => i.id == itemId);
        if (idx >= 0) {
          _searchResults[idx] = _searchResults[idx].copyWith(iconUrl: url);
          notifyListeners();
        }
      });
    }
  }

  void clearSearch() {
    _searchResults = [];
    notifyListeners();
  }

  /// Add item to watchlist, persist, and fetch its price.
  Future<void> addToWatchlist(AuctionItem item) async {
    if (isInWatchlist(item.id)) return;

    // Apply cached icon if available
    final cachedIcon = _iconCache[item.id];
    final itemToAdd = cachedIcon != null && item.iconUrl == null
        ? item.copyWith(iconUrl: cachedIcon)
        : item;

    _watchlist.add(itemToAdd);
    notifyListeners();
    await saveWatchlistFunction(_watchlist);

    // Background icon fetch if still needed
    if (itemToAdd.mediaId != null && itemToAdd.iconUrl == null && enrichIconFunction != null) {
      enrichIconFunction!(itemToAdd.mediaId!).then((url) {
        if (url != null) {
          _iconCache[itemToAdd.id] = url;
          final idx = _watchlist.indexWhere((i) => i.id == itemToAdd.id);
          if (idx >= 0) {
            _watchlist[idx] = _watchlist[idx].copyWith(iconUrl: url);
            saveWatchlistFunction(_watchlist);
            notifyListeners();
          }
        }
      });
    }

    await _fetchPricesForItems([itemToAdd.id]);
  }

  /// Remove item from watchlist and persist.
  Future<void> removeFromWatchlist(int itemId) async {
    _watchlist.removeWhere((i) => i.id == itemId);
    notifyListeners();
    await saveWatchlistFunction(_watchlist);
  }

  /// Fetch prices respecting staleness window. Called on screen open.
  Future<void> fetchPrices() async {
    if (_watchlist.isEmpty) return;

    if (_lastPriceFetch != null) {
      final elapsed = DateTime.now().difference(_lastPriceFetch!);
      if (elapsed < stalenessDuration) return;
    }

    await _doFetchPrices();
  }

  /// Refresh prices bypassing staleness but respecting rate limit.
  /// Called on pull-to-refresh.
  Future<void> refreshPrices() async {
    if (_watchlist.isEmpty) return;

    if (_lastPriceFetch != null) {
      final elapsed = DateTime.now().difference(_lastPriceFetch!);
      if (elapsed < rateLimitDuration) return;
    }

    await _doFetchPrices();
  }

  Future<void> _doFetchPrices() async {
    if (_watchlist.isEmpty) return;

    _isLoadingPrices = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final ids = _watchlist.map((i) => i.id).toList();
      final result = await fetchPricesFunction(ids);
      _applyPrices(result.prices);
      if (result.lastUpdated != null) {
        _dataLastUpdated = result.lastUpdated;
      }
      _lastPriceFetch = DateTime.now();
    } catch (_) {
      _errorMessage = 'Failed to fetch prices';
    } finally {
      _isLoadingPrices = false;
      notifyListeners();
    }
  }

  /// Fetch prices for specific items only (used when adding to watchlist).
  Future<void> _fetchPricesForItems(List<int> itemIds) async {
    try {
      final result = await fetchPricesFunction(itemIds);
      _applyPrices(result.prices);
      if (result.lastUpdated != null) {
        _dataLastUpdated = result.lastUpdated;
      }
      _lastPriceFetch = DateTime.now();
      notifyListeners();
    } catch (_) {
      // Silent failure for single-item price fetch
    }
  }

  void _applyPrices(Map<int, ({int minPrice, int totalQuantity})> prices) {
    for (var i = 0; i < _watchlist.length; i++) {
      final priceData = prices[_watchlist[i].id];
      if (priceData != null) {
        _watchlist[i] = _watchlist[i].copyWith(
          price: priceData.minPrice,
          totalQuantity: priceData.totalQuantity,
        );
      }
    }
  }

  /// Clear all state (e.g., on region switch or logout).
  void clear() {
    _watchlist = [];
    _searchResults = [];
    _isSearching = false;
    _isLoadingPrices = false;
    _errorMessage = null;
    _lastPriceFetch = null;
    _dataLastUpdated = null;
    notifyListeners();
  }
}
