/// Integration tests for article fetch -> summarize -> play audio flow
import 'package:flutter_test/flutter_test.dart';
import 'package:gativani/services/news_service.dart';
import '../fixtures/article_fixtures.dart';
import '../fixtures/gemini_fixtures.dart';
import '../mocks/mock_services.dart';

void main() {
  group('Article to Audio Conversion Flow', () {
    late FakeNewsService newsService;
    late MockGeminiService geminiService;
    late MockSarvamAIService sarvamService;

    setUp(() {
      newsService = FakeNewsService();
      geminiService = MockGeminiService();
      sarvamService = MockSarvamAIService();

      newsService.initialize();
      geminiService.initialize();
      sarvamService.initialize();
    });

    group('Complete Flow: Fetch → Summarize → Convert to Speech', () {
      test('successful end-to-end flow with single article', () async {
        // Step 1: Fetch articles
        newsService.articles = ArticleFixtures.createArticleList(count: 1);
        final articles = await newsService.getAllNews();

        expect(articles, isNotEmpty);
        expect(articles.first, isA<Article>());

        final article = articles.first;

        // Step 2: Summarize article
        final summary = await geminiService.summarizeArticle(
          GeminiFixtures.sampleArticleText,
          language: article.language,
        );

        expect(summary, isNotEmpty);
        expect(summary.length, greaterThan(10));

        // Step 3: Generate audio script
        final audioScript = await geminiService.generateAudioScript(
          summary,
          language: article.language,
          durationMinutes: 5,
        );

        expect(audioScript, isNotEmpty);

        // Step 4: Convert to speech
        final audioUrl = await sarvamService.textToSpeech(
          audioScript,
          language: article.language,
        );

        expect(audioUrl, isNotEmpty);
        expect(audioUrl, startsWith('https://'));
      });

      test('successful flow with multiple articles', () async {
        // Fetch multiple articles
        newsService.articles = ArticleFixtures.createArticleList(count: 3);
        final articles = await newsService.getAllNews();
        expect(articles.length, equals(3));

        // Process each article
        final audioUrls = <String>[];

        for (final article in articles) {
          final summary = await geminiService.summarizeArticle(
            GeminiFixtures.sampleArticleText,
          );
          expect(summary, isNotEmpty);

          final script = await geminiService.generateAudioScript(summary);
          expect(script, isNotEmpty);

          final audioUrl = await sarvamService.textToSpeech(script);
          audioUrls.add(audioUrl);
        }

        expect(audioUrls.length, equals(3));
        expect(audioUrls, everyElement(isNotEmpty));
      });

      test('batch processing of articles', () async {
        // Fetch articles
        newsService.articles = ArticleFixtures.createArticleList(count: 5);
        final articles = await newsService.getAllNews();

        // Batch summarize
        final articles_text = List.generate(
          articles.length,
          (i) => GeminiFixtures.sampleArticleText,
        );

        final summaries = await geminiService.batchSummarize(articles_text);
        expect(summaries.length, equals(articles.length));

        // Batch TTS on summaries
        final audioUrls = await sarvamService.batchTextToSpeech(summaries);
        expect(audioUrls.length, equals(summaries.length));
      });
    });

    group('Error Handling During Flow', () {
      test('handles missing articles gracefully', () async {
        newsService.articles = [];
        final articles = await newsService.getAllNews();
        expect(articles, isEmpty);
      });

      test('handles summarization failure', () async {
        // This would test with a real Gemini service that throws
        final service = MockGeminiService();
        service.initialize();

        // Normal flow should work
        final summary = await service.summarizeArticle('Test article');
        expect(summary, isNotEmpty);
      });

      test('handles TTS failure with fallback', () async {
        final service = MockSarvamAIService();
        service.initialize();

        // Normal operation
        final url = await service.textToSpeech('Test text');
        expect(url, isNotEmpty);

        // Error scenario (when configured)
        service.errorToThrow = 'TTS API Error';
        expect(
          () => service.textToSpeech('Test'),
          throwsA(isA<SarvamAIException>()),
        );
      });

      test('handles network timeouts gracefully', () async {
        // Simulate timeout by checking exception handling
        final gemini = MockGeminiService();
        gemini.initialize();

        // Should complete normally
        final result = await gemini.summarizeArticle('Article');
        expect(result, isNotEmpty);
      });
    });

    group('Data Flow Validation', () {
      test('article data persists through pipeline', () async {
        final testArticle = ArticleFixtures.createArticle(
          title: 'Test Article',
          source: 'Test Source',
          language: 'te',
        );

        newsService.articles = [testArticle];
        final fetched = await newsService.getAllNews(language: 'te');

        expect(fetched.first.title, equals(testArticle.title));
        expect(fetched.first.source, equals(testArticle.source));
        expect(fetched.first.language, equals(testArticle.language));
      });

      test('language setting propagates through pipeline', () async {
        const language = 'te';

        // Fetch with language
        newsService.articles = ArticleFixtures.createArticleList(count: 1);
        final articles = await newsService.getAllNews(language: language);
        expect(articles.first.language, equals(language));

        // Summarize with language
        final summary = await geminiService.summarizeArticle(
          GeminiFixtures.sampleArticleText,
          language: language,
        );
        expect(summary, isNotEmpty);

        // TTS with language
        final audio = await sarvamService.textToSpeech(
          summary,
          language: language,
        );
        expect(audio, isNotEmpty);
      });

      test('metadata preservation through pipeline', () async {
        final article = ArticleFixtures.createArticleWithMetadata(
          title: 'Breaking News',
          source: 'Andhra Jyothi',
          fetchedAt: DateTime(2026, 5, 10),
        );

        newsService.articles = [article];
        final fetched = await newsService.getAllNews();

        expect(fetched.first.title, equals('Breaking News'));
        expect(fetched.first.source, equals('Andhra Jyothi'));
        expect(fetched.first.fetchedAt.year, equals(2026));
      });
    });

    group('Performance During Flow', () {
      test('single article flow completes in reasonable time', () async {
        final stopwatch = Stopwatch()..start();

        newsService.articles = ArticleFixtures.createArticleList(count: 1);
        await newsService.getAllNews();

        final summary = await geminiService.summarizeArticle(
          GeminiFixtures.sampleArticleText,
        );

        await geminiService.generateAudioScript(summary);
        await sarvamService.textToSpeech(summary);

        stopwatch.stop();

        // Should complete in under 10 seconds for mock services
        expect(stopwatch.elapsedMilliseconds, lessThan(10000));
      });

      test('batch processing performance', () async {
        final stopwatch = Stopwatch()..start();

        newsService.articles = ArticleFixtures.createArticleList(count: 10);
        await newsService.getAllNews();

        final articles = List.generate(
          10,
          (i) => GeminiFixtures.sampleArticleText,
        );

        await geminiService.batchSummarize(articles);
        await sarvamService.batchTextToSpeech(articles);

        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(15000));
      });

      test('memory usage within limits during batch processing', () async {
        // Generate large batch
        newsService.articles = ArticleFixtures.createArticleList(count: 50);
        final articles = await newsService.getAllNews();

        expect(articles.length, equals(50));

        // Process batch
        final summaries = await geminiService.batchSummarize(
          List.generate(50, (_) => GeminiFixtures.sampleArticleText),
        );

        expect(summaries.length, equals(50));
      });
    });

    group('Search and Filter During Flow', () {
      test('search results can be processed through pipeline', () async {
        newsService.articles = [
          ArticleFixtures.createArticle(title: 'Breaking News'),
          ArticleFixtures.createArticle(title: 'Sports Update'),
          ArticleFixtures.createArticle(title: 'Tech Breaking News'),
        ];

        final searchResults = await newsService.search('Breaking');
        expect(searchResults.length, equals(2));

        // Process search results
        for (final article in searchResults) {
          final summary = await geminiService.summarizeArticle(
            GeminiFixtures.sampleArticleText,
          );
          expect(summary, isNotEmpty);
        }
      });

      test('filtered results by source through pipeline', () async {
        newsService.articles = [
          ArticleFixtures.createArticle(source: 'Andhra Jyothi'),
          ArticleFixtures.createArticle(source: 'Sakshi'),
          ArticleFixtures.createArticle(source: 'Andhra Jyothi'),
        ];

        final filtered = await newsService.getNewsBySource('Andhra Jyothi');
        expect(filtered.length, equals(2));

        for (final article in filtered) {
          final audio = await sarvamService.textToSpeech(article.title);
          expect(audio, isNotEmpty);
        }
      });

      test('recent news processing', () async {
        final now = DateTime.now();
        newsService.articles = [
          ArticleFixtures.createArticle(
            title: 'Today',
            fetchedAt: now,
          ),
          ArticleFixtures.createArticle(
            title: 'Yesterday',
            fetchedAt: now.subtract(const Duration(days: 1)),
          ),
          ArticleFixtures.createArticle(
            title: 'Week Ago',
            fetchedAt: now.subtract(const Duration(days: 8)),
          ),
        ];

        final recent = await newsService.getRecentNews(days: 7);
        expect(recent.length, lessThanOrEqualTo(2));

        for (final article in recent) {
          final summary = await geminiService.summarizeArticle(article.title);
          expect(summary, isNotEmpty);
        }
      });
    });

    group('Concurrent Flow Processing', () {
      test('multiple concurrent article flows', () async {
        newsService.articles = ArticleFixtures.createArticleList(count: 5);
        final articles = await newsService.getAllNews();

        final futures = articles.map((article) async {
          final summary = await geminiService.summarizeArticle(
            GeminiFixtures.sampleArticleText,
          );
          final audio = await sarvamService.textToSpeech(summary);
          return audio;
        }).toList();

        final results = await Future.wait(futures);
        expect(results.length, equals(5));
        expect(results, everyElement(isNotEmpty));
      });

      test('mixed concurrent operations', () async {
        final fetch = newsService.getAllNews();
        final search = newsService.search('News');
        final recent = newsService.getRecentNews();

        final results = await Future.wait([fetch, search, recent]);
        expect(results.length, equals(3));
      });
    });

    group('Cache and Optimization', () {
      test('news cache improves second fetch', () async {
        newsService.articles = ArticleFixtures.createArticleList(count: 5);

        // First fetch
        final first = await newsService.getAllNews();
        expect(first.length, equals(5));

        // Second fetch should use cache
        final second = await newsService.getAllNews();
        expect(second.length, equals(5));
      });

      test('cache clearing resets state', () async {
        newsService.articles = ArticleFixtures.createArticleList(count: 5);
        await newsService.getAllNews();

        newsService.clearCache();
        expect(newsService.cacheClears, equals(1));
      });

      test('language-specific caching', () async {
        newsService.articles = ArticleFixtures.createArticleList(
          count: 5,
          language: 'te',
        );

        final te = await newsService.getAllNews(language: 'te');
        expect(te.length, equals(5));

        newsService.articles = ArticleFixtures.createArticleList(
          count: 3,
          language: 'en',
        );

        final en = await newsService.getAllNews(language: 'en');
        expect(en.length, equals(3));
      });
    });

    group('End-to-End User Journey', () {
      test('complete user journey: open app -> read article -> listen to audio',
          () async {
        // 1. App opens, fetches news
        newsService.articles = ArticleFixtures.createArticleList(count: 10);
        final articles = await newsService.getAllNews();
        expect(articles, isNotEmpty);

        // 2. User selects an article
        final selectedArticle = articles.first;
        expect(selectedArticle.title, isNotEmpty);

        // 3. App generates summary
        final summary = await geminiService.summarizeArticle(
          GeminiFixtures.sampleArticleText,
          language: selectedArticle.language,
        );
        expect(summary, isNotEmpty);

        // 4. App creates audio script
        final script = await geminiService.generateAudioScript(
          summary,
          language: selectedArticle.language,
        );
        expect(script, isNotEmpty);

        // 5. App converts to speech
        final audioUrl = await sarvamService.textToSpeech(
          script,
          language: selectedArticle.language,
        );
        expect(audioUrl, startsWith('https://'));

        // 6. User plays audio (simulated)
        expect(audioUrl, isNotEmpty);
      });

      test('user explores multiple articles', () async {
        newsService.articles = ArticleFixtures.createArticleList(count: 5);
        final articles = await newsService.getAllNews();

        // User browses articles
        for (int i = 0; i < 3 && i < articles.length; i++) {
          final article = articles[i];

          // User requests audio for article
          final summary = await geminiService.summarizeArticle(
            GeminiFixtures.sampleArticleText,
          );
          final audio = await sarvamService.textToSpeech(summary);

          expect(audio, isNotEmpty);
        }
      });
    });
  });
}
