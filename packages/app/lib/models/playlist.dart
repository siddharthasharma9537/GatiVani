import '../models/newspaper_article.dart';

/// A user-created, named collection of stories — distinct from the
/// ephemeral Up Next queue (cleared on restart) and from Downloads
/// (offline copies, not curated). Each item is a full article snapshot
/// (same reasoning as DownloadsStore/ReactionsStore): a playlist has to
/// render and play even if the original feed that surfaced the article is
/// long gone from memory.
class Playlist {
  Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    List<NewspaperArticle>? articles,
  }) : articles = articles ?? [];

  final String id;
  String name;
  final DateTime createdAt;
  final List<NewspaperArticle> articles;

  bool contains(String articleId) =>
      articles.any((a) => a.id == articleId);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'articles': articles
            .map((a) => {
                  'id': a.id,
                  'title': a.title,
                  'content': a.content,
                  'preview': a.preview,
                  'category': a.category,
                  'estimatedDurationSeconds': a.estimatedDurationSeconds,
                  'page': a.page,
                  'language': a.language,
                  'audioUrl': a.audioUrl,
                })
            .toList(),
      };

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ??
                DateTime.now(),
        articles: ((j['articles'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(NewspaperArticle.fromJson)
            .toList(),
      );
}
