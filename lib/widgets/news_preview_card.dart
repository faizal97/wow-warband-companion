import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../models/news_article.dart';
import '../services/news_provider.dart';
import '../theme/app_theme.dart';
import '../theme/news_source_colors.dart';

class NewsPreviewCard extends StatelessWidget {
  final VoidCallback onSeeAll;
  final void Function(NewsArticle) onArticleTap;

  const NewsPreviewCard({
    super.key,
    required this.onSeeAll,
    required this.onArticleTap,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NewsProvider>();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceBorder, width: 1),
      ),
      child: _buildContent(provider),
    );
  }

  Widget _buildContent(NewsProvider provider) {
    if (provider.isLoading && provider.allArticles.isEmpty) {
      return _buildShimmer();
    }

    if (provider.allArticles.isEmpty) {
      return _buildError(provider);
    }

    return _buildLoaded(provider);
  }

  Widget _buildLoaded(NewsProvider provider) {
    final articles = provider.previewArticles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            const Icon(
              Icons.article_rounded,
              color: Color(0xFF3FC7EB),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Latest News',
              style: GoogleFonts.rajdhani(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'See all',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF3FC7EB),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Article list
        ...articles.asMap().entries.map((entry) {
          final index = entry.key;
          final article = entry.value;
          return Column(
            children: [
              if (index > 0)
                Divider(
                  color: AppTheme.surfaceBorder.withValues(alpha: 0.5),
                  height: 1,
                ),
              _buildArticleItem(article),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildArticleItem(NewsArticle article) {
    final sourceColor = NewsSourceColors.forSource(article.source);

    return GestureDetector(
      onTap: () => onArticleTap(article),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 52,
                height: 52,
                child: article.hasImage
                    ? CachedNetworkImage(
                        imageUrl: article.proxiedImageUrl!,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _buildThumbnailFallback(
                          sourceColor,
                          article.source,
                        ),
                        errorWidget: (_, __, ___) => _buildThumbnailFallback(
                          sourceColor,
                          article.source,
                        ),
                      )
                    : _buildThumbnailFallback(sourceColor, article.source),
              ),
            ),
            const SizedBox(width: 12),
            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Source badge + time ago
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: sourceColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          NewsSourceColors.displayName(article.source),
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: sourceColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
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
                  // Title (2 lines max)
                  Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                      height: 1.3,
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

  Widget _buildThumbnailFallback(Color sourceColor, String source) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            sourceColor.withValues(alpha: 0.2),
            sourceColor.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Icon(
        Icons.article_outlined,
        color: sourceColor.withValues(alpha: 0.5),
        size: 20,
      ),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: AppTheme.surface,
      highlightColor: AppTheme.surfaceElevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header shimmer
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 90,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Article item shimmers
          for (int i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 60,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        height: 13,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 140,
                        height: 13,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildError(NewsProvider provider) {
    return GestureDetector(
      onTap: () => provider.fetchNews(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.article_rounded,
                color: Color(0xFF3FC7EB),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Latest News',
                style: GoogleFonts.rajdhani(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            provider.errorMessage ?? 'News unavailable',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap to retry',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
