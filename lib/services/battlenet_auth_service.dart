import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

/// Handles Battle.net OAuth 2.0 Authorization Code flow.
///
/// Works on both web (browser redirect + Uri.base) and mobile
/// (system browser + deep link callback).
class BattleNetAuthService {
  static const _tokenKey = 'bnet_access_token';

  final SharedPreferences _prefs;

  BattleNetAuthService(this._prefs);

  /// Returns the Battle.net OAuth authorization URL.
  Uri getAuthorizationUrl() {
    return Uri.parse('https://oauth.battle.net/authorize').replace(
      queryParameters: {
        'client_id': AppConfig.battleNetClientId,
        'redirect_uri': AppConfig.redirectUri,
        'response_type': 'code',
        'scope': 'wow.profile',
        'state': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
  }

  /// Checks the current page URL for an OAuth callback code (web only).
  String? checkForCallbackCode() {
    if (!kIsWeb) return null;
    final uri = Uri.base;
    if (uri.path.contains('/auth/callback') &&
        uri.queryParameters.containsKey('code')) {
      return uri.queryParameters['code'];
    }
    return null;
  }

  /// Extracts an OAuth code from a deep link URI (mobile).
  String? extractCodeFromUri(Uri uri) {
    if (uri.queryParameters.containsKey('code')) {
      return uri.queryParameters['code'];
    }
    return null;
  }

  /// Checks if we have a stored token from a previous session.
  bool hasStoredToken() {
    final token = _prefs.getString(_tokenKey);
    return token != null && token.isNotEmpty;
  }

  /// Exchanges the authorization code for an access token via the auth proxy.
  Future<bool> handleCallback(String code) async {
    try {
      const proxyUrl = AppConfig.authProxyUrl;
      if (proxyUrl.isEmpty) return false;

      final response = await http.post(
        Uri.parse('$proxyUrl/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'redirect_uri': AppConfig.redirectUri,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['access_token'] as String?;
        if (token != null) {
          await _prefs.setString(_tokenKey, token);
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Returns the stored access token.
  Future<String?> getAccessToken() async {
    return _prefs.getString(_tokenKey);
  }

  /// Clears stored token (logout).
  Future<void> logout() async {
    await _prefs.remove(_tokenKey);
  }

  /// Check if user is authenticated.
  Future<bool> isAuthenticated() async {
    return hasStoredToken();
  }
}
