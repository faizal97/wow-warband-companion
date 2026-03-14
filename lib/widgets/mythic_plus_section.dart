import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../models/mythic_plus_profile.dart';
import '../theme/app_theme.dart';

/// Displays M+ rating and best runs grouped by dungeon with affix toggle.
class MythicPlusSection extends StatefulWidget {
  final MythicPlusProfile? profile;
  final bool isLoading;

  const MythicPlusSection({
    super.key,
    required this.profile,
    required this.isLoading,
  });

  @override
  State<MythicPlusSection> createState() => _MythicPlusSectionState();
}

class _MythicPlusSectionState extends State<MythicPlusSection> {
  String? _selectedAffix; // null = best run per dungeon

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) return _buildShimmer();

    if (widget.profile == null || widget.profile!.currentRating == 0) {
      return _buildEmptyState();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildRatingBadge(),
          if (widget.profile!.bestRuns.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildAffixToggle(),
            const SizedBox(height: 8),
            _buildDungeonGrid(),
          ],
        ],
      ),
    );
  }

  Widget _buildRatingBadge() {
    final rating = widget.profile!.currentRating;
    final ratingColor = _ensureContrast(widget.profile!.ratingColor);
    final formattedRating = _formatRating(rating);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ratingColor.withValues(alpha: 0.35),
          width: 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ratingColor.withValues(alpha: 0.15),
            AppTheme.surface,
            AppTheme.surface,
          ],
        ),
      ),
      child: Column(
        children: [
          Text(
            formattedRating,
            style: GoogleFonts.rajdhani(
              fontSize: 42,
              fontWeight: FontWeight.w700,
              color: ratingColor,
              height: 1.0,
              shadows: [
                Shadow(
                  color: ratingColor.withValues(alpha: 0.3),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.profile!.latestSeasonId != null
                ? 'MYTHIC+ RATING · SEASON ${widget.profile!.latestSeasonId}'
                : 'MYTHIC+ RATING',
            style: GoogleFonts.rajdhani(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAffixToggle() {
    // Collect unique affixes from runs
    final affixes = <String>{};
    for (final run in widget.profile!.bestRuns) {
      if (run.affixes.isNotEmpty) affixes.add(run.affixes.first);
    }

    final options = [null, ...affixes.toList()..sort()];

    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final affix = options[index];
          final isSelected = _selectedAffix == affix;
          final label = affix ?? 'Best';

          return GestureDetector(
            onTap: () => setState(() => _selectedAffix = affix),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF3FC7EB).withValues(alpha: 0.12)
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF3FC7EB).withValues(alpha: 0.4)
                      : AppTheme.surfaceBorder,
                  width: 1,
                ),
              ),
              child: Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? const Color(0xFF3FC7EB)
                      : AppTheme.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDungeonGrid() {
    // Group runs by dungeon, pick one run per dungeon based on selected affix
    final dungeonRuns = <String, MythicPlusBestRun>{};

    for (final run in widget.profile!.bestRuns) {
      final name = run.dungeonName;

      if (_selectedAffix == null) {
        // "Best" mode — pick highest keystone per dungeon
        if (!dungeonRuns.containsKey(name) ||
            run.keystoneLevel > dungeonRuns[name]!.keystoneLevel) {
          dungeonRuns[name] = run;
        }
      } else {
        // Affix filter — only show runs matching the selected affix
        if (run.affixes.isNotEmpty && run.affixes.first == _selectedAffix) {
          dungeonRuns[name] = run;
        }
      }
    }

    // Sort by rating descending
    final entries = dungeonRuns.entries.toList()
      ..sort((a, b) => b.value.rating.compareTo(a.value.rating));

    // Split into left/right
    final left = <MapEntry<String, MythicPlusBestRun>>[];
    final right = <MapEntry<String, MythicPlusBestRun>>[];
    for (var i = 0; i < entries.length; i++) {
      if (i.isEven) {
        left.add(entries[i]);
      } else {
        right.add(entries[i]);
      }
    }

    final rowCount = left.length > right.length ? left.length : right.length;

    return Column(
      children: [
        for (var i = 0; i < rowCount; i++)
          _buildPairedRow(
            leftEntry: i < left.length ? left[i] : null,
            rightEntry: i < right.length ? right[i] : null,
          ),
      ],
    );
  }

  Widget _buildPairedRow({
    MapEntry<String, MythicPlusBestRun>? leftEntry,
    MapEntry<String, MythicPlusBestRun>? rightEntry,
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
            Expanded(
              child: leftEntry != null
                  ? _DungeonCell(run: leftEntry.value, isLeft: true)
                  : const SizedBox.shrink(),
            ),
            Container(
              width: 0.5,
              color: AppTheme.surfaceBorder.withValues(alpha: 0.5),
            ),
            Expanded(
              child: rightEntry != null
                  ? _DungeonCell(run: rightEntry.value, isLeft: false)
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
          children: [
            Container(
              width: double.infinity,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(
              4,
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
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Center(
        child: Text(
          'No Mythic+ data available',
          style: GoogleFonts.dmSans(
            fontSize: 14,
            color: AppTheme.textTertiary,
          ),
        ),
      ),
    );
  }

  String _formatRating(double rating) {
    final intRating = rating.round();
    if (intRating >= 1000) {
      final thousands = intRating ~/ 1000;
      final remainder = (intRating % 1000).toString().padLeft(3, '0');
      return '$thousands,$remainder';
    }
    return intRating.toString();
  }

  Color _ensureContrast(Color color) {
    final hsl = HSLColor.fromColor(color);
    if (hsl.lightness < 0.45) {
      return hsl
          .withLightness(0.55)
          .withSaturation((hsl.saturation * 1.2).clamp(0.0, 1.0))
          .toColor();
    }
    return color;
  }
}

/// A single dungeon cell — icon + name + key level + duration.
class _DungeonCell extends StatelessWidget {
  final MythicPlusBestRun run;
  final bool isLeft;

  const _DungeonCell({required this.run, required this.isLeft});

  @override
  Widget build(BuildContext context) {
    final color = _keystoneColor(run.keystoneLevel);
    final stars = run.keystoneUpgrades > 0 ? '★' * run.keystoneUpgrades : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        textDirection: isLeft ? TextDirection.ltr : TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dungeon icon with level badge
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: color.withValues(alpha: 0.12),
                    border: Border.all(
                      color: color.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: run.iconUrl != null
                      ? CachedNetworkImage(
                          imageUrl: run.iconUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _iconFallback(color),
                          errorWidget: (_, __, ___) => _iconFallback(color),
                        )
                      : _iconFallback(color),
                ),
                // Level badge
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: color.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '+${run.keystoneLevel}',
                      style: GoogleFonts.rajdhani(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Dungeon info
          Expanded(
            child: Column(
              crossAxisAlignment:
                  isLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                // Dungeon name
                Text(
                  run.dungeonName,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  textAlign: isLeft ? TextAlign.left : TextAlign.right,
                ),
                const SizedBox(height: 3),

                // Duration + timed + stars
                Row(
                  mainAxisSize: MainAxisSize.min,
                  textDirection:
                      isLeft ? TextDirection.ltr : TextDirection.rtl,
                  children: [
                    Icon(
                      run.isTimedCompletion
                          ? Icons.check_circle
                          : Icons.cancel,
                      size: 10,
                      color: run.isTimedCompletion
                          ? const Color(0xFF1EFF00)
                          : const Color(0xFFFF4444),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(run.durationMs),
                      style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                    if (stars.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        stars,
                        style: const TextStyle(
                          fontSize: 8,
                          color: Color(0xFFFFD100),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconFallback(Color color) {
    return Container(
      color: color.withValues(alpha: 0.08),
      child: Center(
        child: Text(
          _abbr(run.dungeonName),
          style: GoogleFonts.rajdhani(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
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

  String _formatDuration(int durationMs) {
    final totalSeconds = durationMs ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Color _keystoneColor(int level) {
    if (level >= 15) return const Color(0xFFFF8000);
    if (level >= 12) return const Color(0xFFA335EE);
    if (level >= 10) return const Color(0xFF0070DD);
    if (level >= 7) return const Color(0xFF1EFF00);
    return AppTheme.textSecondary;
  }
}
