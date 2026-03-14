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
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    final achProvider = context.read<AchievementProvider>();
    final charProvider = context.read<CharacterProvider>();

    if (forceRefresh && charProvider.hasCharacters) {
      final char = charProvider.characters.first;
      await achProvider.forceRefreshAll(char.realmSlug, char.name);
      await achProvider.loadRecentlyCompleted();
    } else {
      await achProvider.loadCategories();
      if (charProvider.hasCharacters) {
        final char = charProvider.characters.first;
        await achProvider.loadProgress(char.realmSlug, char.name);
        await achProvider.loadRecentlyCompleted();
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

                    if (_showSearch)
                      SliverToBoxAdapter(child: _buildSearchBar()),

                    if (_showSearch && _searchQuery.isNotEmpty)
                      SliverToBoxAdapter(child: _buildSearchResults(provider)),

                    if (!_showSearch || _searchQuery.isEmpty) ...[
                      if (provider.progress != null)
                        SliverToBoxAdapter(child: _buildPointsSummary(provider)),

                      if (provider.recentlyCompleted.isNotEmpty)
                        SliverToBoxAdapter(child: _buildRecentlyCompleted(provider)),

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
                    ],

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
          ),
          const Spacer(),
          IconButton(
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
            icon: Icon(
              _showSearch ? Icons.close_rounded : Icons.search_rounded,
              color: _showSearch ? AppTheme.textPrimary : AppTheme.textTertiary,
              size: 20,
            ),
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search achievements...',
          hintStyle: GoogleFonts.inter(fontSize: 14, color: AppTheme.textTertiary),
          prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textTertiary, size: 18),
          filled: true,
          fillColor: AppTheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.surfaceBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.surfaceBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF3FC7EB), width: 1),
          ),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  Widget _buildSearchResults(AchievementProvider provider) {
    final results = provider.searchAchievements(_searchQuery);
    final cacheSize = provider.searchableCacheSize;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Text(
                _searchQuery.length < 2
                    ? 'Type at least 2 characters...'
                    : 'No results found',
                style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textTertiary),
              ),
            ),
          ),
        for (final result in results)
          _SearchResultTile(
            result: result,
            progress: provider.progress,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AchievementListScreen(
                    categoryId: result.categoryId,
                    categoryName: result.categoryPath,
                    highlightAchievementId: result.achievement.id,
                  ),
                ),
              );
            },
          ),
        if (results.isNotEmpty || _searchQuery.length >= 2)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Text(
              'Searched $cacheSize cached achievements. Browse more categories to expand search.',
              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textTertiary),
            ),
          ),
      ],
    );
  }

  Widget _buildRecentlyCompleted(AchievementProvider provider) {
    if (provider.recentlyCompleted.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.surfaceBorder, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RECENT',
              style: GoogleFonts.rajdhani(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textTertiary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            for (final display in provider.recentlyCompleted) ...[
              _RecentAchievementRow(display: display),
              if (display != provider.recentlyCompleted.last)
                Divider(color: AppTheme.surfaceBorder, height: 16, thickness: 0.5),
            ],
          ],
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

class _SearchResultTile extends StatelessWidget {
  final AchievementSearchResult result;
  final AccountAchievementProgress? progress;
  final VoidCallback onTap;

  const _SearchResultTile({required this.result, this.progress, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ach = result.achievement;
    final entry = progress?.achievements[ach.id];
    final isCompleted = entry?.isCompleted ?? false;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.surfaceBorder, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ach.name,
                    style: GoogleFonts.rajdhani(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    result.categoryPath,
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textTertiary),
                  ),
                ],
              ),
            ),
            if (isCompleted)
              const Icon(Icons.check_circle_rounded, color: Color(0xFF1EFF00), size: 16)
            else
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _RecentAchievementRow extends StatelessWidget {
  final AchievementDisplay display;

  const _RecentAchievementRow({required this.display});

  String _formatRelativeDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD100), size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            display.achievement.name,
            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (display.achievement.points > 0) ...[
          Text(
            '${display.achievement.points}',
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFFFD100),
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (display.completedTimestamp != null)
          Text(
            _formatRelativeDate(display.completedTimestamp!),
            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textTertiary),
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}
