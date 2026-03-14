import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../models/achievement.dart';
import '../services/achievement_provider.dart';
import '../services/character_provider.dart';
import '../theme/app_theme.dart';
import 'achievement_list_screen.dart';

class AchievementCategoryScreen extends StatefulWidget {
  const AchievementCategoryScreen({super.key});

  @override
  State<AchievementCategoryScreen> createState() => _AchievementCategoryScreenState();
}

class _AchievementCategoryScreenState extends State<AchievementCategoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    final achProvider = context.read<AchievementProvider>();
    final charProvider = context.read<CharacterProvider>();

    if (forceRefresh && charProvider.hasCharacters) {
      final char = charProvider.characters.first;
      await achProvider.forceRefreshAll(char.realmSlug, char.name);
    } else {
      await achProvider.loadCategories();
      if (charProvider.hasCharacters) {
        final char = charProvider.characters.first;
        await achProvider.loadProgress(char.realmSlug, char.name);
      }
    }
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
              return RefreshIndicator(
                onRefresh: () => _loadData(forceRefresh: true),
                color: const Color(0xFF3FC7EB),
                backgroundColor: AppTheme.surface,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),

                    if (provider.progress != null)
                      SliverToBoxAdapter(child: _buildPointsSummary(provider)),

                    if (provider.isCategoriesLoading)
                      SliverToBoxAdapter(child: _buildLoadingShimmer()),

                    if (provider.error != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                            child: Text(
                              provider.error!,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: AppTheme.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ),

                    if (!provider.isCategoriesLoading)
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final cat = provider.topCategories[index];
                            return _CategoryTile(
                              category: cat,
                              counts: provider.getCategoryCounts(cat.id),
                              onTap: () => _openCategory(cat),
                            );
                          },
                          childCount: provider.topCategories.length,
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
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: AppTheme.textSecondary,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WOW WARBAND',
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textTertiary,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Achievements',
                style: GoogleFonts.rajdhani(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPointsSummary(AchievementProvider provider) {
    final progress = provider.progress!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.surfaceBorder, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD100).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                color: Color(0xFFFFD100),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${progress.totalPoints}',
                  style: GoogleFonts.rajdhani(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    height: 1.0,
                  ),
                ),
                Text(
                  'Achievement Points',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${progress.totalQuantity}',
                  style: GoogleFonts.rajdhani(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                    height: 1.0,
                  ),
                ),
                Text(
                  'Completed',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: List.generate(
          6,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Shimmer.fromColors(
              baseColor: AppTheme.surfaceElevated,
              highlightColor: AppTheme.surfaceBorder,
              child: Container(
                height: 60,
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

  void _openCategory(AchievementCategoryRef category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AchievementListScreen(
          categoryId: category.id,
          categoryName: category.name,
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final AchievementCategoryRef category;
  final ({int completed, int total})? counts;
  final VoidCallback onTap;

  const _CategoryTile({required this.category, this.counts, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
          children: [
            Expanded(
              child: Text(
                category.name,
                style: GoogleFonts.rajdhani(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            if (counts != null) ...[
              Text(
                '${counts!.completed}/${counts!.total}',
                style: GoogleFonts.rajdhani(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFFFD100),
                ),
              ),
              const SizedBox(width: 12),
            ],
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
