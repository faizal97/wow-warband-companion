import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/character.dart';
import '../theme/app_theme.dart';
import '../theme/wow_class_colors.dart';

/// Horizontal scrolling character selector — each character is a pill
/// with their class color accent.
class CharacterSelector extends StatelessWidget {
  final List<WowCharacter> characters;
  final WowCharacter? selected;
  final ValueChanged<WowCharacter> onSelected;

  const CharacterSelector({
    super.key,
    required this.characters,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: characters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final character = characters[index];
          final isSelected = character.id == selected?.id;
          final classColor = WowClassColors.forClass(character.characterClass);

          return GestureDetector(
            onTap: () => onSelected(character),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? classColor.withValues(alpha: 0.15)
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isSelected
                      ? classColor.withValues(alpha: 0.5)
                      : AppTheme.surfaceBorder,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Class color dot
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: classColor,
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: classColor.withValues(alpha: 0.5),
                                blurRadius: 6,
                              )
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    character.name,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
