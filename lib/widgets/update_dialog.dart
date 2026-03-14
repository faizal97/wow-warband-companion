import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';

/// Shows an update dialog if a newer version is available.
class UpdateDialog {
  static Future<void> checkAndShow(BuildContext context) async {
    final update = await UpdateService.checkForUpdate();
    if (update == null) return;
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (_) => _UpdateDialogContent(update: update),
    );
  }
}

class _UpdateDialogContent extends StatelessWidget {
  final UpdateInfo update;

  const _UpdateDialogContent({required this.update});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: const Color(0xFF3FC7EB).withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF3FC7EB).withValues(alpha: 0.1),
                border: Border.all(
                  color: const Color(0xFF3FC7EB).withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.system_update_rounded,
                color: Color(0xFF3FC7EB),
                size: 28,
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              'Update Available',
              style: GoogleFonts.rajdhani(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),

            // Version info
            Text(
              'v${update.currentVersion} → v${update.latestVersion}',
              style: GoogleFonts.rajdhani(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF3FC7EB),
              ),
            ),
            const SizedBox(height: 8),

            Text(
              'A new version is available with improvements and bug fixes.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),

            // Update button
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () {
                  if (update.downloadUrl != null) {
                    launchUrl(
                      Uri.parse(update.downloadUrl!),
                      mode: LaunchMode.externalApplication,
                    );
                  }
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3FC7EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'UPDATE',
                  style: GoogleFonts.rajdhani(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Skip button
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Later',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
