import 'package:flutter_test/flutter_test.dart';
import 'package:wow_warband_companion/models/battlenet_region.dart';

void main() {
  group('BattleNetRegion', () {
    test('US region has correct API base URL', () {
      expect(BattleNetRegion.us.apiBaseUrl, 'https://us.api.blizzard.com');
    });

    test('EU region has correct namespace prefix', () {
      expect(BattleNetRegion.eu.namespacePrefix, 'eu');
    });

    test('CN region uses different OAuth base', () {
      expect(BattleNetRegion.cn.oauthBaseUrl, 'https://oauth.battlenet.com.cn');
    });

    test('CN region uses different API domain', () {
      expect(BattleNetRegion.cn.apiBaseUrl, 'https://gateway.battlenet.com.cn');
    });

    test('profileNamespace returns correct format', () {
      expect(BattleNetRegion.us.profileNamespace, 'profile-us');
      expect(BattleNetRegion.eu.profileNamespace, 'profile-eu');
    });

    test('staticNamespace returns correct format', () {
      expect(BattleNetRegion.kr.staticNamespace, 'static-kr');
    });

    test('dynamicNamespace returns correct format', () {
      expect(BattleNetRegion.tw.dynamicNamespace, 'dynamic-tw');
    });

    test('fromKey returns correct region', () {
      expect(BattleNetRegion.fromKey('eu'), BattleNetRegion.eu);
      expect(BattleNetRegion.fromKey('cn'), BattleNetRegion.cn);
    });

    test('fromKey returns null for invalid key', () {
      expect(BattleNetRegion.fromKey('xx'), isNull);
    });

    test('all regions are present', () {
      expect(BattleNetRegion.values.length, 5);
    });
  });
}
