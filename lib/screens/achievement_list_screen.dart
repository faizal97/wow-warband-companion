import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../models/achievement.dart';
import '../services/achievement_provider.dart';
import '../theme/app_theme.dart';

enum AchievementFilter { all, inProgress, done }

class AchievementListScreen extends StatefulWidget {
  final int categoryId;
  final String categoryName;
  final String? parentCategoryName;
  final int? highlightAchievementId;

  const AchievementListScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.parentCategoryName,
    this.highlightAchievementId,
  });

  @override
  State<AchievementListScreen> createState() => _AchievementListScreenState();
}

class _AchievementListScreenState extends State<AchievementListScreen> {
  AchievementFilter _filter = AchievementFilter.all;
  int? _highlightAchievementId;

  @override
  void initState() {
    super.initState();
    _highlightAchievementId = widget.highlightAchievementId;
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

              // Split incomplete into "almost there" and regular
              List<AchievementDisplay> almostThere = [];
              List<AchievementDisplay> inProgress = [];
              if (merged != null) {
                for (final d in merged.incomplete) {
                  if (d.totalCriteria > 0 && d.completedCriteria / d.totalCriteria >= 0.5) {
                    almostThere.add(d);
                  } else {
                    inProgress.add(d);
                  }
                }
                almostThere.sort((a, b) {
                  final aRatio = a.totalCriteria > 0 ? a.completedCriteria / a.totalCriteria : 0.0;
                  final bRatio = b.totalCriteria > 0 ? b.completedCriteria / b.totalCriteria : 0.0;
                  return bRatio.compareTo(aRatio);
                });
                if (almostThere.length > 5) almostThere = almostThere.sublist(0, 5);
              }

              final showAlmostThere = _filter != AchievementFilter.done;
              final showInProgress = _filter != AchievementFilter.done;
              final showCompleted = _filter != AchievementFilter.inProgress;

              // Find highlighted achievement for search
              AchievementDisplay? highlighted;
              if (_highlightAchievementId != null && merged != null) {
                for (final d in [...almostThere, ...inProgress, ...(merged.completed)]) {
                  if (d.achievement.id == _highlightAchievementId) {
                    highlighted = d;
                    break;
                  }
                }
              }

              return RefreshIndicator(
                onRefresh: () => provider.forceRefreshCategory(widget.categoryId),
                color: const Color(0xFF3FC7EB),
                backgroundColor: AppTheme.surface,
                child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader()),

                  // Filter chips
                  if (!isLoading && merged != null)
                    SliverToBoxAdapter(child: _buildFilterChips()),

                  if (isLoading)
                    SliverToBoxAdapter(child: _buildLoadingShimmer()),

                  // Highlighted search result
                  if (!isLoading && highlighted != null) ...[
                    SliverToBoxAdapter(
                      child: _buildSectionHeader('SEARCH RESULT'),
                    ),
                    SliverToBoxAdapter(
                      child: _HighlightedAchievementCard(
                        display: highlighted,
                        onTap: () => _showDetail(highlighted!),
                      ),
                    ),
                  ],

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
                                  parentCategoryName: widget.parentCategoryName != null
                                      ? '${widget.parentCategoryName} > ${widget.categoryName}'
                                      : widget.categoryName,
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: category.subcategories.length,
                      ),
                    ),
                  ],

                  // Almost there
                  if (!isLoading && showAlmostThere && almostThere.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _buildSectionHeader('ALMOST THERE', count: almostThere.length),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _AchievementRichCard(
                          display: almostThere[index],
                          onTap: () => _showDetail(almostThere[index]),
                          highlight: true,
                        ),
                        childCount: almostThere.length,
                      ),
                    ),
                  ],

                  // In progress
                  if (!isLoading && showInProgress && inProgress.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _buildSectionHeader('IN PROGRESS', count: inProgress.length),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _AchievementRichCard(
                          display: inProgress[index],
                          onTap: () => _showDetail(inProgress[index]),
                        ),
                        childCount: inProgress.length,
                      ),
                    ),
                  ],

                  // Completed
                  if (!isLoading && showCompleted && merged != null && merged.completed.isNotEmpty) ...[
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
              ),
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
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: AppTheme.textSecondary,
              size: 22,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.parentCategoryName != null)
                  Text(
                    widget.parentCategoryName!,
                    style: GoogleFonts.rajdhani(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textTertiary,
                      letterSpacing: 1.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                Text(
                  widget.categoryName,
                  style: GoogleFonts.rajdhani(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    height: 1.0,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: AchievementFilter.values.map((filter) {
          final isActive = _filter == filter;
          final label = switch (filter) {
            AchievementFilter.all => 'All',
            AchievementFilter.inProgress => 'In Progress',
            AchievementFilter.done => 'Done',
          };
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filter = filter),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF3FC7EB).withValues(alpha: 0.1)
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFF3FC7EB).withValues(alpha: 0.3)
                        : AppTheme.surfaceBorder,
                    width: 1,
                  ),
                ),
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? const Color(0xFF3FC7EB)
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
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
  final bool highlight;

  const _AchievementRichCard({required this.display, required this.onTap, this.highlight = false});

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
          border: Border.all(
            color: highlight ? const Color(0xFFFFD100).withValues(alpha: 0.4) : AppTheme.surfaceBorder,
            width: 1,
          ),
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
                overflow: TextOverflow.ellipsis,
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

class _HighlightedAchievementCard extends StatelessWidget {
  final AchievementDisplay display;
  final VoidCallback onTap;

  const _HighlightedAchievementCard({required this.display, required this.onTap});

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
          color: const Color(0xFFFFD100).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFFFD100).withValues(alpha: 0.5),
            width: 1.5,
          ),
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
                      if (display.isCompleted) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.check_circle_rounded, color: Color(0xFF1EFF00), size: 16),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ach.description,
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasProgress && !display.isCompleted) ...[
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

class _AchievementDetailSheet extends StatelessWidget {
  final AchievementDisplay display;
  final AchievementDisplay? parentDisplay;

  const _AchievementDetailSheet({
    required this.display,
    this.parentDisplay,
  });

  @override
  Widget build(BuildContext context) {
    final ach = display.achievement;
    final provider = context.read<AchievementProvider>();
    final categoryInfo = provider.findAchievementCategory(ach.id);

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
                // Drag handle
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
                const SizedBox(height: 12),

                // Back to parent + View in category
                Row(
                  children: [
                    if (parentDisplay != null)
                      Flexible(
                        child: GestureDetector(
                          onTap: () => _goBackToParent(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.surfaceBorder, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.arrow_back_rounded, color: AppTheme.textSecondary, size: 14),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    parentDisplay!.achievement.name,
                                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (parentDisplay != null && categoryInfo != null)
                      const SizedBox(width: 8),
                    if (categoryInfo != null && parentDisplay != null)
                      Flexible(
                        child: GestureDetector(
                          onTap: () => _viewInCategory(context, categoryInfo.categoryId, categoryInfo.categoryName),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3FC7EB).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF3FC7EB).withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'View in category',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF3FC7EB),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_forward_rounded, color: Color(0xFF3FC7EB), size: 14),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Achievement header
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
                  // Criteria header with progress count
                  Row(
                    children: [
                      Text(
                        'CRITERIA',
                        style: GoogleFonts.rajdhani(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textTertiary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      if (display.totalCriteria > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${display.completedCriteria}/${display.totalCriteria}',
                          style: GoogleFonts.rajdhani(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFFFD100),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildCriteriaTree(context, ach.criteria!, display.criteriaProgress, 0),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCriteriaTree(BuildContext context,
      AchievementCriteria criteria, Map<int, bool> progress, int depth) {
    final children = criteria.childCriteria;

    if (children.isEmpty) {
      final isCompleted = progress[criteria.id] ?? false;
      if (criteria.isMetaCriterion) {
        return _MetaCriterionCard(
          description: criteria.linkedAchievementName ?? criteria.description,
          isCompleted: isCompleted,
          depth: depth,
          onTap: () => _openLinkedAchievement(context, criteria.linkedAchievementId!),
        );
      }
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
        if (criteria.isMetaCriterion) ...[
          _MetaCriterionCard(
            description: criteria.linkedAchievementName ?? criteria.description,
            isCompleted: progress[criteria.id] ?? false,
            depth: depth,
            onTap: () => _openLinkedAchievement(context, criteria.linkedAchievementId!),
          ),
        ] else if (criteria.description.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.only(left: depth * 12.0, bottom: 4, top: depth > 0 ? 8 : 0),
            child: Text(
              criteria.description,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
        for (final child in children)
          _buildCriteriaTree(context, child, progress,
              depth + (criteria.description.isNotEmpty ? 1 : 0)),
      ],
    );
  }

  void _openLinkedAchievement(BuildContext context, int achievementId) async {
    final provider = context.read<AchievementProvider>();
    final progress = provider.progress;

    final ach = await provider.fetchAchievement(achievementId);
    if (ach == null) return;

    final entry = progress?.achievements[achievementId];
    final isCompleted = entry?.isCompleted ?? false;

    int completedCriteria = 0;
    int totalCriteria = 0;
    if (ach.criteria != null && ach.criteria!.childCriteria.isNotEmpty) {
      totalCriteria = ach.criteria!.childCriteria.length;
      for (final child in ach.criteria!.childCriteria) {
        if (entry?.criteriaProgress[child.id] == true) {
          completedCriteria++;
        }
      }
    }

    final linkedDisplay = AchievementDisplay(
      achievement: ach,
      isCompleted: isCompleted,
      completedTimestamp: entry?.completedTimestamp,
      criteriaProgress: entry?.criteriaProgress ?? {},
      completedCriteria: completedCriteria,
      totalCriteria: totalCriteria,
    );

    if (!context.mounted) return;

    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AchievementDetailSheet(
        display: linkedDisplay,
        parentDisplay: display,
      ),
    );
  }

  void _goBackToParent(BuildContext context) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AchievementDetailSheet(display: parentDisplay!),
    );
  }

  void _viewInCategory(BuildContext context, int categoryId, String categoryName) {
    Navigator.pop(context); // close the sheet
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AchievementListScreen(
          categoryId: categoryId,
          categoryName: categoryName,
          highlightAchievementId: display.achievement.id,
        ),
      ),
    );
  }
}

/// Regular criterion row — touch-friendly with 44px min height.
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
      padding: EdgeInsets.only(left: depth * 12.0),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isCompleted
              ? const Color(0xFF1EFF00).withValues(alpha: 0.04)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCompleted
                    ? const Color(0xFF1EFF00).withValues(alpha: 0.15)
                    : AppTheme.surfaceBorder.withValues(alpha: 0.5),
              ),
              child: Icon(
                isCompleted
                    ? Icons.check_rounded
                    : Icons.remove_rounded,
                color: isCompleted
                    ? const Color(0xFF1EFF00)
                    : AppTheme.textTertiary,
                size: 14,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                description,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isCompleted
                      ? AppTheme.textSecondary
                      : AppTheme.textPrimary,
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                  decorationColor: AppTheme.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Meta-criterion card — tappable card that links to another achievement.
/// Always tappable, even when completed.
class _MetaCriterionCard extends StatelessWidget {
  final String description;
  final bool isCompleted;
  final int depth;
  final VoidCallback onTap;

  const _MetaCriterionCard({
    required this.description,
    required this.isCompleted,
    required this.depth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: isCompleted
                ? const Color(0xFF1EFF00).withValues(alpha: 0.04)
                : const Color(0xFF3FC7EB).withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCompleted
                  ? const Color(0xFF1EFF00).withValues(alpha: 0.15)
                  : const Color(0xFF3FC7EB).withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? const Color(0xFF1EFF00).withValues(alpha: 0.15)
                      : const Color(0xFF3FC7EB).withValues(alpha: 0.12),
                ),
                child: Icon(
                  isCompleted
                      ? Icons.check_rounded
                      : Icons.emoji_events_outlined,
                  color: isCompleted
                      ? const Color(0xFF1EFF00)
                      : const Color(0xFF3FC7EB),
                  size: 14,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      description,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isCompleted
                            ? AppTheme.textSecondary
                            : const Color(0xFF3FC7EB),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Tap to view achievement',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: isCompleted
                            ? AppTheme.textTertiary
                            : const Color(0xFF3FC7EB).withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: isCompleted
                    ? AppTheme.textTertiary
                    : const Color(0xFF3FC7EB),
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
