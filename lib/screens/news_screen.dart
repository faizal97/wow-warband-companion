import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/news_article.dart';
import '../services/news_provider.dart';
import '../theme/app_theme.dart';
import '../theme/news_source_colors.dart';
import 'article_detail_screen.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  final _searchController = TextEditingController();
  int _sortMode = 0; // 0=Latest, 1=Oldest

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NewsProvider>().fetchNews();
      context.read<RedditProvider>().fetchPosts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Consumer2<NewsProvider, RedditProvider>(
          builder: (context, newsProvider, redditProvider, _) {
            return RefreshIndicator(
              onRefresh: () async {
                await Future.wait([
                  newsProvider.refreshNews(),
                  redditProvider.refreshPosts(),
                ]);
              },
              color: const Color(0xFF3FC7EB),
              backgroundColor: AppTheme.surface,
              child: CustomScrollView(
                slivers: [
                  // Top bar
                  SliverToBoxAdapter(child: _buildTopBar()),
                  // Search
                  SliverToBoxAdapter(child: _buildSearchBar(newsProvider)),
                  // Toolbar
                  SliverToBoxAdapter(child: _buildToolbar(newsProvider)),
                  // Loading indicator
                  if (newsProvider.isLoading &&
                      newsProvider.allArticles.isEmpty)
                    SliverToBoxAdapter(child: _buildLoadingState())
                  else if (newsProvider.articles.isEmpty &&
                      !newsProvider.isLoading)
                    SliverToBoxAdapter(
                        child: _buildEmptyState(newsProvider))
                  else ...[
                    // News articles
                    _buildNewsList(newsProvider),
                  ],
                  // Reddit section
                  if (redditProvider.showReddit &&
                      redditProvider.posts.isNotEmpty) ...[
                    SliverToBoxAdapter(child: _buildRedditDivider()),
                    _buildRedditList(redditProvider),
                  ],
                  // Bottom padding
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 20, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Color(0xFF3FC7EB),
              size: 22,
            ),
          ),
          Text(
            'NEWS',
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

  Widget _buildSearchBar(NewsProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.surfaceBorder),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            const Icon(Icons.search_rounded,
                color: AppTheme.textTertiary, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (q) => provider.setSearchQuery(q),
                style: GoogleFonts.inter(
                    fontSize: 14, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search news...',
                  hintStyle: GoogleFonts.inter(
                      fontSize: 14, color: AppTheme.textTertiary),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  provider.setSearchQuery('');
                },
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.close_rounded,
                      color: AppTheme.textTertiary, size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(NewsProvider provider) {
    final filterCount = provider.activeFilterCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          // Sort button
          GestureDetector(
            onTap: () => setState(() => _sortMode = _sortMode == 0 ? 1 : 0),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.surfaceBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort_rounded,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    _sortMode == 0 ? 'Latest' : 'Oldest',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Filter button
          GestureDetector(
            onTap: () => _showFilterSheet(provider),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: filterCount > 0
                    ? const Color(0xFF3FC7EB).withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: filterCount > 0
                      ? const Color(0xFF3FC7EB).withValues(alpha: 0.3)
                      : AppTheme.surfaceBorder,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded,
                      size: 14,
                      color: filterCount > 0
                          ? const Color(0xFF3FC7EB)
                          : AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'Filters',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: filterCount > 0
                          ? const Color(0xFF3FC7EB)
                          : AppTheme.textSecondary,
                    ),
                  ),
                  if (filterCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3FC7EB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$filterCount',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.background,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Spacer(),
          Text(
            '${provider.articles.length} articles',
            style:
                GoogleFonts.inter(fontSize: 12, color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  // ─── Filter bottom sheet ─────────────────────────────────────────────────
  void _showFilterSheet(NewsProvider provider) {
    final tempSources = Set<NewsSource>.from(provider.selectedSources);
    final tempCategories =
        Set<NewsCategory>.from(provider.selectedCategories);
    final redditProvider = context.read<RedditProvider>();
    bool tempShowReddit = redditProvider.showReddit;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final totalFilters =
                tempSources.length + tempCategories.length;

            return DraggableScrollableSheet(
              initialChildSize: 0.65,
              maxChildSize: 0.85,
              minChildSize: 0.4,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Column(
                        children: [
                          Center(
                            child: Container(
                              width: 32,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceBorder,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Text(
                                'Filters',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              if (totalFilters > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3FC7EB)
                                        .withValues(alpha: 0.15),
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$totalFilters active',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFF3FC7EB),
                                    ),
                                  ),
                                ),
                              ],
                              const Spacer(),
                              if (totalFilters > 0)
                                GestureDetector(
                                  onTap: () => setSheetState(() {
                                    tempSources.clear();
                                    tempCategories.clear();
                                  }),
                                  child: Text(
                                    'Reset',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: AppTheme.textTertiary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Filter sections
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding:
                            const EdgeInsets.fromLTRB(24, 8, 24, 0),
                        children: [
                          // SOURCE
                          const _FilterSectionHeader(title: 'SOURCE'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                NewsSource.values.map((source) {
                              final sel =
                                  tempSources.contains(source);
                              final color =
                                  NewsSourceColors.forSource(
                                      source.name);
                              return _SourceFilterTag(
                                label:
                                    NewsSourceColors.displayName(
                                        source.name),
                                isSelected: sel,
                                color: color,
                                onTap: () => setSheetState(() {
                                  sel
                                      ? tempSources.remove(source)
                                      : tempSources.add(source);
                                }),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),

                          // CONTENT TYPE
                          const _FilterSectionHeader(
                              title: 'CONTENT TYPE'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: NewsCategory.values
                                .where(
                                    (c) => c != NewsCategory.all)
                                .map((cat) {
                              final sel =
                                  tempCategories.contains(cat);
                              return _FilterTag(
                                label: cat.displayName,
                                isSelected: sel,
                                color: const Color(0xFF3FC7EB),
                                onTap: () => setSheetState(() {
                                  sel
                                      ? tempCategories.remove(cat)
                                      : tempCategories.add(cat);
                                }),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),

                          // REDDIT toggle
                          const _FilterSectionHeader(
                              title: 'REDDIT'),
                          const SizedBox(height: 8),
                          _FilterTag(
                            label: 'Show r/wow posts',
                            isSelected: tempShowReddit,
                            color: NewsSourceColors.reddit,
                            onTap: () => setSheetState(() {
                              tempShowReddit = !tempShowReddit;
                            }),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),

                    // Apply button
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(24, 8, 24, 16),
                      child: SafeArea(
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: () {
                              provider.applyFilters(
                                sources: tempSources,
                                categories: tempCategories,
                              );
                              redditProvider
                                  .setShowReddit(tempShowReddit);
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF3FC7EB),
                              foregroundColor: AppTheme.background,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              totalFilters > 0
                                  ? 'Apply $totalFilters ${totalFilters == 1 ? 'Filter' : 'Filters'}'
                                  : 'Apply Filters',
                              style: GoogleFonts.rajdhani(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ─── News list ─────────────────────────────────────────────────────────
  SliverList _buildNewsList(NewsProvider provider) {
    final articles = provider.articles;
    // Group by day
    final today = DateTime.now();
    final todayArticles = articles
        .where((a) =>
            a.publishedAt.year == today.year &&
            a.publishedAt.month == today.month &&
            a.publishedAt.day == today.day)
        .toList();
    final olderArticles = articles
        .where((a) =>
            !(a.publishedAt.year == today.year &&
                a.publishedAt.month == today.month &&
                a.publishedAt.day == today.day))
        .toList();

    final items = <Widget>[];

    if (todayArticles.isNotEmpty) {
      items.add(const Padding(
        padding: EdgeInsets.fromLTRB(20, 28, 20, 12),
        child: _SectionLabel(text: 'TODAY'),
      ));
      // First article: featured card with image
      items.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _FeaturedNewsCard(
          article: todayArticles.first,
          onTap: () => _openArticle(todayArticles.first),
        ),
      ));
      // Rest: compact cards
      for (final article in todayArticles.skip(1)) {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _CompactNewsCard(
            article: article,
            onTap: () => _openArticle(article),
          ),
        ));
      }
    }

    if (olderArticles.isNotEmpty) {
      items.add(const Padding(
        padding: EdgeInsets.fromLTRB(20, 28, 20, 12),
        child: _SectionLabel(text: 'EARLIER'),
      ));
      for (final article in olderArticles) {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _CompactNewsCard(
            article: article,
            onTap: () => _openArticle(article),
          ),
        ));
      }
    }

    return SliverList(delegate: SliverChildListDelegate(items));
  }

  void _openArticle(NewsArticle article) {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => ArticleDetailScreen(article: article)),
    );
  }

  // ─── Reddit section ────────────────────────────────────────────────────
  Widget _buildRedditDivider() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
      child: Row(
        children: [
          Expanded(
              child:
                  Container(height: 1, color: AppTheme.surfaceBorder)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'R/WOW COMMUNITY',
              style: GoogleFonts.rajdhani(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textTertiary,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Expanded(
              child:
                  Container(height: 1, color: AppTheme.surfaceBorder)),
        ],
      ),
    );
  }

  SliverList _buildRedditList(RedditProvider provider) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final post = provider.posts[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _RedditCard(post: post),
          );
        },
        childCount: provider.posts.length.clamp(0, 10),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Shimmer.fromColors(
        baseColor: AppTheme.surface,
        highlightColor: AppTheme.surfaceElevated,
        child: Column(
          children: List.generate(
            3,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(NewsProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          const Icon(Icons.article_outlined,
              color: AppTheme.textTertiary, size: 48),
          const SizedBox(height: 16),
          Text(
            'No articles found',
            style: GoogleFonts.rajdhani(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            provider.hasActiveFilters
                ? 'Try adjusting your filters'
                : 'Pull down to refresh',
            style: GoogleFonts.inter(
                fontSize: 13, color: AppTheme.textTertiary),
          ),
          if (provider.hasActiveFilters) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => provider.clearFilters(),
              child: Text(
                'Clear all filters',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF3FC7EB),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Private widgets ──────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.rajdhani(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppTheme.textTertiary,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _FilterSectionHeader extends StatelessWidget {
  final String title;
  const _FilterSectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.rajdhani(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppTheme.textTertiary,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _FilterTag extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _FilterTag({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.4)
                : AppTheme.surfaceBorder,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? color : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SourceFilterTag extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _SourceFilterTag({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.4)
                : AppTheme.surfaceBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? color : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedNewsCard extends StatelessWidget {
  final NewsArticle article;
  final VoidCallback onTap;

  const _FeaturedNewsCard({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sourceColor = NewsSourceColors.forSource(article.source);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.surfaceBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            SizedBox(
              height: 140,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  article.hasImage
                      ? CachedNetworkImage(
                          imageUrl: article.proxiedImageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              _thumbFallback(sourceColor),
                          errorWidget: (_, __, ___) =>
                              _thumbFallback(sourceColor),
                        )
                      : _thumbFallback(sourceColor),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            AppTheme.surface,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _SourceBadge(source: article.source),
                      const SizedBox(width: 8),
                      _CategoryBadge(category: article.category),
                      const Spacer(),
                      Text(
                        article.timeAgo,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    article.title,
                    style: GoogleFonts.rajdhani(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  if (article.summary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      article.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.5,
                      ),
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

  Widget _thumbFallback(Color color) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.surfaceElevated,
            color.withValues(alpha: 0.12),
          ],
        ),
      ),
      child: Center(
        child: Icon(Icons.article_rounded,
            color: color.withValues(alpha: 0.2), size: 40),
      ),
    );
  }
}

class _CompactNewsCard extends StatelessWidget {
  final NewsArticle article;
  final VoidCallback onTap;

  const _CompactNewsCard({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sourceColor = NewsSourceColors.forSource(article.source);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.surfaceBorder),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 72,
                height: 72,
                child: article.hasImage
                    ? CachedNetworkImage(
                        imageUrl: article.proxiedImageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            _thumbFallback(sourceColor),
                        errorWidget: (_, __, ___) =>
                            _thumbFallback(sourceColor),
                      )
                    : _thumbFallback(sourceColor),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _SourceBadge(source: article.source),
                      const SizedBox(width: 8),
                      _CategoryBadge(category: article.category),
                      const Spacer(),
                      Text(
                        article.timeAgo,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.rajdhani(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  if (article.summary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      article.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                      ),
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

  Widget _thumbFallback(Color color) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.surfaceElevated,
            color.withValues(alpha: 0.12),
          ],
        ),
      ),
      child: Center(
        child: Icon(Icons.article_rounded,
            color: color.withValues(alpha: 0.2), size: 24),
      ),
    );
  }
}

class _RedditCard extends StatelessWidget {
  final RedditPost post;
  const _RedditCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _launchUrl(post.url),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.surfaceBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              post.title,
              style: GoogleFonts.rajdhani(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.arrow_upward_rounded,
                    size: 14, color: NewsSourceColors.reddit),
                const SizedBox(width: 2),
                Text(
                  post.formattedScore,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: NewsSourceColors.reddit,
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.chat_bubble_outline_rounded,
                    size: 14, color: AppTheme.textTertiary),
                const SizedBox(width: 4),
                Text(
                  '${post.numComments}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textTertiary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  post.timeAgo,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
                if (post.flair != null) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      post.flair!,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _launchUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _SourceBadge extends StatelessWidget {
  final String source;
  const _SourceBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    final color = NewsSourceColors.forSource(source);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        NewsSourceColors.displayName(source),
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  final String category;
  const _CategoryBadge({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        category.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AppTheme.textTertiary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
