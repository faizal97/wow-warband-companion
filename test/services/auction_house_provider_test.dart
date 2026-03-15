import 'package:flutter_test/flutter_test.dart';
import 'package:wow_warband_companion/models/auction_item.dart';
import 'package:wow_warband_companion/services/auction_house_provider.dart';

void main() {
  group('AuctionHouseProvider', () {
    late AuctionHouseProvider provider;
    late int priceCallCount;
    late Map<int, ({int minPrice, int totalQuantity})> mockPrices;

    setUp(() {
      priceCallCount = 0;
      mockPrices = {
        100: (minPrice: 85000, totalQuantity: 1247),
        200: (minPrice: 12000, totalQuantity: 5000),
      };

      provider = AuctionHouseProvider(
        searchFunction: (query) async => [
          const AuctionItem(id: 100, name: 'Mycbloom', subclass: 'Herb'),
          const AuctionItem(id: 200, name: 'Mycbloom Petal', subclass: 'Herb'),
        ],
        fetchPricesFunction: (itemIds) async {
          priceCallCount++;
          return (
            prices: {
              for (final id in itemIds)
                if (mockPrices.containsKey(id))
                  id: (
                    minPrice: mockPrices[id]!.minPrice,
                    totalQuantity: mockPrices[id]!.totalQuantity,
                  ),
            },
            lastUpdated: DateTime.now(),
          );
        },
        loadWatchlistFunction: () async => [],
        saveWatchlistFunction: (_) async {},
      );
    });

    test('initial state is empty', () {
      expect(provider.watchlist, isEmpty);
      expect(provider.searchResults, isEmpty);
      expect(provider.isSearching, isFalse);
      expect(provider.isLoadingPrices, isFalse);
    });

    test('search returns results', () async {
      await provider.search('Myc');
      expect(provider.searchResults.length, 2);
      expect(provider.searchResults.first.name, 'Mycbloom');
    });

    test('addToWatchlist adds item and fetches price', () async {
      const item = AuctionItem(id: 100, name: 'Mycbloom', subclass: 'Herb');
      await provider.addToWatchlist(item);
      expect(provider.watchlist.length, 1);
      expect(provider.watchlist.first.price, 85000);
      expect(provider.watchlist.first.totalQuantity, 1247);
    });

    test('removeFromWatchlist removes item', () async {
      const item = AuctionItem(id: 100, name: 'Mycbloom', subclass: 'Herb');
      await provider.addToWatchlist(item);
      await provider.removeFromWatchlist(100);
      expect(provider.watchlist, isEmpty);
    });

    test('isInWatchlist returns correct state', () async {
      const item = AuctionItem(id: 100, name: 'Mycbloom', subclass: 'Herb');
      expect(provider.isInWatchlist(100), isFalse);
      await provider.addToWatchlist(item);
      expect(provider.isInWatchlist(100), isTrue);
    });

    test('refreshPrices respects rate limit', () async {
      const item = AuctionItem(id: 100, name: 'Mycbloom', subclass: 'Herb');
      await provider.addToWatchlist(item);
      await provider.refreshPrices();
      expect(priceCallCount, 1);
    });

    test('clearSearch resets search state', () async {
      await provider.search('Myc');
      provider.clearSearch();
      expect(provider.searchResults, isEmpty);
    });

    test('clear resets all state', () async {
      const item = AuctionItem(id: 100, name: 'Mycbloom', subclass: 'Herb');
      await provider.addToWatchlist(item);
      provider.clear();
      expect(provider.watchlist, isEmpty);
      expect(provider.searchResults, isEmpty);
    });
  });
}
