import 'package:flutter_test/flutter_test.dart';
import 'package:wow_warband_companion/models/wow_token.dart';

void main() {
  group('WowToken', () {
    test('fromJson parses price and timestamp', () {
      final json = {
        'last_updated_timestamp': 1710500000000,
        'price': 2345000000,
      };
      final token = WowToken.fromJson(json);
      expect(token.price, 2345000000);
      expect(token.lastUpdatedTimestamp, 1710500000000);
    });

    test('priceInGold converts copper to gold', () {
      final token = WowToken(price: 2345000000, lastUpdatedTimestamp: 0);
      expect(token.priceInGold, 234500);
    });

    test('formattedPrice formats with comma separators', () {
      final token = WowToken(price: 2345000000, lastUpdatedTimestamp: 0);
      expect(token.formattedPrice, '234,500');
    });

    test('formattedPrice handles small prices', () {
      final token = WowToken(price: 50000, lastUpdatedTimestamp: 0);
      expect(token.formattedPrice, '5');
    });

    test('formattedPrice handles zero', () {
      final token = WowToken(price: 0, lastUpdatedTimestamp: 0);
      expect(token.formattedPrice, '0');
    });

    test('lastUpdated returns correct DateTime', () {
      final token = WowToken(price: 0, lastUpdatedTimestamp: 1710500000000);
      expect(
        token.lastUpdated,
        DateTime.fromMillisecondsSinceEpoch(1710500000000),
      );
    });
  });
}
