/// A news article from any aggregated source.
class NewsArticle {
  final String id;
  final String title;
  final String source; // 'blizzard', 'wowhead', 'mmochampion', 'icyveins'
  final String category;
  final String? imageUrl;
  final String summary;
  final String content;
  final String? author;
  final DateTime publishedAt;
  final String url;

  const NewsArticle({
    required this.id,
    required this.title,
    required this.source,
    required this.category,
    this.imageUrl,
    required this.summary,
    required this.content,
    this.author,
    required this.publishedAt,
    required this.url,
  });

  factory NewsArticle.fromJson(Map<String, dynamic> json) {
    return NewsArticle(
      id: json['id'] as String,
      title: json['title'] as String,
      source: json['source'] as String,
      category: json['category'] as String? ?? 'News',
      imageUrl: json['imageUrl'] as String?,
      summary: json['summary'] as String? ?? '',
      content: json['content'] as String? ?? '',
      author: json['author'] as String?,
      publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? '') ?? DateTime.now(),
      url: json['url'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'source': source,
    'category': category,
    'imageUrl': imageUrl,
    'summary': summary,
    'content': content,
    'author': author,
    'publishedAt': publishedAt.toIso8601String(),
    'url': url,
  };

  /// Display name for the source.
  String get sourceDisplayName {
    switch (source) {
      case 'blizzard': return 'Blizzard';
      case 'wowhead': return 'Wowhead';
      case 'mmochampion': return 'MMO-C';
      case 'icyveins': return 'IcyVeins';
      default: return source;
    }
  }

  /// How long ago this was published, human-readable.
  String get timeAgo {
    final diff = DateTime.now().difference(publishedAt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  /// Returns the image URL proxied through the Worker for geo-blocked domains.
  String? get proxiedImageUrl {
    if (imageUrl == null || imageUrl!.isEmpty) return null;
    final url = imageUrl!;
    // Domains that may be geo-blocked and need proxying
    const blockedDomains = ['zamimg.com', 'wow.zamimg.com', 'static.icy-veins.com', 'wp.icy-veins.com'];
    final uri = Uri.tryParse(url);
    if (uri != null && blockedDomains.any((d) => uri.host.contains(d))) {
      return '${const String.fromEnvironment('AUTH_PROXY_URL', defaultValue: 'https://wow-companion-auth.fayz.workers.dev')}/image-proxy?url=${Uri.encodeComponent(url)}';
    }
    return url;
  }
}

/// A Reddit post from r/wow.
class RedditPost {
  final String id;
  final String title;
  final String? imageUrl;
  final String summary;
  final String? author;
  final DateTime publishedAt;
  final String url;
  final int score;
  final int numComments;
  final String? flair;

  const RedditPost({
    required this.id,
    required this.title,
    this.imageUrl,
    required this.summary,
    this.author,
    required this.publishedAt,
    required this.url,
    required this.score,
    required this.numComments,
    this.flair,
  });

  factory RedditPost.fromJson(Map<String, dynamic> json) {
    return RedditPost(
      id: json['id'] as String,
      title: json['title'] as String,
      imageUrl: json['imageUrl'] as String?,
      summary: json['summary'] as String? ?? '',
      author: json['author'] as String?,
      publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? '') ?? DateTime.now(),
      url: json['url'] as String,
      score: json['score'] as int? ?? 0,
      numComments: json['numComments'] as int? ?? 0,
      flair: json['flair'] as String?,
    );
  }

  String get formattedScore {
    if (score >= 1000) {
      return '${(score / 1000).toStringAsFixed(1)}k';
    }
    return score.toString();
  }

  String get timeAgo {
    final diff = DateTime.now().difference(publishedAt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}
