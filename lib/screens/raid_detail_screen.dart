import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/raid_progression.dart';
import '../services/character_detail_provider.dart';
import '../theme/app_theme.dart';

/// Full-screen raid encounter journal showing boss list with images.
class RaidDetailScreen extends StatefulWidget {
  final int raidInstanceId;
  final String expansionName;

  const RaidDetailScreen({
    super.key,
    required this.raidInstanceId,
    required this.expansionName,
  });

  @override
  State<RaidDetailScreen> createState() => _RaidDetailScreenState();
}

class _RaidDetailScreenState extends State<RaidDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CharacterDetailProvider>().loadBossIcons(widget.raidInstanceId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CharacterDetailProvider>(
      builder: (context, provider, _) {
        final raid = provider.raidProgression?.instances
                .where((i) => i.id == widget.raidInstanceId)
                .firstOrNull ??
            const RaidInstance(
                name: 'Unknown', id: 0, encounters: [], difficulties: []);

        final accentColor = _highestDifficultyColor(raid);

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                await DefaultCacheManager().emptyCache();
                await provider.forceRefreshBossIcons(widget.raidInstanceId);
              },
              color: accentColor,
              backgroundColor: AppTheme.surface,
              child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Top bar
                SliverToBoxAdapter(
                  child: _buildTopBar(context, accentColor),
                ),

                // Raid header with icon and progress
                SliverToBoxAdapter(
                  child: _buildRaidHeader(raid, accentColor),
                ),

                // Encounters label
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 14,
                          decoration: BoxDecoration(
                            color: accentColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'ENCOUNTERS',
                          style: GoogleFonts.rajdhani(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textTertiary,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const Spacer(),
                        // Difficulty legend
                        ..._buildDifficultyLegend(raid),
                      ],
                    ),
                  ),
                ),

                // Boss list
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildBossCard(
                      raid.encounters[index],
                      raid.difficulties.map((d) => d.type).toList(),
                      accentColor,
                      index,
                    ),
                    childCount: raid.encounters.length,
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
      },
    );
  }

  Widget _buildTopBar(BuildContext context, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 20, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: accentColor,
              size: 22,
            ),
          ),
          Text(
            'RAID',
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

  Widget _buildRaidHeader(RaidInstance raid, Color accentColor) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Accent bar
          Container(height: 2, color: accentColor),

          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accentColor.withValues(alpha: 0.08),
                  AppTheme.surface,
                  AppTheme.surface,
                ],
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Raid icon (larger for detail screen)
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                    color: accentColor.withValues(alpha: 0.08),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.15),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: raid.iconUrl != null
                      ? CachedNetworkImage(
                          imageUrl: raid.iconUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              _raidIconFallback(raid.name, accentColor),
                          errorWidget: (_, __, ___) =>
                              _raidIconFallback(raid.name, accentColor),
                        )
                      : _raidIconFallback(raid.name, accentColor),
                ),
                const SizedBox(width: 14),

                // Raid info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.expansionName.toUpperCase(),
                        style: GoogleFonts.rajdhani(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textTertiary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        raid.name,
                        style: GoogleFonts.rajdhani(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Difficulty badges
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: raid.difficulties.map((diff) {
                          final color = _difficultyColor(diff.type);
                          final hasProgress = diff.completedCount > 0;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: hasProgress
                                  ? color.withValues(alpha: 0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: hasProgress
                                    ? color.withValues(alpha: 0.35)
                                    : AppTheme.surfaceBorder,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '${diff.completedCount}/${diff.totalCount} ${diff.name}',
                              style: GoogleFonts.rajdhani(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: hasProgress
                                    ? color
                                    : AppTheme.textTertiary,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDifficultyLegend(RaidInstance raid) {
    final diffs = raid.difficulties.map((d) => d.type).toList();
    return diffs.map((d) {
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Text(
          _difficultyLabel(d),
          style: GoogleFonts.rajdhani(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _difficultyColor(d).withValues(alpha: 0.7),
            letterSpacing: 0.5,
          ),
        ),
      );
    }).toList();
  }

  Widget _buildBossCard(
    RaidEncounter encounter,
    List<String> diffs,
    Color accentColor,
    int index,
  ) {
    final bossAccent = _highestKilledDifficultyColor(encounter, diffs);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: bossAccent.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          // Boss image
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              fit: StackFit.expand,
              children: [
                encounter.iconUrl != null
                    ? CachedNetworkImage(
                        imageUrl: encounter.iconUrl!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        placeholder: (_, __) =>
                            _bossPlaceholder(encounter.name, bossAccent),
                        errorWidget: (_, __, ___) =>
                            _bossPlaceholder(encounter.name, bossAccent),
                      )
                    : _bossPlaceholder(encounter.name, bossAccent),
                // Gradient overlay on right edge for smooth transition
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 20,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          AppTheme.surface,
                        ],
                      ),
                    ),
                  ),
                ),
                // Boss number badge
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppTheme.background.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: bossAccent.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: GoogleFonts.rajdhani(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: bossAccent,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 4),

          // Boss info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    encounter.name,
                    style: GoogleFonts.rajdhani(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                      height: 1.1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Kill badges per difficulty
                  Row(
                    children: diffs.map((d) {
                      final killed = encounter.isKilledOn(d);
                      final kills = encounter.killsOn(d);
                      final color = _difficultyColor(d);

                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: killed
                                ? color.withValues(alpha: 0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: killed
                                  ? color.withValues(alpha: 0.35)
                                  : AppTheme.surfaceBorder,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _difficultyLabel(d),
                                style: GoogleFonts.rajdhani(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: killed
                                      ? color
                                      : AppTheme.textTertiary,
                                ),
                              ),
                              if (killed) ...[
                                const SizedBox(width: 3),
                                Text(
                                  '$kills',
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: color.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _raidIconFallback(String name, Color color) {
    return Container(
      color: color.withValues(alpha: 0.08),
      child: Center(
        child: Text(
          _abbr(name),
          style: GoogleFonts.rajdhani(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _bossPlaceholder(String name, Color color) {
    return Container(
      color: color.withValues(alpha: 0.06),
      child: Center(
        child: Icon(
          Icons.shield_outlined,
          size: 24,
          color: color.withValues(alpha: 0.2),
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

  Color _highestKilledDifficultyColor(
      RaidEncounter encounter, List<String> diffs) {
    const order = ['MYTHIC', 'HEROIC', 'NORMAL', 'LFR'];
    for (final diff in order) {
      if (diffs.contains(diff) && encounter.isKilledOn(diff)) {
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
