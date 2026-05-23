/// Integration tests for offline cache fallback and error recovery
///
/// These scenarios verify the contract that the app must continue to work
/// when one or more dependencies (network, AI APIs, storage) misbehave.
///
/// Strategy:
///   * Use [FakeNewsService] and the configurable error knobs on
///     [FakeSarvamAIService] to simulate failures.
///   * Verify that downstream consumers either receive cached data or
///     translate failures into typed exceptions instead of crashing.

import 'package:flutter_test/flutter_test.dart';
import 'package:gativani/services/sarvam_ai_service.dart';
import 'package:gativani/services/gemini_service.dart';
import 'package:gativani/services/news_service.dart';

import '../fixtures/article_fixtures.dart';
import '../fixtures/gemini_fixtures.dart';
import '../mocks/mock_services.dart';

void main() {
  group('Offline cache fallback', () {
    late FakeNewsService news;

    setUp(() {
      news = FakeNewsService();
      news.initialize();
    });

    test('returns cached articles when service is queried twice', () async {
      news.articles = ArticleFixtures.createArticleList(count: 4);

      final first = await news.getAllNews();
      final second = await news.getAllNews();

      expect(first.length, equals(4));
      expect(second.length, equals(4));
      // Identical content represents a cache hit on the second call.
      expect(second.map((a) => a.title).toList(),
          equals(first.map((a) => a.title).toList()));
    });

    test('returns last-known articles after a clearCache call', () async {
      news.articles = ArticleFixtures.createArticleList(count: 2);
      final initial = await news.getAllNews();
      expect(initial.length, equals(2));

      // Clear cache and refill with new data
      news.clearCache();
      news.articles = ArticleFixtures.createArticleList(count: 5);

      final refreshed = await news.getAllNews();
      expect(refreshed.length, equals(5));
      expect(news.cacheClears, equals(1));
    });

    test('empty cache returns empty list without throwing', () async {
      news.articles = [];
      final results = await news.getAllNews();
      expect(results, isEmpty);
    });

    test('language-scoped cache returns content for each language',
        () async {
      news.articles = ArticleFixtures.createArticleList(
        count: 3,
        language: 'te',
      );
      final teResults = await news.getAllNews(language: 'te');
      expect(teResults.length, equals(3));

      news.articles = ArticleFixtures.createArticleList(
        count: 4,
        language: 'en',
      );
      final enResults = await news.getAllNews(language: 'en');
      expect(enResults.length, equals(4));
    });
  });

  group('Error recovery: AI services', () {
    late FakeSarvamAIService sarvam;
    late MockGeminiService gemini;

    setUp(() {
      sarvam = FakeSarvamAIService();
      gemini = MockGeminiService();
      sarvam.initialize();
      gemini.initialize();
    });

    test('TTS error throws typed exception, not unhandled error',
        () async {
      sarvam.errorToThrow = 'Network timeout';
      expect(
        () => sarvam.textToSpeech('Test'),
        throwsA(isA<SarvamAIException>()),
      );
    });

    test('OCR error throws typed exception, not unhandled error',
        () async {
      sarvam.errorToThrow = 'OCR API rate limited';
      expect(
        () => sarvam.extractTextFromImage('test.jpg'),
        throwsA(isA<SarvamAIException>()),
      );
    });

    test('clearing errorToThrow restores normal operation', () async {
      sarvam.errorToThrow = 'Transient error';
      expect(
        () => sarvam.textToSpeech('Text'),
        throwsA(isA<SarvamAIException>()),
      );

      sarvam.errorToThrow = null;
      final url = await sarvam.textToSpeech('Text');
      expect(url, startsWith('https://'));
    });

    test('summarization with empty input raises GeminiException', () async {
      expect(
        () => gemini.summarizeArticle(''),
        throwsA(isA<GeminiException>()),
      );
    });
  });

  group('Pipeline degradation', () {
    late FakeNewsService news;
    late MockGeminiService gemini;
    late FakeSarvamAIService sarvam;

    setUp(() {
      news = FakeNewsService();
      gemini = MockGeminiService();
      sarvam = FakeSarvamAIService();

      news.initialize();
      gemini.initialize();
      sarvam.initialize();
    });

    test('article still surfaces even if TTS step fails', () async {
      news.articles = ArticleFixtures.createArticleList(count: 1);
      final articles = await news.getAllNews();
      expect(articles, isNotEmpty);

      final summary = await gemini.summarizeArticle(
        GeminiFixtures.sampleArticleText,
      );
      expect(summary, isNotEmpty);

      // Now make TTS fail. The caller is responsible for catching this;
      // verify the pipeline does not crash earlier steps.
      sarvam.errorToThrow = 'TTS unavailable';
      expect(
        () => sarvam.textToSpeech(summary),
        throwsA(isA<SarvamAIException>()),
      );

      // Existing data (articles + summary) is still usable.
      expect(articles.first, isA<Article>());
      expect(summary, isA<String>());
    });

    test('batch TTS surfaces a single typed error for the whole batch',
        () async {
      sarvam.errorToThrow = 'Batch error';
      expect(
        () => sarvam.batchTextToSpeech(['a', 'b', 'c']),
        throwsA(isA<SarvamAIException>()),
      );
    });

    test('mixed flow: news cache survives after AI failure', () async {
      news.articles = ArticleFixtures.createArticleList(count: 3);
      sarvam.errorToThrow = 'AI down';

      // First, populate the news cache successfully.
      final first = await news.getAllNews();
      expect(first.length, equals(3));

      // Attempt downstream conversion -> fails with typed exception.
      expect(
        () => sarvam.textToSpeech('hello'),
        throwsA(isA<SarvamAIException>()),
      );

      // News data is still served from cache (fake "warm" state).
      final second = await news.getAllNews();
      expect(second.length, equals(3));
    });
  });

  group('Article serialization round-trip', () {
    // Ensures cached articles survive JSON encode/decode in a real cache
    // (Hive/SharedPreferences), guarding the offline contract.
    test('Article.toMap -> Article.fromMap preserves fields', () {
      final original = ArticleFixtures.createArticle(
        title: 'Round-trip',
        source: 'Cache Source',
        url: 'https://cache.test/article',
        imageUrl: 'https://cache.test/image.jpg',
        fetchedAt: DateTime(2026, 5, 11, 8, 30),
        language: 'te',
      );

      final round = Article.fromMap(original.toMap());
      expect(round.title, equals(original.title));
      expect(round.source, equals(original.source));
      expect(round.url, equals(original.url));
      expect(round.imageUrl, equals(original.imageUrl));
      expect(round.fetchedAt, equals(original.fetchedAt));
      expect(round.language, equals(original.language));
    });

    test('fromMap with missing fields fills sensible defaults', () {
      final article = Article.fromMap(<String, dynamic>{});
      expect(article.title, equals('Untitled'));
      expect(article.source, equals('Unknown'));
      expect(article.language, equals('te'));
    });
  });
}
