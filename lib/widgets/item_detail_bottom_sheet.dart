import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/equipped_item.dart';
import '../theme/app_theme.dart';
import '../theme/wow_item_quality.dart';

/// Bottom sheet displaying full details for an equipped item.
class ItemDetailBottomSheet extends StatelessWidget {
  final EquippedItem item;

  const ItemDetailBottomSheet({super.key, required this.item});

  /// Shows the bottom sheet for the given item.
  static void show(BuildContext context, EquippedItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ItemDetailBottomSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qualityColor = WowItemQuality.forQuality(item.quality);

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.surfaceBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Item name
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Text(
              item.itemName,
              style: GoogleFonts.rajdhani(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: qualityColor,
              ),
            ),
          ),

          // Slot and item level
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '${item.slotDisplayName}  \u00b7  Item Level ${item.itemLevel}',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Divider
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            color: AppTheme.surfaceBorder,
          ),

          // Enchantments
          if (item.enchantments.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildDetailSection(
              'Enchantments',
              item.enchantments,
              const Color(0xFF1EFF00),
            ),
          ],

          // Sockets / Gems
          if (item.sockets.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildDetailSection(
              'Gems',
              item.sockets,
              const Color(0xFF0070DD),
            ),
          ],

          // Set name
          if (item.setName != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 14,
                    color: const Color(0xFF1EFF00).withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.setName!,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1EFF00),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Bottom padding (safe area)
          SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
        ],
      ),
    );
  }

  Widget _buildDetailSection(
    String title,
    List<String> items,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppTheme.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          ...items.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: color.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
