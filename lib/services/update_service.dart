import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Checks GitHub Releases for newer app versions.
class UpdateService {
  static const _repoOwner = 'faizal97';
  static const _repoName = 'wow-warband-companion';

  /// Returns update info if a newer version is available, null otherwise.
  /// Skips check on web (web always serves latest).
  static Future<UpdateInfo?> checkForUpdate() async {
    if (kIsWeb) return null;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.0.0"

      final response = await http.get(
        Uri.parse(
            'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final tagName = data['tag_name'] as String? ?? '';
      final latestVersion = tagName.replaceFirst('v', '');

      if (!_isNewer(latestVersion, currentVersion)) return null;

      // Find APK asset download URL
      String? downloadUrl;
      final assets = data['assets'] as List? ?? [];
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] as String?;
          break;
        }
      }

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        downloadUrl: downloadUrl,
        releaseNotes: data['body'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns true if [latest] is newer than [current] (semver comparison).
  static bool _isNewer(String latest, String current) {
    final latestParts = latest.split('.').map(int.tryParse).toList();
    final currentParts = current.split('.').map(int.tryParse).toList();

    for (var i = 0; i < 3; i++) {
      final l = i < latestParts.length ? (latestParts[i] ?? 0) : 0;
      final c = i < currentParts.length ? (currentParts[i] ?? 0) : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }
}

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String? downloadUrl;
  final String? releaseNotes;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    this.downloadUrl,
    this.releaseNotes,
  });
}
