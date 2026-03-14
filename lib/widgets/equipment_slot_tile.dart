import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/equipped_item.dart';
import '../theme/app_theme.dart';
import '../theme/wow_item_quality.dart';
import 'item_detail_bottom_sheet.dart';

/// A single equipment slot tile showing item info at a glance.
class EquipmentSlotTile extends StatelessWidget {
  final EquippedItem item;

  const EquipmentSlotTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final qualityColor = WowItemQuality.forQuality(item.quality);

    return GestureDetector(
      onTap: () => ItemDetailBottomSheet.show(context, item),
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: qualityColor.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Stack(
          children: [
            // Subtle quality-colored background tint
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      qualityColor.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Slot abbreviation
            Center(
              child: Text(
                _slotAbbreviation(item.slotDisplayName),
                style: GoogleFonts.rajdhani(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),

            // Item level (bottom-right)
            Positioned(
              right: 4,
              bottom: 3,
              child: Text(
                item.itemLevel.toString(),
                style: GoogleFonts.rajdhani(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: qualityColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Generates a short abbreviation from the slot display name.
  String _slotAbbreviation(String slotName) {
    // Handle multi-word slot names
    final words = slotName.split(' ');
    if (words.length > 1) {
      // e.g. "Main Hand" -> "MH", "Off Hand" -> "OH", "Finger 1" -> "R1"
      return words.map((w) => w[0].toUpperCase()).join();
    }
    // Single word: take first 3 characters
    return slotName.length >= 3
        ? slotName.substring(0, 3).toUpperCase()
        : slotName.toUpperCase();
  }
}
