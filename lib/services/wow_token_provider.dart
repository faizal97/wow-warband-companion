import 'package:flutter/foundation.dart';
import '../models/wow_token.dart';

/// Provides WoW Token price data with dual-layer caching.
///
/// - Rate limit (default 2 min): Hard floor, cannot be bypassed.
/// - Staleness (default 20 min): Bypassed by pull-to-refresh.
class WowTokenProvider extends ChangeNotifier {
  final Future<WowToken?> Function() _fetchFunction;
  final Duration rateLimitDuration;
  final Duration stalenessDuration;

  WowToken? _token;
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastFetchTime;

  WowTokenProvider({
    required Future<WowToken?> Function() fetchFunction,
    this.rateLimitDuration = const Duration(minutes: 2),
    this.stalenessDuration = const Duration(minutes: 20),
  }) : _fetchFunction = fetchFunction;

  WowToken? get token => _token;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Fetches token price, respecting both rate limit and staleness cache.
  /// Called on screen load.
  Future<void> fetchTokenPrice() async {
    // If we have cached data within staleness window, serve it
    if (_token != null && _lastFetchTime != null) {
      final elapsed = DateTime.now().difference(_lastFetchTime!);
      if (elapsed < stalenessDuration) return;
    }

    await _doFetch();
  }

  /// Refreshes token price, bypassing staleness but respecting rate limit.
  /// Called on pull-to-refresh.
  Future<void> refreshTokenPrice() async {
    if (_lastFetchTime != null) {
      final elapsed = DateTime.now().difference(_lastFetchTime!);
      if (elapsed < rateLimitDuration) return;
    }

    await _doFetch();
  }

  /// Clears cached token data (e.g., on region switch or logout).
  void clearToken() {
    _token = null;
    _errorMessage = null;
    _lastFetchTime = null;
    notifyListeners();
  }

  Future<void> _doFetch() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _fetchFunction();
      if (result != null) {
        _token = result;
        _lastFetchTime = DateTime.now();
      } else {
        _errorMessage = 'Price unavailable';
      }
    } catch (e) {
      _errorMessage = 'Price unavailable';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
