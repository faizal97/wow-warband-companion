import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../models/achievement.dart';
import '../services/achievement_provider.dart';
import '../theme/app_theme.dart';

class AchievementListScreen extends StatefulWidget {
  final int categoryId;
  final String categoryName;

  const AchievementListScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<AchievementListScreen> createState() => _AchievementListScreenState();
}

class _AchievementListScreenState extends State<AchievementListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AchievementProvider>().loadCategoryDetails(widget.categoryId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.3, 1.0],
            colors: [
              Color(0xFF101018),
              AppTheme.background,
              AppTheme.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Consumer<AchievementProvider>(
            builder: (context, provider, _) {
              final isLoading = provider.isCategoryLoading(widget.categoryId);
              final category = provider.getCategoryDetails(widget.categoryId);
              final merged = provider.getMergedAchievements(widget.categoryId);

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader()),

                  if (isLoading)
                    SliverToBoxAdapter(child: _buildLoadingShimmer()),

                  // Subcategories
                  if (!isLoading && category != null && category.subcategories.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _buildSectionHeader('SUBCATEGORIES'),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final sub = category.subcategories[index];
                          return _SubcategoryTile(
                            subcategory: sub,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AchievementListScreen(
                                  categoryId: sub.id,
                                  categoryName: sub.name,
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: category.subcategories.length,
                      ),
                    ),
                  ],

                  // Incomplete achievements (rich cards)
                  if (!isLoading && merged != null && merged.incomplete.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _buildSectionHeader('IN PROGRESS', count: merged.incomplete.length),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _AchievementRichCard(
                          display: merged.incomplete[index],
                          onTap: () => _showDetail(merged.incomplete[index]),
                        ),
                        childCount: merged.incomplete.length,
                      ),
                    ),
                  ],

                  // Completed achievements (compact tiles)
                  if (!isLoading && merged != null && merged.completed.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _buildSectionHeader('COMPLETED', count: merged.completed.length),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _AchievementCompactTile(
                          display: merged.completed[index],
                          onTap: () => _showDetail(merged.completed[index]),
                        ),
                        childCount: merged.completed.length,
                      ),
                    ),
                  ],

                  // Empty state
                  if (!isLoading &&
                      merged != null &&
                      merged.completed.isEmpty &&
                      merged.incomplete.isEmpty &&
                      (category == null || category.subcategories.isEmpty))
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Text(
                            'No achievements in this category',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: AppTheme.textSecondary,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              widget.categoryName,
              style: GoogleFonts.rajdhani(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                height: 1.0,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String label, {int? count}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textTertiary,
              letterSpacing: 1.5,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text(
              '($count)',
              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: List.generate(
          4,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Shimmer.fromColors(
              baseColor: AppTheme.surfaceElevated,
              highlightColor: AppTheme.surfaceBorder,
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDetail(AchievementDisplay display) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AchievementDetailSheet(display: display),
    );
  }
}

class _SubcategoryTile extends StatelessWidget {
  final AchievementCategoryRef subcategory;
  final VoidCallback onTap;

  const _SubcategoryTile({required this.subcategory, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.surfaceBorder, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                subcategory.name,
                style: GoogleFonts.rajdhani(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _AchievementRichCard extends StatelessWidget {
  final AchievementDisplay display;
  final VoidCallback onTap;

  const _AchievementRichCard({required this.display, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ach = display.achievement;
    final hasProgress = display.totalCriteria > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.surfaceBorder, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AchievementIcon(iconUrl: ach.iconUrl, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ach.name,
                          style: GoogleFonts.rajdhani(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      _PointsBadge(points: ach.points),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ach.description,
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasProgress) ...[
                    const SizedBox(height: 10),
                    _CriteriaProgressBar(
                      completed: display.completedCriteria,
                      total: display.totalCriteria,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementCompactTile extends StatelessWidget {
  final AchievementDisplay display;
  final VoidCallback onTap;

  const _AchievementCompactTile({required this.display, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ach = display.achievement;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.surfaceBorder, width: 1),
        ),
        child: Row(
          children: [
            _AchievementIcon(iconUrl: ach.iconUrl, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                ach.name,
                style: GoogleFonts.rajdhani(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _PointsBadge(points: ach.points),
            const SizedBox(width: 10),
            const Icon(Icons.check_circle_rounded, color: Color(0xFF1EFF00), size: 18),
            if (display.formattedDate != null) ...[
              const SizedBox(width: 8),
              Text(
                display.formattedDate!,
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AchievementIcon extends StatelessWidget {
  final String? iconUrl;
  final double size;

  const _AchievementIcon({this.iconUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    if (iconUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: iconUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => _placeholder(),
          errorWidget: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.surfaceBorder, width: 1),
      ),
      child: Icon(
        Icons.emoji_events_outlined,
        color: AppTheme.textTertiary,
        size: size * 0.5,
      ),
    );
  }
}

class _PointsBadge extends StatelessWidget {
  final int points;

  const _PointsBadge({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD100).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$points',
        style: GoogleFonts.rajdhani(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFFFD100),
        ),
      ),
    );
  }
}

class _CriteriaProgressBar extends StatelessWidget {
  final int completed;
  final int total;

  const _CriteriaProgressBar({required this.completed, required this.total});

  @override
  Widget build(BuildContext context) {
    final fraction = total > 0 ? completed / total : 0.0;

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              backgroundColor: AppTheme.surfaceBorder,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF3FC7EB)),
              minHeight: 4,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$completed/$total',
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _AchievementDetailSheet extends StatelessWidget {
  final AchievementDisplay display;

  const _AchievementDetailSheet({required this.display});

  @override
  Widget build(BuildContext context) {
    final ach = display.achievement;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AchievementIcon(iconUrl: ach.iconUrl, size: 56),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ach.name,
                            style: GoogleFonts.rajdhani(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _PointsBadge(points: ach.points),
                              if (display.isCompleted) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.check_circle_rounded,
                                    color: Color(0xFF1EFF00), size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  display.formattedDate ?? 'Completed',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF1EFF00),
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
                const SizedBox(height: 16),

                Text(
                  ach.description,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),

                if (ach.criteria != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'CRITERIA',
                    style: GoogleFonts.rajdhani(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textTertiary,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildCriteriaTree(ach.criteria!, display.criteriaProgress, 0),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCriteriaTree(
      AchievementCriteria criteria, Map<int, bool> progress, int depth) {
    final children = criteria.childCriteria;

    if (children.isEmpty) {
      final isCompleted = progress[criteria.id] ?? false;
      return _CriterionRow(
        description: criteria.description.isNotEmpty
            ? criteria.description
            : 'Criterion #${criteria.id}',
        isCompleted: isCompleted,
        depth: depth,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (criteria.description.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: depth * 16.0, bottom: 4),
            child: Text(
              criteria.description,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        for (final child in children)
          _buildCriteriaTree(child, progress,
              depth + (criteria.description.isNotEmpty ? 1 : 0)),
      ],
    );
  }
}

class _CriterionRow extends StatelessWidget {
  final String description;
  final bool isCompleted;
  final int depth;

  const _CriterionRow({
    required this.description,
    required this.isCompleted,
    required this.depth,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0, top: 2, bottom: 2),
      child: Row(
        children: [
          Icon(
            isCompleted
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: isCompleted ? const Color(0xFF1EFF00) : AppTheme.textTertiary,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              description,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isCompleted ? AppTheme.textSecondary : AppTheme.textPrimary,
                decoration: isCompleted ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
