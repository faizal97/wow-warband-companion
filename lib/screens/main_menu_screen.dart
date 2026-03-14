import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/achievement_provider.dart';
import '../services/character_provider.dart';
import '../theme/app_theme.dart';
import 'achievement_category_screen.dart';
import 'character_list_screen.dart';

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.3, 1.0],
            colors: [
              Color(0xFF101018),
              AppTheme.background,
              AppTheme.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),
                Text(
                  'WOW WARBAND',
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textTertiary,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Companion',
                  style: GoogleFonts.rajdhani(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 48),
                _MenuCard(
                  icon: Icons.people_rounded,
                  title: 'Characters',
                  subtitle: _buildCharacterSubtitle(context),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CharacterListScreen()),
                  ),
                ),
                const SizedBox(height: 16),
                _MenuCard(
                  icon: Icons.emoji_events_rounded,
                  title: 'Achievements',
                  subtitle: _buildAchievementSubtitle(context),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AchievementCategoryScreen()),
                  ),
                ),
                const Spacer(),
                // Footer links
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _FooterLink(
                      icon: Icons.favorite_rounded,
                      label: 'Support',
                      color: const Color(0xFFFF5E5B),
                      onTap: () => launchUrl(
                        Uri.parse('https://ko-fi.com/starlighthvn'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    _footerDot(),
                    _FooterLink(
                      icon: Icons.code_rounded,
                      label: 'GitHub',
                      onTap: () => launchUrl(
                        Uri.parse('https://github.com/faizal97/wow-warband-companion'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    if (kIsWeb) ...[
                      _footerDot(),
                      _FooterLink(
                        icon: Icons.download_rounded,
                        label: 'Download APK',
                        onTap: () => launchUrl(
                          Uri.parse('https://github.com/faizal97/wow-warband-companion/releases/latest'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: GestureDetector(
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: AppTheme.surfaceElevated,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          title: Text(
                            'Sign Out',
                            style: GoogleFonts.rajdhani(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          content: Text(
                            'Are you sure you want to sign out?',
                            style: GoogleFonts.inter(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(
                                'Cancel',
                                style: GoogleFonts.inter(color: AppTheme.textTertiary),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(
                                'Sign Out',
                                style: GoogleFonts.inter(color: const Color(0xFFFF5E5B)),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        context.read<CharacterProvider>().logout();
                        Navigator.of(context).pushReplacementNamed('/login');
                      }
                    },
                    child: Text(
                      'Sign Out',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buildCharacterSubtitle(BuildContext context) {
    final provider = context.watch<CharacterProvider>();
    if (provider.hasCharacters) {
      return '${provider.characters.length} characters';
    }
    return 'View your warband';
  }

  String _buildAchievementSubtitle(BuildContext context) {
    final provider = context.watch<AchievementProvider>();
    final points = provider.progress?.totalPoints;
    if (points != null && points > 0) {
      return '$points points';
    }
    return 'Track your progress';
  }

  static Widget _footerDot() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        width: 3,
        height: 3,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.surfaceBorder,
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.surfaceBorder, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF3FC7EB).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF3FC7EB), size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.rajdhani(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textTertiary,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _FooterLink({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppTheme.textTertiary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
