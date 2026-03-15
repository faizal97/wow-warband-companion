import 'package:flutter_test/flutter_test.dart';
import 'package:wow_warband_companion/models/wow_token.dart';
import 'package:wow_warband_companion/services/wow_token_provider.dart';

void main() {
  group('WowTokenProvider', () {
    late int apiCallCount;
    late WowToken? mockResponse;

    WowTokenProvider createProvider() {
      apiCallCount = 0;
      mockResponse = const WowToken(
          price: 2345000000, lastUpdatedTimestamp: 1710500000000);
      return WowTokenProvider(
        fetchFunction: () async {
          apiCallCount++;
          return mockResponse;
        },
      );
    }

    test('initial state has no token and is not loading', () {
      final provider = createProvider();
      expect(provider.token, isNull);
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('fetchTokenPrice calls API on first load', () async {
      final provider = createProvider();
      await provider.fetchTokenPrice();
      expect(provider.token, isNotNull);
      expect(provider.token!.price, 2345000000);
      expect(apiCallCount, 1);
    });

    test('fetchTokenPrice serves cache within staleness window', () async {
      final provider = createProvider();
      await provider.fetchTokenPrice();
      await provider.fetchTokenPrice();
      expect(apiCallCount, 1); // second call should be cached
    });

    test('refreshTokenPrice respects rate limit', () async {
      final provider = createProvider();
      await provider.fetchTokenPrice();
      await provider.refreshTokenPrice();
      expect(apiCallCount, 1); // rate limit blocks second call
    });

    test('refreshTokenPrice fetches after rate limit expires', () async {
      final provider = createProvider();
      // Use a provider with a very short rate limit for testing
      final fastProvider = WowTokenProvider(
        fetchFunction: () async {
          apiCallCount++;
          return mockResponse;
        },
        rateLimitDuration: Duration.zero,
        stalenessDuration: const Duration(minutes: 20),
      );
      await fastProvider.fetchTokenPrice();
      await fastProvider.refreshTokenPrice();
      expect(apiCallCount, 2);
    });

    test('sets error message on API failure', () async {
      final provider = WowTokenProvider(
        fetchFunction: () async => null,
      );
      await provider.fetchTokenPrice();
      expect(provider.token, isNull);
      expect(provider.errorMessage, isNotNull);
    });

    test('clearToken resets state', () async {
      final provider = createProvider();
      await provider.fetchTokenPrice();
      provider.clearToken();
      expect(provider.token, isNull);
      expect(provider.errorMessage, isNull);
    });
  });
}
