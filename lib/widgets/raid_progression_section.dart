import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../models/raid_progression.dart';
import '../screens/raid_detail_screen.dart';
import '../theme/app_theme.dart';

/// Displays raid progression as compact tiles that navigate to a detail screen.
class RaidProgressionSection extends StatelessWidget {
  final RaidProgression? progression;
  final bool isLoading;

  const RaidProgressionSection({
    super.key,
    required this.progression,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) return _buildShimmer();

    if (progression == null || progression!.instances.isEmpty) {
      return _buildEmptyState();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Expansion label
          if (progression!.expansionName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                      color: const Color(0xFFA335EE),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    progression!.expansionName.toUpperCase(),
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textTertiary,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          // Raid tiles
          ...progression!.instances.map((raid) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildRaidTile(context, raid),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRaidTile(BuildContext context, RaidInstance raid) {
    final accentColor = _highestDifficultyColor(raid);

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RaidDetailScreen(
              raidInstanceId: raid.id,
              expansionName: progression!.expansionName,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Accent bar at top
            Container(height: 2, color: accentColor.withValues(alpha: 0.6)),

            // Header
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accentColor.withValues(alpha: 0.06),
                    AppTheme.surface,
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
              child: Row(
                children: [
                  // Raid icon
                  _buildRaidIcon(raid, accentColor),
                  const SizedBox(width: 10),

                  // Raid info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          raid.name,
                          style: GoogleFonts.rajdhani(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 5),
                        _buildDifficultyBadges(raid),
                      ],
                    ),
                  ),

                  // Navigate indicator
                  Icon(
                    Icons.chevron_right_rounded,
                    color: accentColor.withValues(alpha: 0.5),
                    size: 22,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRaidIcon(RaidInstance raid, Color accentColor) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.4),
          width: 1.5,
        ),
        color: accentColor.withValues(alpha: 0.08),
      ),
      clipBehavior: Clip.antiAlias,
      child: raid.iconUrl != null
          ? CachedNetworkImage(
              imageUrl: raid.iconUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => _iconFallback(raid.name, accentColor),
              errorWidget: (_, __, ___) =>
                  _iconFallback(raid.name, accentColor),
            )
          : _iconFallback(raid.name, accentColor),
    );
  }

  Widget _iconFallback(String name, Color color) {
    return Container(
      color: color.withValues(alpha: 0.08),
      child: Center(
        child: Text(
          _abbr(name),
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildDifficultyBadges(RaidInstance raid) {
    return Wrap(
      spacing: 5,
      runSpacing: 4,
      children: raid.difficulties.map((diff) {
        final color = _difficultyColor(diff.type);
        final hasProgress = diff.completedCount > 0;
        final label =
            '${diff.completedCount}/${diff.totalCount} ${_difficultyLabel(diff.type)}';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: hasProgress
                ? color.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: hasProgress
                  ? color.withValues(alpha: 0.3)
                  : AppTheme.surfaceBorder,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: hasProgress ? color : AppTheme.textTertiary,
            ),
          ),
        );
      }).toList(),
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
            2,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
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
          'No raid data available',
          style: GoogleFonts.dmSans(
            fontSize: 14,
            color: AppTheme.textTertiary,
          ),
        ),
      ),
    );
  }

  Color _highestDifficultyColor(RaidInstance raid) {
    const order = ['MYTHIC', 'HEROIC', 'NORMAL', 'LFR'];
    for (final diff in order) {
      final progress = raid.difficulties.where((d) => d.type == diff);
      if (progress.isNotEmpty && progress.first.completedCount > 0) {
        return _difficultyColor(diff);
      }
    }
    return AppTheme.textTertiary;
  }

  static Color _difficultyColor(String type) {
    switch (type) {
      case 'LFR':
        return const Color(0xFF1EFF00);
      case 'NORMAL':
        return const Color(0xFF0070DD);
      case 'HEROIC':
        return const Color(0xFFA335EE);
      case 'MYTHIC':
        return const Color(0xFFFF8000);
      default:
        return AppTheme.textSecondary;
    }
  }

  static String _difficultyLabel(String type) {
    switch (type) {
      case 'LFR':
        return 'LFR';
      case 'NORMAL':
        return 'N';
      case 'HEROIC':
        return 'H';
      case 'MYTHIC':
        return 'M';
      default:
        return type.isNotEmpty ? type[0] : '?';
    }
  }

  String _abbr(String name) {
    final words = name
        .replaceAll("'s", '')
        .replaceAll(':', '')
        .replaceAll(',', '')
        .split(' ')
        .where((w) => w.isNotEmpty && w[0] == w[0].toUpperCase())
        .toList();
    if (words.length >= 2) return words.take(3).map((w) => w[0]).join();
    return name.substring(0, name.length.clamp(0, 3)).toUpperCase();
  }
}
