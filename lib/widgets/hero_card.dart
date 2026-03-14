import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/character.dart';
import '../theme/app_theme.dart';
import '../theme/wow_class_colors.dart';

/// Compact hero card with character render background and inline stats.
class HeroCard extends StatelessWidget {
  final WowCharacter character;

  const HeroCard({super.key, required this.character});

  @override
  Widget build(BuildContext context) {
    final classColor = WowClassColors.forClass(character.characterClass);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppTheme.surface,
        border: Border.all(
          color: classColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Class-colored top accent
          Positioned(
            top: 0, left: 0, right: 0, height: 2,
            child: Container(color: classColor),
          ),

          // Background gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    classColor.withValues(alpha: 0.06),
                    AppTheme.surface,
                  ],
                ),
              ),
            ),
          ),

          // Character render (right side)
          Positioned(
            right: -20,
            top: -10,
            bottom: -30,
            width: 200,
            child: _buildCharacterRender(classColor),
          ),

          // Gradient overlay for text readability
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0.0, 0.5, 0.75, 1.0],
                  colors: [
                    AppTheme.surface,
                    AppTheme.surface.withValues(alpha: 0.92),
                    AppTheme.surface.withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Character info
          Positioned(
            left: 16,
            top: 16,
            right: 140,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Faction + Level row
                Row(
                  children: [
                    _buildFactionBadge(),
                    const SizedBox(width: 6),
                    Text(
                      'Lv ${character.level}',
                      style: GoogleFonts.rajdhani(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: classColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Name
                Text(
                  character.name,
                  style: GoogleFonts.rajdhani(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),

                // Spec + Class
                Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: classColor,
                        boxShadow: [
                          BoxShadow(
                            color: classColor.withValues(alpha: 0.5),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '${character.activeSpec} ${character.characterClass}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: classColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // Race + Realm
                Text(
                  '${character.race} · ${character.realm}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),

                const Spacer(),

                // Inline stat badges
                _buildInlineStats(classColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFactionBadge() {
    final isHorde = character.faction == 'Horde';
    final badgeColor =
        isHorde ? const Color(0xFF8C1616) : const Color(0xFF162E8C);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Text(
        isHorde ? 'H' : 'A',
        style: GoogleFonts.rajdhani(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isHorde ? const Color(0xFFCC3333) : const Color(0xFF3366CC),
        ),
      ),
    );
  }

  Widget _buildInlineStats(Color classColor) {
    return Row(
      children: [
        if (character.equippedItemLevel != null)
          _statBadge(
            '${character.equippedItemLevel} ilvl',
            _ilvlColor(character.equippedItemLevel!),
          ),
        if (character.equippedItemLevel != null) const SizedBox(width: 6),
        if (character.achievementPoints != null)
          _statBadge(
            '${character.achievementPoints} pts',
            const Color(0xFFFFD100),
          ),
      ],
    );
  }

  Widget _statBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: GoogleFonts.rajdhani(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildCharacterRender(Color classColor) {
    if (character.renderUrl != null) {
      return CachedNetworkImage(
        imageUrl: character.renderUrl!,
        fit: BoxFit.contain,
        alignment: Alignment.bottomCenter,
        placeholder: (_, __) => _buildPlaceholder(classColor),
        errorWidget: (_, __, ___) => _buildPlaceholder(classColor),
      );
    }
    return _buildPlaceholder(classColor);
  }

  Widget _buildPlaceholder(Color classColor) {
    return Center(
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              classColor.withValues(alpha: 0.12),
              classColor.withValues(alpha: 0.03),
            ],
          ),
        ),
        child: Icon(
          Icons.person_outline_rounded,
          size: 36,
          color: classColor.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Color _ilvlColor(int ilvl) {
    if (ilvl >= 620) return const Color(0xFFFF8000);
    if (ilvl >= 610) return const Color(0xFFA335EE);
    if (ilvl >= 600) return const Color(0xFF0070DD);
    if (ilvl >= 580) return const Color(0xFF1EFF00);
    return AppTheme.textSecondary;
  }
}
