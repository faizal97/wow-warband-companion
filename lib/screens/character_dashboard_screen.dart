import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/character.dart';
import '../services/character_provider.dart';
import '../services/character_detail_provider.dart';
import '../theme/app_theme.dart';
import '../theme/wow_class_colors.dart';
import '../widgets/hero_card.dart';
import '../widgets/section_header.dart';
import '../widgets/equipment_grid.dart';
import '../widgets/mythic_plus_section.dart';
import '../widgets/raid_progression_section.dart';

/// Detail view for a single selected character.
class CharacterDashboardScreen extends StatefulWidget {
  const CharacterDashboardScreen({super.key});

  @override
  State<CharacterDashboardScreen> createState() =>
      _CharacterDashboardScreenState();
}

class _CharacterDashboardScreenState extends State<CharacterDashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Defer to avoid calling notifyListeners during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final charProvider = context.read<CharacterProvider>();
      final detailProvider = context.read<CharacterDetailProvider>();
      final selected = charProvider.selectedCharacter;
      if (selected != null) {
        detailProvider.loadDetails(selected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CharacterProvider>(
      builder: (context, charProvider, _) {
        final selected = charProvider.selectedCharacter;
        final classColor = selected != null
            ? WowClassColors.forClass(selected.characterClass)
            : const Color(0xFF3FC7EB);

        return AnimatedTheme(
          duration: const Duration(milliseconds: 400),
          data: AppTheme.darkTheme(accentColor: classColor),
          child: Scaffold(
            body: selected == null
                ? _buildEmpty()
                : Consumer<CharacterDetailProvider>(
                    builder: (context, detailProvider, _) {
                      return _buildContent(
                        context,
                        selected,
                        classColor,
                        detailProvider,
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Text(
        'No character selected',
        style: TextStyle(color: AppTheme.textTertiary),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WowCharacter selected,
    Color classColor,
    CharacterDetailProvider detailProvider,
  ) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => detailProvider.forceRefresh(selected),
          color: classColor,
          backgroundColor: AppTheme.surface,
          child: CustomScrollView(
          slivers: [
            // Top bar + hero with class-colored gradient
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      classColor.withValues(alpha: 0.1),
                      AppTheme.background,
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    _buildTopBar(context, classColor),
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: HeroCard(character: selected),
                    ),
                  ],
                ),
              ),
            ),

            // Equipment section
            const SliverToBoxAdapter(
              child: SectionHeader(title: 'EQUIPMENT'),
            ),
            SliverToBoxAdapter(
              child: EquipmentGrid(
                equipment: detailProvider.equipment,
                isLoading: detailProvider.isEquipmentLoading,
              ),
            ),

            // Mythic+ section
            const SliverToBoxAdapter(
              child: SectionHeader(title: 'MYTHIC+'),
            ),
            SliverToBoxAdapter(
              child: MythicPlusSection(
                profile: detailProvider.mythicPlusProfile,
                isLoading: detailProvider.isMythicPlusLoading,
              ),
            ),

            // Raid Progression section
            const SliverToBoxAdapter(
              child: SectionHeader(title: 'RAID PROGRESSION'),
            ),
            SliverToBoxAdapter(
              child: RaidProgressionSection(
                progression: detailProvider.raidProgression,
                isLoading: detailProvider.isRaidLoading,
              ),
            ),

            // Bottom padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 40),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, Color classColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 20, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: classColor,
              size: 22,
            ),
          ),
          Text(
            'CHARACTER',
            style: GoogleFonts.rajdhani(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

}
