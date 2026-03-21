import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/news_article.dart';
import '../services/news_provider.dart';
import '../theme/app_theme.dart';
import '../theme/news_source_colors.dart';

class ArticleDetailScreen extends StatefulWidget {
  final NewsArticle article;

  const ArticleDetailScreen({super.key, required this.article});

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  String? _fullContent;
  String? _heroImage;
  bool _isLoadingContent = false;

  @override
  void initState() {
    super.initState();
    _loadFullContent();
  }

  Future<void> _loadFullContent() async {
    // If the article already has substantial inline content from RSS, use it directly
    // (Wowhead RSS only has truncated excerpts, always fetch full for those)
    if (widget.article.content.length > 500 && widget.article.source != 'wowhead') {
      setState(() {
        _fullContent = widget.article.content;
        _heroImage = widget.article.imageUrl;
        _isLoadingContent = false;
      });
      return;
    }

    // Otherwise fetch from the /news/article endpoint
    setState(() => _isLoadingContent = true);
    try {
      final provider = context.read<NewsProvider>();
      final result = await provider.fetchArticleContent(widget.article.url);
      if (result != null && mounted) {
        setState(() {
          _fullContent = result['content'] as String? ?? '';
          _heroImage = result['imageUrl'] as String? ?? widget.article.imageUrl;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingContent = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    final sourceColor = NewsSourceColors.forSource(article.source);
    final rawHeroUrl = _heroImage ?? article.imageUrl;
    final heroUrl = rawHeroUrl != null ? _proxyIfNeeded(rawHeroUrl) : null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                // Top bar
                SliverToBoxAdapter(child: _buildTopBar()),
                // Article content
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Source + category + date
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: sourceColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                NewsSourceColors.displayName(article.source),
                                style: GoogleFonts.inter(
                                  fontSize: 10, fontWeight: FontWeight.w600,
                                  color: sourceColor, letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                article.category.toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 10, fontWeight: FontWeight.w500,
                                  color: AppTheme.textTertiary, letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(article.publishedAt),
                              style: GoogleFonts.inter(
                                fontSize: 12, color: AppTheme.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Title
                        Text(
                          article.title,
                          style: GoogleFonts.rajdhani(
                            fontSize: 26, fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                            height: 1.15, letterSpacing: -0.3,
                          ),
                        ),
                        // Author
                        if (article.author != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'By ${article.author}',
                            style: GoogleFonts.inter(
                              fontSize: 13, color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        // Hero image
                        if (heroUrl != null && heroUrl.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: double.infinity,
                              height: 200,
                              decoration: BoxDecoration(
                                border: Border.all(color: AppTheme.surfaceBorder),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: CachedNetworkImage(
                                imageUrl: heroUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  color: AppTheme.surfaceElevated,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF3FC7EB),
                                    ),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color: AppTheme.surfaceElevated,
                                ),
                              ),
                            ),
                          ),
                        if (heroUrl != null && heroUrl.isNotEmpty)
                          const SizedBox(height: 24),
                        // Article body
                        if (_isLoadingContent)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(40),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF3FC7EB),
                              ),
                            ),
                          )
                        else
                          _buildArticleBody(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Open in browser FAB
            Positioned(
              bottom: 24,
              right: 20,
              child: GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse(article.url),
                  mode: LaunchMode.inAppBrowserView,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3FC7EB),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3FC7EB).withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.open_in_new_rounded, size: 18, color: Color(0xFF0D0D14)),
                      const SizedBox(width: 8),
                      Text(
                        'Open in Browser',
                        style: GoogleFonts.rajdhani(
                          fontSize: 14, fontWeight: FontWeight.w700,
                          color: const Color(0xFF0D0D14),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF3FC7EB), size: 22),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {
              // Share functionality — could use share_plus
            },
            icon: const Icon(Icons.share_rounded, color: AppTheme.textSecondary, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildArticleBody() {
    final content = _fullContent ?? widget.article.summary;
    if (content.isEmpty) {
      return Column(
        children: [
          Text(
            widget.article.summary.isNotEmpty
                ? widget.article.summary
                : 'Full article content is available on the source website.',
            style: GoogleFonts.inter(
              fontSize: 15, color: AppTheme.textSecondary, height: 1.75,
            ),
          ),
        ],
      );
    }

    // If content is HTML, strip tags for clean reader mode
    final cleanText = content
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<p[^>]*>'), '\n')
        .replaceAll('</p>', '\n')
        .replaceAll(RegExp(r'<h[1-6][^>]*>'), '\n### ')
        .replaceAll(RegExp(r'</h[1-6]>'), '\n')
        .replaceAll(RegExp(r'<li[^>]*>'), '\n• ')
        .replaceAll(RegExp(r'</li>'), '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();

    // Split into paragraphs and render
    final paragraphs = cleanText.split(RegExp(r'\n\n+'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: paragraphs.map((p) {
        final trimmed = p.trim();
        if (trimmed.isEmpty) return const SizedBox.shrink();

        if (trimmed.startsWith('### ')) {
          return Padding(
            padding: const EdgeInsets.only(top: 28, bottom: 10),
            child: Text(
              trimmed.substring(4),
              style: GoogleFonts.rajdhani(
                fontSize: 19, fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            trimmed,
            style: GoogleFonts.inter(
              fontSize: 15, color: AppTheme.textSecondary, height: 1.75,
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  static String _proxyIfNeeded(String url) {
    const blockedDomains = ['zamimg.com', 'wow.zamimg.com', 'static.icy-veins.com', 'wp.icy-veins.com'];
    final uri = Uri.tryParse(url);
    if (uri != null && blockedDomains.any((d) => uri.host.contains(d))) {
      return '${const String.fromEnvironment('AUTH_PROXY_URL', defaultValue: 'https://wow-companion-auth.fayz.workers.dev')}/image-proxy?url=${Uri.encodeComponent(url)}';
    }
    return url;
  }
}
