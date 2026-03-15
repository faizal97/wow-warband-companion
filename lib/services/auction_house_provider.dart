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
  final Future<Map<int, ({int minPrice, int totalQuantity})>> Function(
      List<int> itemIds) fetchPricesFunction;
  final Future<List<AuctionItem>> Function() loadWatchlistFunction;
  final Future<void> Function(List<AuctionItem>) saveWatchlistFunction;

  final Duration rateLimitDuration;
  final Duration stalenessDuration;

  List<AuctionItem> _watchlist = [];
  List<AuctionItem> _searchResults = [];
  bool _isSearching = false;
  bool _isLoadingPrices = false;
  String? _errorMessage;
  DateTime? _lastPriceFetch;

  AuctionHouseProvider({
    required this.searchFunction,
    required this.fetchPricesFunction,
    required this.loadWatchlistFunction,
    required this.saveWatchlistFunction,
    this.rateLimitDuration = const Duration(minutes: 2),
    this.stalenessDuration = const Duration(minutes: 20),
  });

  List<AuctionItem> get watchlist => List.unmodifiable(_watchlist);
  List<AuctionItem> get searchResults => List.unmodifiable(_searchResults);
  bool get isSearching => _isSearching;
  bool get isLoadingPrices => _isLoadingPrices;
  String? get errorMessage => _errorMessage;

  bool isInWatchlist(int itemId) => _watchlist.any((i) => i.id == itemId);

  /// Load watchlist from persistence, then fetch prices if stale.
  Future<void> init() async {
    _watchlist = await loadWatchlistFunction();
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
    } catch (_) {
      _searchResults = [];
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    _searchResults = [];
    notifyListeners();
  }

  /// Add item to watchlist, persist, and fetch its price.
  Future<void> addToWatchlist(AuctionItem item) async {
    if (isInWatchlist(item.id)) return;
    _watchlist.add(item);
    notifyListeners();
    await saveWatchlistFunction(_watchlist);
    await _fetchPricesForItems([item.id]);
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
      final prices = await fetchPricesFunction(ids);
      _applyPrices(prices);
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
      final prices = await fetchPricesFunction(itemIds);
      _applyPrices(prices);
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
    notifyListeners();
  }
}
