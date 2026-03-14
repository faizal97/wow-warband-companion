import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/character.dart';
import '../theme/app_theme.dart';
import '../theme/wow_class_colors.dart';

/// A compact character tile for the "Other Characters" list section.
class CharacterListTile extends StatelessWidget {
  final WowCharacter character;
  final bool isSelected;
  final VoidCallback onTap;

  const CharacterListTile({
    super.key,
    required this.character,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final classColor = WowClassColors.forClass(character.characterClass);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? classColor.withValues(alpha:0.08)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? classColor.withValues(alpha:0.25)
                : AppTheme.surfaceBorder,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Class color indicator
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: classColor.withValues(alpha:0.12),
                border: Border.all(
                  color: classColor.withValues(alpha:0.2),
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  character.level.toString(),
                  style: GoogleFonts.rajdhani(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: classColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Name + details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    character.name,
                    style: GoogleFonts.rajdhani(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${character.activeSpec} ${character.characterClass} · ${character.realm}',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),

            // iLvl badge
            if (character.equippedItemLevel != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${character.equippedItemLevel}',
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
