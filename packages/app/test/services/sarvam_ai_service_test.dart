/// Unit tests for SarvamAIService
import 'package:flutter_test/flutter_test.dart';
import 'package:gativani/services/sarvam_ai_service.dart';
import '../mocks/mock_services.dart';

void main() {
  group('SarvamAIService', () {
    late FakeSarvamAIService service;

    setUp(() {
      service = FakeSarvamAIService();
      service.initialize();
    });

    group('Initialization', () {
      test('singleton pattern returns same instance', () {
        final service1 = SarvamAIService();
        final service2 = SarvamAIService();
        expect(identical(service1, service2), true);
      });

      test('initialize sets initialized flag', () {
        expect(service.initialized, true);
      });

      test('multiple initialize calls are safe', () {
        expect(() {
          service.initialize();
          service.initialize();
        }, returnsNormally);
      });
    });

    group('OCR - Text Extraction', () {
      test('extractTextFromImage returns non-empty string', () async {
        final text = await service.extractTextFromImage('test.jpg');
        expect(text, isNotEmpty);
      });

      test('extractTextFromImage returns extracted text', () async {
        final text = await service.extractTextFromImage('test.jpg');
        expect(text, contains('Extracted'));
      });

      test('extractTextFromImage supports Telugu language', () async {
        final text = await service.extractTextFromImage(
          'test.jpg',
          language: 'te',
        );
        expect(text, isA<String>());
      });

      test('extractTextFromImage supports English language', () async {
        final text = await service.extractTextFromImage(
          'test.jpg',
          language: 'en',
        );
        expect(text, isA<String>());
      });

      test('extractTextFromImage supports Hindi language', () async {
        final text = await service.extractTextFromImage(
          'test.jpg',
          language: 'hi',
        );
        expect(text, isA<String>());
      });

      test('extractTextFromImage increments call counter', () async {
        expect(service.ocrCallCount, equals(0));
        await service.extractTextFromImage('test1.jpg');
        expect(service.ocrCallCount, equals(1));
        await service.extractTextFromImage('test2.jpg');
        expect(service.ocrCallCount, equals(2));
      });

      test('extractTextFromImage with various file paths', () async {
        final text1 = await service.extractTextFromImage('/path/to/image.jpg');
        final text2 = await service.extractTextFromImage('image.png');
        final text3 = await service.extractTextFromImage('image.pdf');
        expect([text1, text2, text3], everyElement(isNotEmpty));
      });

      test('extractTextFromImage handles multiple calls sequentially', () async {
        final texts = <String>[];
        for (int i = 0; i < 5; i++) {
          texts.add(await service.extractTextFromImage('test$i.jpg'));
        }
        expect(texts.length, equals(5));
        expect(service.ocrCallCount, equals(5));
      });

      test('extractTextFromImage throws on error when configured', () async {
        service.errorToThrow = 'API Error';
        expect(
          () => service.extractTextFromImage('test.jpg'),
          throwsA(isA<SarvamAIException>()),
        );
      });
    });

    group('TTS - Text to Speech', () {
      test('textToSpeech returns audio URL', () async {
        final url = await service.textToSpeech('Hello world');
        expect(url, isNotEmpty);
        expect(url, contains('example.com'));
      });

      test('textToSpeech returns valid URL format', () async {
        final url = await service.textToSpeech('Test audio');
        expect(url, startsWith('https://'));
        expect(url, contains('audio'));
      });

      test('textToSpeech supports Telugu language', () async {
        final url = await service.textToSpeech(
          'నమస్కారం',
          language: 'te',
        );
        expect(url, isNotEmpty);
      });

      test('textToSpeech supports English language', () async {
        final url = await service.textToSpeech(
          'Hello',
          language: 'en',
        );
        expect(url, isNotEmpty);
      });

      test('textToSpeech supports Hindi language', () async {
        final url = await service.textToSpeech(
          'नमस्कार',
          language: 'hi',
        );
        expect(url, isNotEmpty);
      });

      test('textToSpeech supports female gender', () async {
        final url = await service.textToSpeech(
          'Test',
          gender: 'female',
        );
        expect(url, isNotEmpty);
      });

      test('textToSpeech supports male gender', () async {
        final url = await service.textToSpeech(
          'Test',
          gender: 'male',
        );
        expect(url, isNotEmpty);
      });

      test('textToSpeech supports speed parameter', () async {
        final url = await service.textToSpeech(
          'Test',
          speed: 1.5,
        );
        expect(url, isNotEmpty);
      });

      test('textToSpeech with minimum speed', () async {
        final url = await service.textToSpeech('Test', speed: 0.5);
        expect(url, isNotEmpty);
      });

      test('textToSpeech with maximum speed', () async {
        final url = await service.textToSpeech('Test', speed: 2.0);
        expect(url, isNotEmpty);
      });

      test('textToSpeech increments call counter', () async {
        expect(service.ttsCallCount, equals(0));
        await service.textToSpeech('Text 1');
        expect(service.ttsCallCount, equals(1));
        await service.textToSpeech('Text 2');
        expect(service.ttsCallCount, equals(2));
      });

      test('textToSpeech handles empty text gracefully', () async {
        final url = await service.textToSpeech('');
        expect(url, isNotEmpty);
      });

      test('textToSpeech handles very long text', () async {
        final longText = 'word ' * 1000;
        final url = await service.textToSpeech(longText);
        expect(url, isNotEmpty);
      });

      test('textToSpeech with multiple parameters', () async {
        final url = await service.textToSpeech(
          'Full test',
          language: 'te',
          gender: 'female',
          speed: 1.2,
        );
        expect(url, isNotEmpty);
      });

      test('textToSpeech throws on error when configured', () async {
        service.errorToThrow = 'API Error';
        expect(
          () => service.textToSpeech('Test'),
          throwsA(isA<SarvamAIException>()),
        );
      });
    });

    group('Batch TTS - Multiple texts', () {
      test('batchTextToSpeech returns list of URLs', () async {
        final urls = await service.batchTextToSpeech(['Text 1', 'Text 2', 'Text 3']);
        expect(urls, isA<List<String>>());
        expect(urls.length, equals(3));
      });

      test('batchTextToSpeech returns correct number of URLs', () async {
        final texts = ['a', 'b', 'c', 'd', 'e'];
        final urls = await service.batchTextToSpeech(texts);
        expect(urls.length, equals(texts.length));
      });

      test('batchTextToSpeech all URLs are non-empty', () async {
        final urls = await service.batchTextToSpeech(['Text 1', 'Text 2']);
        expect(urls, everyElement(isNotEmpty));
      });

      test('batchTextToSpeech supports Telugu', () async {
        final urls = await service.batchTextToSpeech(
          ['నమస్కారం', 'హలో'],
          language: 'te',
        );
        expect(urls.length, equals(2));
      });

      test('batchTextToSpeech supports English', () async {
        final urls = await service.batchTextToSpeech(
          ['Hello', 'World'],
          language: 'en',
        );
        expect(urls.length, equals(2));
      });

      test('batchTextToSpeech with gender parameter', () async {
        final urls = await service.batchTextToSpeech(
          ['Text'],
          gender: 'female',
        );
        expect(urls.length, equals(1));
      });

      test('batchTextToSpeech handles empty list', () async {
        final urls = await service.batchTextToSpeech([]);
        expect(urls, isA<List<String>>());
      });

      test('batchTextToSpeech with single item', () async {
        final urls = await service.batchTextToSpeech(['Single']);
        expect(urls.length, equals(1));
      });

      test('batchTextToSpeech with large batch', () async {
        final texts = List.generate(50, (i) => 'Text $i');
        final urls = await service.batchTextToSpeech(texts);
        expect(urls.length, equals(50));
      });

      test('batchTextToSpeech throws on error when configured', () async {
        service.errorToThrow = 'Batch API Error';
        expect(
          () => service.batchTextToSpeech(['Text']),
          throwsA(isA<SarvamAIException>()),
        );
      });

      test('batchTextToSpeech maintains order', () async {
        final texts = ['First', 'Second', 'Third'];
        final urls = await service.batchTextToSpeech(texts);
        expect(urls.length, equals(3));
        // URLs should correspond to input order
        expect(urls[0], isNotEmpty);
        expect(urls[1], isNotEmpty);
        expect(urls[2], isNotEmpty);
      });
    });

    group('Health Check', () {
      test('healthCheck returns boolean', () async {
        final isHealthy = await service.healthCheck();
        expect(isHealthy, isA<bool>());
      });

      test('healthCheck returns true in normal operation', () async {
        final isHealthy = await service.healthCheck();
        expect(isHealthy, true);
      });

      test('healthCheck can be called multiple times', () async {
        final check1 = await service.healthCheck();
        final check2 = await service.healthCheck();
        expect(check1 && check2, true);
      });
    });

    group('Dispose', () {
      test('dispose can be called without error', () {
        expect(() => service.dispose(), returnsNormally);
      });

      test('dispose called multiple times is safe', () {
        service.dispose();
        expect(() => service.dispose(), returnsNormally);
      });
    });

    group('Exception Handling', () {
      test('SarvamAIException has proper message', () {
        final exception = SarvamAIException('Test error');
        expect(exception.message, equals('Test error'));
      });

      test('SarvamAIException toString includes type', () {
        final exception = SarvamAIException('Test error');
        expect(exception.toString(), contains('SarvamAIException'));
      });

      test('SarvamAIException with empty message', () {
        final exception = SarvamAIException('');
        expect(exception.message, isEmpty);
      });

      test('SarvamAIException with special characters', () {
        final exception = SarvamAIException('Error: @#$% 404');
        expect(exception.message, contains('@'));
      });

      test('error state affects subsequent calls', () async {
        service.errorToThrow = 'Persistent Error';
        expect(
          () => service.extractTextFromImage('test.jpg'),
          throwsA(isA<SarvamAIException>()),
        );
        // Clear error and verify normal operation
        service.errorToThrow = null;
        final text = await service.extractTextFromImage('test.jpg');
        expect(text, isNotEmpty);
      });
    });

    group('Edge Cases', () {
      test('extractTextFromImage with null-like path', () async {
        final text = await service.extractTextFromImage('');
        expect(text, isA<String>());
      });

      test('textToSpeech with unicode text', () async {
        final url = await service.textToSpeech('తెలుగు ఆడియో');
        expect(url, isNotEmpty);
      });

      test('batchTextToSpeech with mixed languages', () async {
        final urls = await service.batchTextToSpeech(['Hello', 'నమస్కారం']);
        expect(urls.length, equals(2));
      });

      test('textToSpeech with newlines and special chars', () async {
        final text = 'Line 1\nLine 2\nLine 3';
        final url = await service.textToSpeech(text);
        expect(url, isNotEmpty);
      });
    });

    group('Concurrent Operations', () {
      test('concurrent OCR calls handled correctly', () async {
        final futures = List.generate(
          5,
          (i) => service.extractTextFromImage('test$i.jpg'),
        );
        final results = await Future.wait(futures);
        expect(results.length, equals(5));
        expect(service.ocrCallCount, equals(5));
      });

      test('concurrent TTS calls handled correctly', () async {
        final futures = List.generate(
          5,
          (i) => service.textToSpeech('Text $i'),
        );
        final results = await Future.wait(futures);
        expect(results.length, equals(5));
        expect(service.ttsCallCount, equals(5));
      });

      test('mixed concurrent operations', () async {
        final ocr1 = service.extractTextFromImage('test.jpg');
        final tts1 = service.textToSpeech('Text');
        final ocr2 = service.extractTextFromImage('test2.jpg');

        await Future.wait([ocr1, tts1, ocr2]);
        expect(service.ocrCallCount, equals(2));
        expect(service.ttsCallCount, equals(1));
      });
    });
  });
}
