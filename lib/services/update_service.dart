import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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
      final currentVersion = packageInfo.version;
      debugPrint('[UpdateService] Current version: $currentVersion');

      final response = await http.get(
        Uri.parse(
            'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode != 200) {
        debugPrint('[UpdateService] GitHub API returned ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      final tagName = data['tag_name'] as String? ?? '';
      final latestVersion = tagName.replaceFirst('v', '');
      debugPrint('[UpdateService] Latest release: $latestVersion (tag: $tagName)');

      if (!_isNewer(latestVersion, currentVersion)) {
        debugPrint('[UpdateService] No update needed ($currentVersion >= $latestVersion)');
        return null;
      }

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

      debugPrint('[UpdateService] Update available: $currentVersion -> $latestVersion');
      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        downloadUrl: downloadUrl,
        releaseNotes: data['body'] as String?,
      );
    } catch (e) {
      debugPrint('[UpdateService] Error checking for update: $e');
      return null;
    }
  }

  /// Downloads the APK to cache and triggers the system installer.
  static Future<void> downloadAndInstall(
    String downloadUrl,
    void Function(double progress) onProgress,
  ) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Download failed with status ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/update.apk');

      final sink = file.openWrite();
      var downloaded = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          onProgress(downloaded / contentLength);
        }
      }

      await sink.close();
      debugPrint('[UpdateService] Download complete: ${file.path} (${downloaded ~/ 1024} KB)');

      // Trigger system installer via platform channel
      const channel = MethodChannel('com.wowwarband.companion/installer');
      await channel.invokeMethod('installApk', {'filePath': file.path});
    } finally {
      client.close();
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
