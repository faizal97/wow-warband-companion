/// Battle.net API regions with their endpoint configuration.
enum BattleNetRegion {
  us(
    key: 'us',
    displayName: 'Americas',
    apiBaseUrl: 'https://us.api.blizzard.com',
    oauthBaseUrl: 'https://oauth.battle.net',
    namespacePrefix: 'us',
    locale: 'en_US',
  ),
  eu(
    key: 'eu',
    displayName: 'Europe',
    apiBaseUrl: 'https://eu.api.blizzard.com',
    oauthBaseUrl: 'https://oauth.battle.net',
    namespacePrefix: 'eu',
    locale: 'en_GB',
  ),
  kr(
    key: 'kr',
    displayName: 'Korea',
    apiBaseUrl: 'https://kr.api.blizzard.com',
    oauthBaseUrl: 'https://oauth.battle.net',
    namespacePrefix: 'kr',
    locale: 'ko_KR',
  ),
  tw(
    key: 'tw',
    displayName: 'Taiwan',
    apiBaseUrl: 'https://tw.api.blizzard.com',
    oauthBaseUrl: 'https://oauth.battle.net',
    namespacePrefix: 'tw',
    locale: 'zh_TW',
  ),
  cn(
    key: 'cn',
    displayName: 'China',
    apiBaseUrl: 'https://gateway.battlenet.com.cn',
    oauthBaseUrl: 'https://oauth.battlenet.com.cn',
    namespacePrefix: 'cn',
    locale: 'zh_CN',
  );

  final String key;
  final String displayName;
  final String apiBaseUrl;
  final String oauthBaseUrl;
  final String namespacePrefix;
  final String locale;

  const BattleNetRegion({
    required this.key,
    required this.displayName,
    required this.apiBaseUrl,
    required this.oauthBaseUrl,
    required this.namespacePrefix,
    required this.locale,
  });

  String get profileNamespace => 'profile-$namespacePrefix';
  String get staticNamespace => 'static-$namespacePrefix';
  String get dynamicNamespace => 'dynamic-$namespacePrefix';

  static BattleNetRegion? fromKey(String key) {
    for (final region in values) {
      if (region.key == key) return region;
    }
    return null;
  }
}
