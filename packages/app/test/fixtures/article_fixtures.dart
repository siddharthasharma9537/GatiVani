/// Test fixtures for Article model
import 'package:gativani/services/news_service.dart';

class ArticleFixtures {
  static Article createArticle({
    String title = 'Test Article Title',
    String source = 'Test Source',
    String url = 'https://example.com/article',
    String? imageUrl,
    DateTime? fetchedAt,
    String language = 'te',
  }) {
    return Article(
      title: title,
      source: source,
      url: url,
      imageUrl: imageUrl,
      fetchedAt: fetchedAt ?? DateTime(2026, 5, 10, 12, 0),
      language: language,
    );
  }

  static List<Article> createArticleList({
    int count = 5,
    String language = 'te',
  }) {
    return List.generate(
      count,
      (index) => createArticle(
        title: 'Article $index',
        source: 'Source ${index % 3}',
        url: 'https://example.com/article-$index',
        language: language,
      ),
    );
  }

  static Article createArticleWithMetadata({
    required String title,
    required String source,
    DateTime? fetchedAt,
  }) {
    return Article(
      title: title,
      source: source,
      url: 'https://example.com/$title',
      imageUrl: 'https://example.com/image/$title.jpg',
      fetchedAt: fetchedAt ?? DateTime.now(),
      language: 'te',
    );
  }
}
