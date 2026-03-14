import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../models/equipped_item.dart';
import '../theme/app_theme.dart';
import '../theme/wow_item_quality.dart';
import 'item_detail_bottom_sheet.dart';

/// Two-column mirrored equipment layout — icons on outer edges.
class EquipmentGrid extends StatelessWidget {
  final CharacterEquipment? equipment;
  final bool isLoading;

  const EquipmentGrid({
    super.key,
    required this.equipment,
    required this.isLoading,
  });

  // Left column slots (icon on left, text flows right)
  static const _leftSlots = [
    'HEAD', 'NECK', 'SHOULDER', 'BACK', 'CHEST', 'WRIST',
    'MAIN_HAND', 'OFF_HAND',
  ];

  // Right column slots (icon on right, text flows left)
  static const _rightSlots = [
    'HANDS', 'WAIST', 'LEGS', 'FEET', 'FINGER_1', 'FINGER_2',
    'TRINKET_1', 'TRINKET_2',
  ];

  @override
  Widget build(BuildContext context) {
    if (isLoading) return _buildShimmer();

    final items = equipment?.equippedItems;
    if (items == null || items.isEmpty) return _buildEmptyState();

    final itemMap = <String, EquippedItem>{};
    for (final item in items) {
      itemMap[item.slot] = item;
    }

    final rowCount =
        _leftSlots.length > _rightSlots.length
            ? _leftSlots.length
            : _rightSlots.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var i = 0; i < rowCount; i++)
            _buildPairedRow(
              leftItem: i < _leftSlots.length ? itemMap[_leftSlots[i]] : null,
              rightItem:
                  i < _rightSlots.length ? itemMap[_rightSlots[i]] : null,
              index: i,
            ),
        ],
      ),
    );
  }

  Widget _buildPairedRow({
    EquippedItem? leftItem,
    EquippedItem? rightItem,
    required int index,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.surfaceBorder.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left item (icon left, text right)
            Expanded(
              child: leftItem != null
                  ? _EquipmentCell(item: leftItem, isLeft: true)
                  : const SizedBox.shrink(),
            ),

            // Center divider
            Container(
              width: 0.5,
              color: AppTheme.surfaceBorder.withValues(alpha: 0.5),
            ),

            // Right item (text left, icon right)
            Expanded(
              child: rightItem != null
                  ? _EquipmentCell(item: rightItem, isLeft: false)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Shimmer.fromColors(
        baseColor: AppTheme.surface,
        highlightColor: AppTheme.surfaceElevated,
        child: Column(
          children: List.generate(
            7,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Center(
        child: Text(
          'No equipment data',
          style: GoogleFonts.dmSans(
            fontSize: 14,
            color: AppTheme.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// A single equipment cell — mirrored layout based on column side.
class _EquipmentCell extends StatelessWidget {
  final EquippedItem item;
  final bool isLeft;

  const _EquipmentCell({required this.item, required this.isLeft});

  @override
  Widget build(BuildContext context) {
    final qualityColor = WowItemQuality.forQuality(item.quality);

    return GestureDetector(
      onTap: () => ItemDetailBottomSheet.show(context, item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          textDirection: isLeft ? TextDirection.ltr : TextDirection.rtl,
          children: [
            // Item icon
            _buildIcon(qualityColor),
            const SizedBox(width: 8),

            // Item info
            Expanded(
              child: Column(
                crossAxisAlignment:
                    isLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Item name
                  Text(
                    item.itemName,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: qualityColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: isLeft ? TextAlign.left : TextAlign.right,
                  ),

                  // Enchants / gems row
                  if (item.enchantments.isNotEmpty || item.sockets.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        [
                          ...item.enchantments,
                          ...item.sockets,
                        ].join(' · '),
                        style: GoogleFonts.dmSans(
                          fontSize: 10,
                          color: const Color(0xFF1EFF00),
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: isLeft ? TextAlign.left : TextAlign.right,
                      ),
                    ),

                  // iLvl
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      'ilvl ${item.itemLevel}',
                      style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textTertiary,
                      ),
                      textAlign: isLeft ? TextAlign.left : TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(Color qualityColor) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: qualityColor.withValues(alpha: 0.6),
          width: 1.5,
        ),
        color: AppTheme.surface,
      ),
      clipBehavior: Clip.antiAlias,
      child: item.iconUrl != null
          ? CachedNetworkImage(
              imageUrl: item.iconUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => _iconFallback(qualityColor),
              errorWidget: (_, __, ___) => _iconFallback(qualityColor),
            )
          : _iconFallback(qualityColor),
    );
  }

  Widget _iconFallback(Color qualityColor) {
    return Container(
      color: qualityColor.withValues(alpha: 0.08),
      child: Center(
        child: Text(
          _slotAbbr(item.slotDisplayName),
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: qualityColor.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  String _slotAbbr(String name) {
    final words = name.split(' ');
    if (words.length > 1) return words.map((w) => w[0].toUpperCase()).join();
    return name.length >= 3 ? name.substring(0, 3).toUpperCase() : name.toUpperCase();
  }
}
