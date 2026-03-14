import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/character.dart';
import '../theme/app_theme.dart';
import '../theme/wow_class_colors.dart';
import 'stat_chip.dart';

/// The main character summary card — hero section of the dashboard.
/// Features a class-colored gradient accent, character render, and key stats.
class CharacterSummaryCard extends StatelessWidget {
  final WowCharacter character;

  const CharacterSummaryCard({super.key, required this.character});

  @override
  Widget build(BuildContext context) {
    final classColor = WowClassColors.forClass(character.characterClass);
    final classColorDark = WowClassColors.forClassDark(character.characterClass);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: classColor.withValues(alpha:0.2),
          width: 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            classColor.withValues(alpha:0.08),
            AppTheme.surface,
            AppTheme.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top section: Character render + name
          _buildHeroSection(classColor, classColorDark),
          // Divider
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            color: classColor.withValues(alpha:0.1),
          ),
          // Stats row
          _buildStatsSection(classColor),
        ],
      ),
    );
  }

  Widget _buildHeroSection(Color classColor, Color classColorDark) {
    return SizedBox(
      height: 220,
      child: Stack(
        children: [
          // Background gradient with class color
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                gradient: RadialGradient(
                  center: Alignment.topRight,
                  radius: 1.2,
                  colors: [
                    classColor.withValues(alpha:0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Character render (or placeholder)
          Positioned(
            right: -20,
            top: 10,
            bottom: -10,
            width: 200,
            child: _buildCharacterImage(classColor),
          ),

          // Character info overlay
          Positioned(
            left: 24,
            bottom: 24,
            right: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Faction badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: character.faction == 'Horde'
                        ? const Color(0xFF8C1616).withValues(alpha:0.3)
                        : const Color(0xFF162E8C).withValues(alpha:0.3),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: character.faction == 'Horde'
                          ? const Color(0xFF8C1616).withValues(alpha:0.5)
                          : const Color(0xFF162E8C).withValues(alpha:0.5),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    character.faction.toUpperCase(),
                    style: GoogleFonts.rajdhani(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Character name
                Text(
                  character.name,
                  style: GoogleFonts.rajdhani(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),

                // Spec + Class with color
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: classColor,
                        boxShadow: [
                          BoxShadow(
                            color: classColor.withValues(alpha:0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${character.activeSpec} ${character.characterClass}',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: classColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),

                // Race + Realm
                Text(
                  '${character.race} · ${character.realm}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterImage(Color classColor) {
    if (character.renderUrl != null) {
      return CachedNetworkImage(
        imageUrl: character.renderUrl!,
        fit: BoxFit.contain,
        alignment: Alignment.bottomCenter,
        placeholder: (_, __) => _buildPlaceholderAvatar(classColor),
        errorWidget: (_, __, ___) => _buildPlaceholderAvatar(classColor),
      );
    }
    return _buildPlaceholderAvatar(classColor);
  }

  Widget _buildPlaceholderAvatar(Color classColor) {
    return Center(
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              classColor.withValues(alpha:0.15),
              classColor.withValues(alpha:0.03),
            ],
          ),
          border: Border.all(
            color: classColor.withValues(alpha:0.15),
            width: 1,
          ),
        ),
        child: Icon(
          Icons.person_outline_rounded,
          size: 48,
          color: classColor.withValues(alpha:0.4),
        ),
      ),
    );
  }

  Widget _buildStatsSection(Color classColor) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          StatChip(
            label: 'LEVEL',
            value: character.level.toString(),
            color: classColor,
          ),
          const SizedBox(width: 12),
          if (character.equippedItemLevel != null)
            StatChip(
              label: 'ITEM LVL',
              value: character.equippedItemLevel.toString(),
              color: _ilvlColor(character.equippedItemLevel!),
            ),
        ],
      ),
    );
  }

  /// Item level color — higher ilvl gets warmer/rarer colors.
  Color _ilvlColor(int ilvl) {
    if (ilvl >= 620) return const Color(0xFFFF8000); // Legendary orange
    if (ilvl >= 610) return const Color(0xFFA335EE); // Epic purple
    if (ilvl >= 600) return const Color(0xFF0070DD); // Rare blue
    if (ilvl >= 580) return const Color(0xFF1EFF00); // Uncommon green
    return AppTheme.textSecondary;
  }
}
