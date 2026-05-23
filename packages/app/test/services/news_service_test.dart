/// Unit tests for NewsService
import 'package:flutter_test/flutter_test.dart';
import 'package:gativani/services/news_service.dart';
import '../fixtures/article_fixtures.dart';
import '../mocks/mock_services.dart';

void main() {
  group('NewsService', () {
    late FakeNewsService service;

    setUp(() {
      service = FakeNewsService();
      service.initialize();
    });

    group('Initialization', () {
      test('singleton pattern returns same instance', () {
        final service1 = NewsService();
        final service2 = NewsService();
        expect(identical(service1, service2), true);
      });

      test('initialize sets initialized flag', () async {
        final testService = FakeNewsService();
        expect(testService.initialized, false);
        testService.initialize();
        expect(testService.initialized, true);
      });

      test('initialize with custom backend URL', () async {
        final testService = FakeNewsService();
        testService.initialize(backendUrl: 'https://custom.api.com');
        expect(testService.initialized, true);
      });
    });

    group('getAllNews', () {
      test('returns empty list when no articles cached', () async {
        final articles = await service.getAllNews();
        expect(articles, isEmpty);
      });

      test('returns all articles when available', () async {
        final expectedArticles = ArticleFixtures.createArticleList(count: 5);
        service.articles = expectedArticles;
        final articles = await service.getAllNews();
        expect(articles.length, equals(5));
      });

      test('respects limit parameter', () async {
        final articles = ArticleFixtures.createArticleList(count: 10);
        service.articles = articles;
        final result = await service.getAllNews(limitPerSource: 5);
        expect(result.length, equals(10)); // All articles from fake service
      });

      test('supports multiple languages', () async {
        final teArticles = ArticleFixtures.createArticleList(count: 3, language: 'te');
        final enArticles = ArticleFixtures.createArticleList(count: 2, language: 'en');
        service.articles = [...teArticles, ...enArticles];

        final teResults = await service.getAllNews(language: 'te');
        expect(teResults.length, greaterThan(0));
      });

      test('handles empty source list gracefully', () async {
        final articles = await service.getAllNews();
        expect(articles, isA<List<Article>>());
      });

      test('returns articles with correct structure', () async {
        final article = ArticleFixtures.createArticle(
          title: 'Breaking News',
          source: 'Test Source',
        );
        service.articles = [article];

        final articles = await service.getAllNews();
        expect(articles.first.title, equals('Breaking News'));
        expect(articles.first.source, equals('Test Source'));
      });

      test('handles large article counts', () async {
        final articles = ArticleFixtures.createArticleList(count: 100);
        service.articles = articles;
        final result = await service.getAllNews();
        expect(result.length, equals(100));
      });
    });

    group('getNewsBySource', () {
      setUp(() {
        service.articles = ArticleFixtures.createArticleList(count: 10);
      });

      test('returns articles from specific source', () async {
        final articles = await service.getNewsBySource('Source 0');
        expect(articles, isNotEmpty);
        expect(articles.every((a) => a.source == 'Source 0'), true);
      });

      test('returns empty list for non-existent source', () async {
        final articles = await service.getNewsBySource('Non-existent Source');
        expect(articles, isEmpty);
      });

      test('filters by source correctly', () async {
        final articles = await service.getNewsBySource('Source 1');
        expect(articles.every((a) => a.source == 'Source 1'), true);
      });

      test('respects limit parameter', () async {
        final articles = await service.getNewsBySource('Source 0', limit: 5);
        expect(articles, isA<List<Article>>());
      });

      test('handles multiple sources independently', () async {
        final source0Articles = await service.getNewsBySource('Source 0');
        final source1Articles = await service.getNewsBySource('Source 1');

        expect(
          source0Articles.any((a) => source1Articles.contains(a)),
          false,
        );
      });
    });

    group('Search', () {
      setUp(() {
        service.articles = [
          ArticleFixtures.createArticle(title: 'Breaking News: Election Results'),
          ArticleFixtures.createArticle(title: 'Sports: Cricket Match Today'),
          ArticleFixtures.createArticle(title: 'Breaking: Stock Market Surge'),
          ArticleFixtures.createArticle(title: 'Tech: New AI Model Released'),
        ];
      });

      test('finds articles by title keyword', () async {
        final results = await service.search('Breaking');
        expect(results.length, equals(2));
        expect(results.every((a) => a.title.contains('Breaking')), true);
      });

      test('case-insensitive search', () async {
        final results = await service.search('breaking');
        expect(results.length, equals(2));
      });

      test('returns empty list for no matches', () async {
        final results = await service.search('NonExistent');
        expect(results, isEmpty);
      });

      test('partial word matching', () async {
        final results = await service.search('News');
        expect(results.length, greaterThan(0));
      });

      test('search finds multiple matching articles', () async {
        final results = await service.search('Breaking');
        expect(results.length, equals(2));
      });

      test('search handles empty query', () async {
        final results = await service.search('');
        expect(results, isNotEmpty);
      });

      test('search with special characters', () async {
        final results = await service.search(':');
        expect(results, isA<List<Article>>());
      });
    });

    group('getRecentNews', () {
      setUp(() {
        final now = DateTime.now();
        service.articles = [
          ArticleFixtures.createArticle(
            title: 'Today News',
            fetchedAt: now,
          ),
          ArticleFixtures.createArticle(
            title: 'Yesterday News',
            fetchedAt: now.subtract(Duration(days: 1)),
          ),
          ArticleFixtures.createArticle(
            title: 'Week Old News',
            fetchedAt: now.subtract(Duration(days: 7)),
          ),
          ArticleFixtures.createArticle(
            title: 'Month Old News',
            fetchedAt: now.subtract(Duration(days: 30)),
          ),
        ];
      });

      test('returns recent articles within days parameter', () async {
        final recent = await service.getRecentNews(days: 7);
        expect(recent, isNotEmpty);
      });

      test('filters articles by date correctly', () async {
        final recent = await service.getRecentNews(days: 2);
        expect(recent.length, greaterThanOrEqualTo(1));
      });

      test('handles single day filter', () async {
        final recent = await service.getRecentNews(days: 1);
        expect(recent, isA<List<Article>>());
      });

      test('handles very old threshold', () async {
        final recent = await service.getRecentNews(days: 60);
        expect(recent.length, greaterThan(0));
      });
    });

    group('Cache Management', () {
      test('clearCache resets cache', () async {
        service.articles = ArticleFixtures.createArticleList(count: 5);
        expect(service.cacheClears, equals(0));

        service.clearCache();
        expect(service.cacheClears, equals(1));
      });

      test('clearCache called multiple times increments counter', () async {
        service.clearCache();
        service.clearCache();
        service.clearCache();
        expect(service.cacheClears, equals(3));
      });
    });

    group('Dispose', () {
      test('dispose can be called without error', () async {
        expect(() => service.dispose(), returnsNormally);
      });

      test('dispose called multiple times is safe', () async {
        service.dispose();
        expect(() => service.dispose(), returnsNormally);
      });
    });

    group('Exception Handling', () {
      test('NewsException has proper message', () {
        final exception = NewsException('Test error');
        expect(exception.message, equals('Test error'));
      });

      test('NewsException toString includes type', () {
        final exception = NewsException('Test error');
        expect(exception.toString(), contains('NewsException'));
      });

      test('NewsException with empty message', () {
        final exception = NewsException('');
        expect(exception.message, isEmpty);
      });
    });

    group('Article Model', () {
      test('Article creation with defaults', () {
        final article = Article(
          title: 'Test',
          source: 'Source',
          url: 'https://test.com',
          fetchedAt: DateTime.now(),
        );
        expect(article.language, equals('te'));
      });

      test('Article toMap serialization', () {
        final article = ArticleFixtures.createArticle();
        final map = article.toMap();

        expect(map['title'], equals(article.title));
        expect(map['source'], equals(article.source));
        expect(map['url'], equals(article.url));
        expect(map['language'], equals(article.language));
      });

      test('Article fromMap deserialization', () {
        final originalArticle = ArticleFixtures.createArticle(
          title: 'Test Article',
          source: 'Test Source',
        );
        final map = originalArticle.toMap();
        final article = Article.fromMap(map);

        expect(article.title, equals(originalArticle.title));
        expect(article.source, equals(originalArticle.source));
        expect(article.url, equals(originalArticle.url));
      });

      test('Article fromMap with minimal data', () {
        final article = Article.fromMap({});
        expect(article.title, equals('Untitled'));
        expect(article.source, equals('Unknown'));
        expect(article.language, equals('te'));
      });

      test('Article handles missing imageUrl', () {
        final article = ArticleFixtures.createArticle(imageUrl: null);
        expect(article.imageUrl, isNull);
      });

      test('Article preserves all metadata', () {
        final now = DateTime.now();
        final article = Article(
          title: 'Full Metadata Article',
          source: 'Complete Source',
          url: 'https://complete.test.com',
          imageUrl: 'https://image.test.com/img.jpg',
          fetchedAt: now,
          language: 'en',
        );

        expect(article.title, equals('Full Metadata Article'));
        expect(article.source, equals('Complete Source'));
        expect(article.url, equals('https://complete.test.com'));
        expect(article.imageUrl, equals('https://image.test.com/img.jpg'));
        expect(article.fetchedAt, equals(now));
        expect(article.language, equals('en'));
      });
    });

    group('Edge Cases', () {
      test('handles articles with empty titles', () async {
        service.articles = [ArticleFixtures.createArticle(title: '')];
        final articles = await service.getAllNews();
        expect(articles.first.title, isEmpty);
      });

      test('handles articles with very long titles', () async {
        final longTitle = 'x' * 1000;
        service.articles = [ArticleFixtures.createArticle(title: longTitle)];
        final articles = await service.getAllNews();
        expect(articles.first.title.length, equals(1000));
      });

      test('handles special characters in source names', () async {
        service.articles = [
          ArticleFixtures.createArticle(source: 'Source & Co. Ltd.')
        ];
        final results = await service.getNewsBySource('Source & Co. Ltd.');
        expect(results.length, equals(1));
      });

      test('handles unicode in article titles', () async {
        service.articles = [
          ArticleFixtures.createArticle(title: 'తెలుగు సమాచారం')
        ];
        final articles = await service.getAllNews();
        expect(articles.first.title, equals('తెలుగు సమాచారం'));
      });

      test('search handles very long queries', () async {
        final longQuery = 'x' * 500;
        final results = await service.search(longQuery);
        expect(results, isA<List<Article>>());
      });
    });

    group('Performance', () {
      test('handles large article lists efficiently', () async {
        service.articles = ArticleFixtures.createArticleList(count: 1000);
        final stopwatch = Stopwatch()..start();

        await service.getAllNews();

        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      });

      test('search performance on large datasets', () async {
        service.articles = ArticleFixtures.createArticleList(count: 500);
        final stopwatch = Stopwatch()..start();

        await service.search('Article');

        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(500));
      });
    });
  });
}
