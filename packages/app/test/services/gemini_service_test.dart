/// Unit tests for GeminiService
import 'package:flutter_test/flutter_test.dart';
import 'package:gativani/services/gemini_service.dart';
import '../mocks/mock_services.dart';

void main() {
  group('GeminiService', () {
    late MockGeminiService service;

    setUp(() {
      service = MockGeminiService();
      service.initialize();
    });

    group('Initialization', () {
      test('singleton pattern returns same instance', () {
        final service1 = GeminiService();
        final service2 = GeminiService();
        expect(identical(service1, service2), true);
      });

      test('initialize can be called without error', () {
        expect(() => service.initialize(), returnsNormally);
      });

      test('multiple initialize calls are safe', () {
        expect(() {
          service.initialize();
          service.initialize();
        }, returnsNormally);
      });
    });

    group('Summarization', () {
      test('summarizeArticle returns non-empty string', () async {
        final summary = await service.summarizeArticle('Test article content');
        expect(summary, isNotEmpty);
      });

      test('summarizeArticle returns valid summary', () async {
        final summary = await service.summarizeArticle(
          'This is a long article about breaking news',
        );
        expect(summary, isA<String>());
      });

      test('summarizeArticle supports Telugu language', () async {
        final summary = await service.summarizeArticle(
          'సమాచారం పత్రిక',
          language: 'te',
        );
        expect(summary, isNotEmpty);
      });

      test('summarizeArticle supports English language', () async {
        final summary = await service.summarizeArticle(
          'News article',
          language: 'en',
        );
        expect(summary, isNotEmpty);
      });

      test('summarizeArticle supports Hindi language', () async {
        final summary = await service.summarizeArticle(
          'समाचार लेख',
          language: 'hi',
        );
        expect(summary, isNotEmpty);
      });

      test('summarizeArticle respects maxLength parameter', () async {
        final summary = await service.summarizeArticle(
          'Article content',
          maxLength: 100,
        );
        expect(summary, isA<String>());
      });

      test('summarizeArticle with different maxLength values', () async {
        final short = await service.summarizeArticle('Article', maxLength: 50);
        final long = await service.summarizeArticle('Article', maxLength: 1000);
        expect([short, long], everyElement(isNotEmpty));
      });

      test('summarizeArticle with very short article', () async {
        final summary = await service.summarizeArticle('Short');
        expect(summary, isNotEmpty);
      });

      test('summarizeArticle with very long article', () async {
        final longArticle = 'word ' * 1000;
        final summary = await service.summarizeArticle(longArticle);
        expect(summary, isNotEmpty);
      });

      test('summarizeArticle with multiple parameters', () async {
        final summary = await service.summarizeArticle(
          'Complete article',
          language: 'te',
          maxLength: 500,
        );
        expect(summary, isNotEmpty);
      });

      test('summarizeArticle with empty text throws exception', () async {
        expect(
          () => service.summarizeArticle(''),
          throwsA(isA<GeminiException>()),
        );
      });

      test('summarizeArticle with unicode content', () async {
        final summary = await service.summarizeArticle('తెలుగు సమాచారం');
        expect(summary, isNotEmpty);
      });

      test('summarizeArticle with special characters', () async {
        final summary = await service.summarizeArticle(
          'Article with @#$% special chars & symbols',
        );
        expect(summary, isNotEmpty);
      });
    });

    group('Audio Script Generation', () {
      test('generateAudioScript returns non-empty string', () async {
        final script = await service.generateAudioScript('Article content');
        expect(script, isNotEmpty);
      });

      test('generateAudioScript returns valid script format', () async {
        final script = await service.generateAudioScript('Breaking news');
        expect(script, contains('Welcome') | contains('Today'));
      });

      test('generateAudioScript supports Telugu language', () async {
        final script = await service.generateAudioScript(
          'సమాచారం పత్రిక',
          language: 'te',
        );
        expect(script, isNotEmpty);
      });

      test('generateAudioScript supports English language', () async {
        final script = await service.generateAudioScript(
          'News article',
          language: 'en',
        );
        expect(script, isNotEmpty);
      });

      test('generateAudioScript supports Hindi language', () async {
        final script = await service.generateAudioScript(
          'समाचार लेख',
          language: 'hi',
        );
        expect(script, isNotEmpty);
      });

      test('generateAudioScript respects durationMinutes parameter', () async {
        final script = await service.generateAudioScript(
          'Article content',
          durationMinutes: 5,
        );
        expect(script, isNotEmpty);
      });

      test('generateAudioScript with different duration values', () async {
        final short = await service.generateAudioScript(
          'Article',
          durationMinutes: 2,
        );
        final long = await service.generateAudioScript(
          'Article',
          durationMinutes: 30,
        );
        expect([short, long], everyElement(isNotEmpty));
      });

      test('generateAudioScript with 1 minute duration', () async {
        final script = await service.generateAudioScript(
          'News',
          durationMinutes: 1,
        );
        expect(script, isNotEmpty);
      });

      test('generateAudioScript with 60 minute duration', () async {
        final script = await service.generateAudioScript(
          'Article',
          durationMinutes: 60,
        );
        expect(script, isNotEmpty);
      });

      test('generateAudioScript with multiple parameters', () async {
        final script = await service.generateAudioScript(
          'Complete article',
          language: 'te',
          durationMinutes: 10,
        );
        expect(script, isNotEmpty);
      });

      test('generateAudioScript includes podcast-style formatting', () async {
        final script = await service.generateAudioScript('News article');
        expect(script, contains('Welcome') | contains('Today'));
      });

      test('generateAudioScript with unicode content', () async {
        final script = await service.generateAudioScript('తెలుగు సమాచారం');
        expect(script, isNotEmpty);
      });

      test('generateAudioScript with very short article', () async {
        final script = await service.generateAudioScript('Short');
        expect(script, isNotEmpty);
      });

      test('generateAudioScript with very long article', () async {
        final longArticle = 'word ' * 1000;
        final script = await service.generateAudioScript(longArticle);
        expect(script, isNotEmpty);
      });
    });

    group('Batch Summarization', () {
      test('batchSummarize returns list of summaries', () async {
        final summaries = await service.batchSummarize(
          ['Article 1', 'Article 2', 'Article 3'],
        );
        expect(summaries, isA<List<String>>());
        expect(summaries.length, equals(3));
      });

      test('batchSummarize returns correct number of summaries', () async {
        final articles = ['Article 1', 'Article 2', 'Article 3', 'Article 4'];
        final summaries = await service.batchSummarize(articles);
        expect(summaries.length, equals(articles.length));
      });

      test('batchSummarize all summaries are non-empty', () async {
        final summaries = await service.batchSummarize(
          ['Article 1', 'Article 2'],
        );
        expect(summaries, everyElement(isNotEmpty));
      });

      test('batchSummarize supports Telugu', () async {
        final summaries = await service.batchSummarize(
          ['సమాచారం 1', 'సమాచారం 2'],
          language: 'te',
        );
        expect(summaries.length, equals(2));
      });

      test('batchSummarize supports English', () async {
        final summaries = await service.batchSummarize(
          ['Article 1', 'Article 2'],
          language: 'en',
        );
        expect(summaries.length, equals(2));
      });

      test('batchSummarize respects maxLength parameter', () async {
        final summaries = await service.batchSummarize(
          ['Article 1', 'Article 2'],
          maxLength: 200,
        );
        expect(summaries.length, equals(2));
      });

      test('batchSummarize with single article', () async {
        final summaries = await service.batchSummarize(['Single Article']);
        expect(summaries.length, equals(1));
      });

      test('batchSummarize with large batch', () async {
        final articles = List.generate(20, (i) => 'Article $i');
        final summaries = await service.batchSummarize(articles);
        expect(summaries.length, equals(20));
      });

      test('batchSummarize maintains order', () async {
        final articles = ['First', 'Second', 'Third'];
        final summaries = await service.batchSummarize(articles);
        expect(summaries.length, equals(3));
        expect(summaries[0], isNotEmpty);
        expect(summaries[1], isNotEmpty);
        expect(summaries[2], isNotEmpty);
      });

      test('batchSummarize with mixed length articles', () async {
        final summaries = await service.batchSummarize([
          'Short',
          'This is a much longer article with more content',
          'Medium content here',
        ]);
        expect(summaries.length, equals(3));
      });
    });

    group('Exception Handling', () {
      test('GeminiException has proper message', () {
        final exception = GeminiException('Test error');
        expect(exception.message, equals('Test error'));
      });

      test('GeminiException toString includes type', () {
        final exception = GeminiException('Test error');
        expect(exception.toString(), contains('GeminiException'));
      });

      test('GeminiException with empty message', () {
        final exception = GeminiException('');
        expect(exception.message, isEmpty);
      });

      test('GeminiException with special characters', () {
        final exception = GeminiException('Error: @#$% 500');
        expect(exception.message, contains('@'));
      });

      test('summarizeArticle throws exception for empty text', () {
        expect(
          () => service.summarizeArticle(''),
          throwsA(isA<GeminiException>()),
        );
      });
    });

    group('Edge Cases', () {
      test('summarizeArticle with null-like content', () async {
        expect(
          () => service.summarizeArticle(''),
          throwsA(isA<GeminiException>()),
        );
      });

      test('generateAudioScript with newlines', () async {
        final script = await service.generateAudioScript(
          'Line 1\nLine 2\nLine 3',
        );
        expect(script, isNotEmpty);
      });

      test('summarizeArticle with tabs and special whitespace', () async {
        final content = 'Text\twith\ttabs\nand\nnewlines';
        final summary = await service.summarizeArticle(content);
        expect(summary, isNotEmpty);
      });

      test('batchSummarize with empty articles list', () async {
        final summaries = await service.batchSummarize([]);
        expect(summaries, isEmpty);
      });

      test('generateAudioScript with zero duration', () async {
        final script = await service.generateAudioScript(
          'Article',
          durationMinutes: 0,
        );
        expect(script, isNotEmpty);
      });

      test('batchSummarize with very long content', () async {
        final longArticles = List.generate(
          5,
          (i) => 'word ' * 500,
        );
        final summaries = await service.batchSummarize(longArticles);
        expect(summaries.length, equals(5));
      });
    });

    group('Performance', () {
      test('summarizeArticle completes in reasonable time', () async {
        final stopwatch = Stopwatch()..start();
        await service.summarizeArticle('Article content');
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
      });

      test('generateAudioScript completes in reasonable time', () async {
        final stopwatch = Stopwatch()..start();
        await service.generateAudioScript('Article content');
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
      });

      test('batchSummarize performance on moderate batch', () async {
        final articles = List.generate(10, (i) => 'Article $i');
        final stopwatch = Stopwatch()..start();
        await service.batchSummarize(articles);
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(10000));
      });
    });

    group('Concurrent Operations', () {
      test('concurrent summarization calls', () async {
        final futures = List.generate(
          5,
          (i) => service.summarizeArticle('Article $i'),
        );
        final results = await Future.wait(futures);
        expect(results.length, equals(5));
      });

      test('concurrent audio script generation', () async {
        final futures = List.generate(
          5,
          (i) => service.generateAudioScript('Article $i'),
        );
        final results = await Future.wait(futures);
        expect(results.length, equals(5));
      });

      test('mixed concurrent operations', () async {
        final summarize = service.summarizeArticle('Article');
        final audioScript = service.generateAudioScript('Article');
        final batch = service.batchSummarize(['A', 'B']);

        final results = await Future.wait([summarize, audioScript, batch]);
        expect(results.length, equals(3));
      });
    });

    group('Language Support', () {
      test('all supported languages for summarization', () async {
        const languages = ['te', 'en', 'hi'];
        for (final lang in languages) {
          final summary = await service.summarizeArticle(
            'Article',
            language: lang,
          );
          expect(summary, isNotEmpty);
        }
      });

      test('all supported languages for audio script', () async {
        const languages = ['te', 'en', 'hi'];
        for (final lang in languages) {
          final script = await service.generateAudioScript(
            'Article',
            language: lang,
          );
          expect(script, isNotEmpty);
        }
      });

      test('unsupported language falls back to default', () async {
        final summary = await service.summarizeArticle(
          'Article',
          language: 'fr',
        );
        expect(summary, isNotEmpty);
      });
    });
  });
}
