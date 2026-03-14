import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/battlenet_auth_service.dart';
import 'services/battlenet_api_service.dart';
import 'services/character_cache_service.dart';
import 'services/character_provider.dart';
import 'services/character_detail_provider.dart';
import 'screens/login_screen.dart';
import 'screens/character_list_screen.dart';
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
  final authService = BattleNetAuthService(prefs);
  final apiService = BattleNetApiService(authService);
  final cacheService = CharacterCacheService(prefs);

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: authService),
        ChangeNotifierProvider(
          create: (_) =>
              CharacterProvider(apiService, authService, cacheService),
        ),
        ChangeNotifierProvider(
          create: (_) => CharacterDetailProvider(apiService, cacheService),
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
    final provider = context.read<CharacterProvider>();
    final detailProvider = context.read<CharacterDetailProvider>();
    provider.useRealApi();
    detailProvider.useRealApi();
    await provider.loadCharacters();

    if (!mounted) return;

    if (provider.hasCharacters) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const CharacterListScreen(),
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

      setState(() => _status = 'Loading characters...');
      final provider = context.read<CharacterProvider>();
      final detailProvider = context.read<CharacterDetailProvider>();
      provider.useRealApi();
      detailProvider.useRealApi();
      await provider.loadCharacters();

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const CharacterListScreen(),
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
