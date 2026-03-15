import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/achievement_provider.dart';
import '../services/battlenet_api_service.dart';
import '../services/character_provider.dart';
import '../services/region_service.dart';
import '../models/battlenet_region.dart';
import '../theme/app_theme.dart';
import '../widgets/update_dialog.dart';
import 'achievement_category_screen.dart';
import 'character_list_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateDialog.checkAndShow(context);
    });
  }

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
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final regionService = context.read<RegionService>();
                    return Text(
                      regionService.activeRegion.displayName,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                        letterSpacing: 1,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 40),
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
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    final regionService = context.read<RegionService>();
                    return _MenuCard(
                      icon: Icons.public_rounded,
                      title: 'Region',
                      subtitle: regionService.activeRegion.displayName,
                      onTap: () => _showRegionSwitcher(context),
                    );
                  },
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
                        final charProvider = context.read<CharacterProvider>();
                        final regionSvc = context.read<RegionService>();
                        final apiSvc = context.read<BattleNetApiService>();
                        final achProvider = context.read<AchievementProvider>();
                        charProvider.logout();
                        achProvider.clearProgress();
                        await regionSvc.clearAll();
                        apiSvc.setRegion(BattleNetRegion.us);
                        if (context.mounted) {
                          Navigator.of(context).pushReplacementNamed('/login');
                        }
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

  void _showRegionSwitcher(BuildContext context) {
    final regionService = context.read<RegionService>();
    final detected = regionService.detectedRegions;
    final activeRegion = regionService.activeRegion;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final detectedRegions = detected.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final otherRegions = BattleNetRegion.values
            .where((r) => !detected.containsKey(r))
            .toList();

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Switch Region',
                  style: GoogleFonts.rajdhani(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (detectedRegions.isNotEmpty) ...[
                          Text(
                            'DETECTED',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textTertiary,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...detectedRegions.map((entry) => _RegionOption(
                            region: entry.key,
                            subtitle: '${entry.value} characters',
                            isActive: entry.key == activeRegion,
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _switchRegion(context, entry.key);
                            },
                          )),
                        ],
                        if (otherRegions.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'OTHER REGIONS',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textTertiary,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...otherRegions.map((region) => _RegionOption(
                            region: region,
                            subtitle: region.key.toUpperCase(),
                            isActive: region == activeRegion,
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _switchRegion(context, region);
                            },
                          )),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _switchRegion(BuildContext context, BattleNetRegion region) async {
    final regionService = context.read<RegionService>();
    final apiService = context.read<BattleNetApiService>();
    final provider = context.read<CharacterProvider>();

    await regionService.setActiveRegion(region);
    apiService.setRegion(region);

    // TLA+ FIX #2: Bump load generation BEFORE forceRefresh
    provider.bumpLoadGeneration();

    // Clear achievement progress (per-region data)
    context.read<AchievementProvider>().clearProgress();

    // Clear cached data and reload for new region
    provider.forceRefresh();

    if (!context.mounted) return;

    // Navigate back to main menu (replace current)
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainMenuScreen()),
    );
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

class _RegionOption extends StatelessWidget {
  final BattleNetRegion region;
  final String subtitle;
  final bool isActive;
  final VoidCallback onTap;

  const _RegionOption({
    required this.region,
    required this.subtitle,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isActive ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF3FC7EB).withValues(alpha: 0.1)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? const Color(0xFF3FC7EB).withValues(alpha: 0.3)
                : AppTheme.surfaceBorder,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    region.displayName,
                    style: GoogleFonts.rajdhani(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? const Color(0xFF3FC7EB)
                          : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (isActive)
              const Icon(Icons.check_rounded, color: Color(0xFF3FC7EB), size: 20),
          ],
        ),
      ),
    );
  }
}
