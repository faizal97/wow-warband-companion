import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/battlenet_region.dart';
import '../services/battlenet_api_service.dart';
import '../services/character_provider.dart';
import '../services/region_service.dart';
import '../theme/app_theme.dart';
import 'main_menu_screen.dart';

/// Shown when auto-detection finds no characters, or from settings.
class RegionPickerScreen extends StatelessWidget {
  const RegionPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0A0A12),
              Color(0xFF12121C),
              Color(0xFF0A0A12),
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
                  'SELECT REGION',
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textTertiary,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose your region',
                  style: GoogleFonts.rajdhani(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'No characters were detected automatically.\nSelect the region your account is on.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                ...BattleNetRegion.values.map((region) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RegionTile(
                        region: region,
                        onTap: () => _selectRegion(context, region),
                      ),
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectRegion(
      BuildContext context, BattleNetRegion region) async {
    final regionService = context.read<RegionService>();
    final apiService = context.read<BattleNetApiService>();

    await regionService.setActiveRegion(region);
    apiService.setRegion(region);

    if (!context.mounted) return;

    final provider = context.read<CharacterProvider>();
    await provider.loadCharacters();

    if (!context.mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainMenuScreen()),
    );
  }
}

class _RegionTile extends StatelessWidget {
  final BattleNetRegion region;
  final VoidCallback onTap;

  const _RegionTile({required this.region, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.surfaceBorder, width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.public, color: Color(0xFF3FC7EB), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    region.displayName,
                    style: GoogleFonts.rajdhani(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    region.key.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
