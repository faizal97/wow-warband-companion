import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'models/auction_item.dart';
import 'models/battlenet_region.dart';
import 'services/auction_house_provider.dart';
import 'services/battlenet_auth_service.dart';
import 'services/battlenet_api_service.dart';
import 'services/character_cache_service.dart';
import 'services/character_provider.dart';
import 'services/character_detail_provider.dart';
import 'services/region_service.dart';
import 'screens/login_screen.dart';
import 'screens/main_menu_screen.dart';
import 'screens/region_picker_screen.dart';
import 'services/achievement_provider.dart';
import 'services/mount_provider.dart';
import 'services/news_provider.dart';
import 'services/wow_token_provider.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final prefs = await SharedPreferences.getInstance();
  final regionService = RegionService(prefs);
  final authService = BattleNetAuthService(prefs);
  final apiService = BattleNetApiService(authService, regionService.activeRegion);
  final cacheService = CharacterCacheService(prefs);

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: authService),
        Provider.value(value: regionService),
        Provider.value(value: apiService),
        ChangeNotifierProvider(
          create: (_) =>
              CharacterProvider(apiService, authService, cacheService),
        ),
        ChangeNotifierProvider(
          create: (_) => CharacterDetailProvider(apiService, cacheService),
        ),
        ChangeNotifierProvider(
          create: (_) => AchievementProvider(apiService, cacheService),
        ),
        ChangeNotifierProvider(
          create: (_) => MountProvider(apiService, prefs),
        ),
        ChangeNotifierProvider(
          create: (context) => WowTokenProvider(
            fetchFunction: () => apiService.fetchWowTokenPrice(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => NewsProvider(prefs)),
        ChangeNotifierProvider(create: (_) => RedditProvider(prefs)),
        ChangeNotifierProvider(
          create: (_) => AuctionHouseProvider(
            searchFunction: (query) => apiService.searchItems(query),
            fetchPricesFunction: (itemIds) => _fetchCommodityPrices(
              itemIds, apiService.region, prefs,
            ),
            loadWatchlistFunction: () => _loadWatchlist(prefs),
            saveWatchlistFunction: (items) => _saveWatchlist(prefs, items),
            enrichIconFunction: (mediaId) => apiService.getItemIconUrl(mediaId),
          ),
        ),
      ],
      child: WowCompanionApp(authService: authService),
    ),
  );
}

class WowCompanionApp extends StatefulWidget {
  final BattleNetAuthService authService;

  const WowCompanionApp({super.key, required this.authService});

  @override
  State<WowCompanionApp> createState() => _WowCompanionAppState();
}

class _WowCompanionAppState extends State<WowCompanionApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initDeepLinks();
    }
  }

  /// Listens for deep link callbacks on mobile (OAuth redirect).
  void _initDeepLinks() {
    final appLinks = AppLinks();
    appLinks.uriLinkStream.listen((uri) {
      final code = widget.authService.extractCodeFromUri(uri);
      if (code != null) {
        _handleOAuthCode(code);
      }
    });
  }

  Future<void> _handleOAuthCode(String code) async {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;

    nav.pushReplacement(
      MaterialPageRoute(
        builder: (_) => _OAuthCallbackHandler(
          authService: widget.authService,
          code: code,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // On web, check for OAuth callback in URL
    final callbackCode = kIsWeb ? widget.authService.checkForCallbackCode() : null;

    final Widget home;
    if (callbackCode != null) {
      home = _OAuthCallbackHandler(
          authService: widget.authService, code: callbackCode);
    } else if (widget.authService.hasStoredToken()) {
      home = const _AutoLoginHandler();
    } else {
      home = const LoginScreen();
    }

    return MaterialApp(
      title: 'WoW Warband Companion',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme(),
      navigatorKey: _navigatorKey,
      home: home,
      routes: {
        '/login': (_) => const LoginScreen(),
      },
    );
  }
}

/// Auto-login: we have a stored token, load characters and go to dashboard.
class _AutoLoginHandler extends StatefulWidget {
  const _AutoLoginHandler();

  @override
  State<_AutoLoginHandler> createState() => _AutoLoginHandlerState();
}

class _AutoLoginHandlerState extends State<_AutoLoginHandler> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAndNavigate());
  }

  Future<void> _loadAndNavigate() async {
    final apiService = context.read<BattleNetApiService>();
    final regionService = context.read<RegionService>();

    // Apply stored region
    apiService.setRegion(regionService.activeRegion);

    final provider = context.read<CharacterProvider>();
    await provider.loadCharacters();

    if (!mounted) return;

    if (provider.hasCharacters) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const MainMenuScreen(),
        ),
      );
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF148EFF),
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Loading characters...',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Handles the OAuth callback: exchanges the code for a token,
/// loads characters, then navigates to the dashboard.
class _OAuthCallbackHandler extends StatefulWidget {
  final BattleNetAuthService authService;
  final String code;

  const _OAuthCallbackHandler({
    required this.authService,
    required this.code,
  });

  @override
  State<_OAuthCallbackHandler> createState() => _OAuthCallbackHandlerState();
}

class _OAuthCallbackHandlerState extends State<_OAuthCallbackHandler> {
  String _status = 'Signing in...';
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _handleOAuth();
  }

  Future<void> _handleOAuth() async {
    try {
      setState(() => _status = 'Exchanging token...');
      final success = await widget.authService.handleCallback(widget.code);

      if (!success) {
        setState(() {
          _status = 'Authentication failed. Please try again.';
          _hasError = true;
        });
        return;
      }

      if (!mounted) return;

      // Detect regions
      setState(() => _status = 'Detecting your regions...');
      final apiService = context.read<BattleNetApiService>();
      final regionService = context.read<RegionService>();

      final detected = await apiService.detectRegionsWithCharacters();
      await regionService.saveDetectedRegions(detected);
      await regionService.markRegionDetectionDone();

      if (detected.isNotEmpty) {
        // Pick the region with the most characters
        final bestRegion = detected.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key;
        await regionService.setActiveRegion(bestRegion);
        apiService.setRegion(bestRegion);
      }

      if (!mounted) return;

      if (detected.isEmpty) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const RegionPickerScreen(),
          ),
        );
        return;
      }

      setState(() => _status = 'Loading characters...');
      final provider = context.read<CharacterProvider>();
      await provider.loadCharacters();

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const MainMenuScreen(),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Error: $e';
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_hasError)
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFF148EFF),
                ),
              ),
            if (_hasError)
              const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 20),
            Text(
              _status,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            if (_hasError) ...[
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushReplacementNamed('/login');
                },
                child: const Text('Back to login'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<({Map<int, ({int minPrice, int totalQuantity})> prices, DateTime? lastUpdated})> _fetchCommodityPrices(
  List<int> itemIds,
  BattleNetRegion region,
  SharedPreferences prefs,
) async {
  if (itemIds.isEmpty) return (prices: <int, ({int minPrice, int totalQuantity})>{}, lastUpdated: null);

  const workerUrl = AppConfig.authProxyUrl;
  final ids = itemIds.join(',');
  final url = '$workerUrl/commodities/prices?items=$ids&region=${region.key}';

  // Retry once on connection errors (mobile networks can reset)
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      debugPrint('[AH] Fetching prices (attempt ${attempt + 1}): $url');
      final response = await http.get(Uri.parse(url));
      debugPrint('[AH] Response ${response.statusCode}: ${response.body.length} bytes');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pricesJson = data['prices'] as Map<String, dynamic>? ?? {};
        final lastUpdatedMs = data['last_updated'] as int?;

        return (
          prices: {
            for (final entry in pricesJson.entries)
              int.parse(entry.key): (
                minPrice: entry.value['min_price'] as int,
                totalQuantity: entry.value['total_quantity'] as int,
              ),
          },
          lastUpdated: lastUpdatedMs != null
              ? DateTime.fromMillisecondsSinceEpoch(lastUpdatedMs)
              : null,
        );
      }
      debugPrint('[AH] Price fetch failed: ${response.statusCode} ${response.body}');
      break; // Don't retry on HTTP errors, only connection errors
    } catch (e) {
      debugPrint('[AH] Price fetch error (attempt ${attempt + 1}): $e');
      if (attempt == 0) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }
  return (prices: <int, ({int minPrice, int totalQuantity})>{}, lastUpdated: null);
}

Future<List<AuctionItem>> _loadWatchlist(SharedPreferences prefs) async {
  final json = prefs.getString('ah_watchlist');
  if (json == null) return [];
  try {
    final list = jsonDecode(json) as List;
    return list
        .map((e) => AuctionItem.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> _saveWatchlist(SharedPreferences prefs, List<AuctionItem> items) async {
  final json = jsonEncode(items.map((i) => i.toJson()).toList());
  await prefs.setString('ah_watchlist', json);
}
