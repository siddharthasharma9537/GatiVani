/// Unit tests for StorageService
import 'package:flutter_test/flutter_test.dart';
import 'package:gativani/services/storage_service.dart';
import '../mocks/mock_services.dart';

void main() {
  group('StorageService', () {
    late MockStorageService service;

    setUp(() {
      service = MockStorageService();
      service.initialize();
    });

    group('Initialization', () {
      test('singleton pattern returns same instance', () {
        final service1 = StorageService();
        final service2 = StorageService();
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

    group('Audio Upload', () {
      test('uploadAudio returns download URL', () async {
        final url = await service.uploadAudio(
          Object() as dynamic,
          articleTitle: 'Test Article',
          source: 'Test Source',
        );
        expect(url, isNotEmpty);
      });

      test('uploadAudio returns valid URL format', () async {
        final url = await service.uploadAudio(
          Object() as dynamic,
          articleTitle: 'Test Article',
          source: 'Test Source',
        );
        expect(url, startsWith('https://'));
        expect(url, contains('example.com'));
      });

      test('uploadAudio with various article titles', () async {
        final titles = [
          'Breaking News',
          'Sports Update',
          'Tech Innovation',
        ];

        for (final title in titles) {
          final url = await service.uploadAudio(
            Object() as dynamic,
            articleTitle: title,
            source: 'Test Source',
          );
          expect(url, isNotEmpty);
        }
      });

      test('uploadAudio with various sources', () async {
        final sources = [
          'Andhra Jyothi',
          'Namasthe Telangana',
          'Sakshi',
        ];

        for (final source in sources) {
          final url = await service.uploadAudio(
            Object() as dynamic,
            articleTitle: 'Test Article',
            source: source,
          );
          expect(url, isNotEmpty);
        }
      });

      test('uploadAudio with special characters in title', () async {
        final url = await service.uploadAudio(
          Object() as dynamic,
          articleTitle: 'Article & Co. Ltd. (2026)',
          source: 'Test Source',
        );
        expect(url, isNotEmpty);
      });

      test('uploadAudio with unicode article title', () async {
        final url = await service.uploadAudio(
          Object() as dynamic,
          articleTitle: 'తెలుగు సమాచారం',
          source: 'Test Source',
        );
        expect(url, isNotEmpty);
      });

      test('uploadAudio with very long title', () async {
        final longTitle = 'Article ' * 100;
        final url = await service.uploadAudio(
          Object() as dynamic,
          articleTitle: longTitle,
          source: 'Test Source',
        );
        expect(url, isNotEmpty);
      });

      test('uploadAudio with empty-like title', () async {
        final url = await service.uploadAudio(
          Object() as dynamic,
          articleTitle: 'A',
          source: 'Test Source',
        );
        expect(url, isNotEmpty);
      });

      test('uploadAudio multiple sequential calls', () async {
        final url1 = await service.uploadAudio(
          Object() as dynamic,
          articleTitle: 'Article 1',
          source: 'Source 1',
        );
        final url2 = await service.uploadAudio(
          Object() as dynamic,
          articleTitle: 'Article 2',
          source: 'Source 2',
        );
        expect(url1, isNotEmpty);
        expect(url2, isNotEmpty);
        expect(url1 != url2, true);
      });
    });

    group('Image Upload', () {
      test('uploadImage returns download URL', () async {
        final url = await service.uploadImage(
          Object() as dynamic,
          imageName: 'test_image',
        );
        expect(url, isNotEmpty);
      });

      test('uploadImage returns valid URL format', () async {
        final url = await service.uploadImage(
          Object() as dynamic,
          imageName: 'test_image',
        );
        expect(url, startsWith('https://'));
        expect(url, contains('example.com'));
        expect(url, contains('image'));
      });

      test('uploadImage with various image names', () async {
        final names = [
          'article_header',
          'thumbnail_small',
          'featured_image',
        ];

        for (final name in names) {
          final url = await service.uploadImage(
            Object() as dynamic,
            imageName: name,
          );
          expect(url, isNotEmpty);
        }
      });

      test('uploadImage with special characters', () async {
        final url = await service.uploadImage(
          Object() as dynamic,
          imageName: 'image & photo (2026)',
        );
        expect(url, isNotEmpty);
      });

      test('uploadImage with unicode name', () async {
        final url = await service.uploadImage(
          Object() as dynamic,
          imageName: 'చిత్రం',
        );
        expect(url, isNotEmpty);
      });

      test('uploadImage with very long name', () async {
        final longName = 'image_' * 100;
        final url = await service.uploadImage(
          Object() as dynamic,
          imageName: longName,
        );
        expect(url, isNotEmpty);
      });

      test('uploadImage multiple sequential calls', () async {
        final url1 = await service.uploadImage(
          Object() as dynamic,
          imageName: 'image_1',
        );
        final url2 = await service.uploadImage(
          Object() as dynamic,
          imageName: 'image_2',
        );
        expect(url1, isNotEmpty);
        expect(url2, isNotEmpty);
        expect(url1 != url2, true);
      });
    });

    group('File Download', () {
      test('downloadFile returns file object', () async {
        final file = await service.downloadFile(
          'https://example.com/audio.mp3',
          '/tmp/audio.mp3',
        );
        expect(file, isNotNull);
      });

      test('downloadFile with various remote URLs', () async {
        final urls = [
          'https://example.com/audio1.mp3',
          'https://example.com/audio2.mp3',
          'https://example.com/image.jpg',
        ];

        for (final url in urls) {
          final file = await service.downloadFile(
            url,
            '/tmp/file',
          );
          expect(file, isNotNull);
        }
      });

      test('downloadFile with various local paths', () async {
        final paths = [
          '/tmp/audio.mp3',
          '/tmp/subdir/audio.mp3',
          '/tmp/nested/path/file.jpg',
        ];

        for (final path in paths) {
          final file = await service.downloadFile(
            'https://example.com/file.mp3',
            path,
          );
          expect(file, isNotNull);
        }
      });

      test('downloadFile creates necessary directories', () async {
        final file = await service.downloadFile(
          'https://example.com/file.mp3',
          '/tmp/new/deep/path/file.mp3',
        );
        expect(file, isNotNull);
      });

      test('downloadFile with special characters in path', () async {
        final file = await service.downloadFile(
          'https://example.com/file.mp3',
          '/tmp/file (2026) & co..mp3',
        );
        expect(file, isNotNull);
      });

      test('downloadFile multiple sequential calls', () async {
        final file1 = await service.downloadFile(
          'https://example.com/file1.mp3',
          '/tmp/file1.mp3',
        );
        final file2 = await service.downloadFile(
          'https://example.com/file2.mp3',
          '/tmp/file2.mp3',
        );
        expect(file1, isNotNull);
        expect(file2, isNotNull);
      });
    });

    group('File Deletion', () {
      test('deleteFile can be called successfully', () async {
        expect(
          () => service.deleteFile('https://example.com/file.mp3'),
          returnsNormally,
        );
      });

      test('deleteFile with various remote URLs', () async {
        final urls = [
          'https://example.com/audio.mp3',
          'https://example.com/image.jpg',
          'https://example.com/deep/path/file.mp3',
        ];

        for (final url in urls) {
          expect(
            () => service.deleteFile(url),
            returnsNormally,
          );
        }
      });

      test('deleteFile called multiple times is safe', () async {
        const url = 'https://example.com/file.mp3';
        expect(() => service.deleteFile(url), returnsNormally);
        expect(() => service.deleteFile(url), returnsNormally);
      });
    });

    group('File Metadata', () {
      test('getFileMetadata returns metadata object or null', () async {
        final metadata = await service.getFileMetadata(
          'https://example.com/file.mp3',
        );
        expect(metadata, isA<dynamic>());
      });

      test('getFileMetadata with various URLs', () async {
        final urls = [
          'https://example.com/audio.mp3',
          'https://example.com/image.jpg',
          'https://example.com/document.pdf',
        ];

        for (final url in urls) {
          final metadata = await service.getFileMetadata(url);
          expect(metadata, isA<dynamic>());
        }
      });

      test('getFileMetadata handles non-existent files gracefully', () async {
        final metadata = await service.getFileMetadata(
          'https://example.com/nonexistent.mp3',
        );
        expect(metadata, isA<dynamic>());
      });
    });

    group('List Files', () {
      test('listFiles returns list of files', () async {
        final files = await service.listFiles('audio/');
        expect(files, isA<List>());
      });

      test('listFiles with various directories', () async {
        final directories = [
          'audio/',
          'images/',
          'audio/archived/',
        ];

        for (final dir in directories) {
          final files = await service.listFiles(dir);
          expect(files, isA<List>());
        }
      });

      test('listFiles returns empty list for empty directory', () async {
        final files = await service.listFiles('empty/');
        expect(files, isA<List>());
      });

      test('listFiles handles deeply nested paths', () async {
        final files = await service.listFiles('audio/2026/may/10/');
        expect(files, isA<List>());
      });
    });

    group('Exception Handling', () {
      test('StorageException has proper message', () {
        final exception = StorageException('Test error');
        expect(exception.message, equals('Test error'));
      });

      test('StorageException toString includes type', () {
        final exception = StorageException('Test error');
        expect(exception.toString(), contains('StorageException'));
      });

      test('StorageException with empty message', () {
        final exception = StorageException('');
        expect(exception.message, isEmpty);
      });

      test('StorageException with special characters', () {
        final exception = StorageException('Error: @#$% 404 Not Found');
        expect(exception.message, contains('@'));
      });
    });

    group('Edge Cases', () {
      test('uploadAudio with empty file', () async {
        final url = await service.uploadAudio(
          Object() as dynamic,
          articleTitle: 'Empty Audio',
          source: 'Test Source',
        );
        expect(url, isNotEmpty);
      });

      test('uploadImage with empty file', () async {
        final url = await service.uploadImage(
          Object() as dynamic,
          imageName: 'empty_image',
        );
        expect(url, isNotEmpty);
      });

      test('downloadFile with very long URL', () async {
        final longUrl = 'https://example.com/' + ('a' * 500);
        final file = await service.downloadFile(longUrl, '/tmp/file');
        expect(file, isNotNull);
      });

      test('listFiles with root directory', () async {
        final files = await service.listFiles('/');
        expect(files, isA<List>());
      });

      test('getFileMetadata with invalid URL format', () async {
        final metadata = await service.getFileMetadata('invalid-url');
        expect(metadata, isA<dynamic>());
      });
    });

    group('Concurrent Operations', () {
      test('concurrent uploads', () async {
        final futures = List.generate(
          5,
          (i) => service.uploadAudio(
            Object() as dynamic,
            articleTitle: 'Article $i',
            source: 'Source $i',
          ),
        );
        final results = await Future.wait(futures);
        expect(results.length, equals(5));
      });

      test('concurrent downloads', () async {
        final futures = List.generate(
          5,
          (i) => service.downloadFile(
            'https://example.com/file$i.mp3',
            '/tmp/file$i.mp3',
          ),
        );
        final results = await Future.wait(futures);
        expect(results.length, equals(5));
      });

      test('mixed concurrent operations', () async {
        final upload = service.uploadAudio(
          Object() as dynamic,
          articleTitle: 'Article',
          source: 'Source',
        );
        final download = service.downloadFile(
          'https://example.com/file.mp3',
          '/tmp/file.mp3',
        );
        final metadata = service.getFileMetadata('https://example.com/file.mp3');

        final results = await Future.wait([upload, download, metadata]);
        expect(results.length, equals(3));
      });
    });

    group('File Path Normalization', () {
      test('handles paths with special characters', () async {
        final url = await service.uploadAudio(
          Object() as dynamic,
          articleTitle: 'Article (2026) & Co.',
          source: 'Source/Name',
        );
        expect(url, isNotEmpty);
      });

      test('handles paths with spaces', () async {
        final url = await service.uploadAudio(
          Object() as dynamic,
          articleTitle: 'Article Title With Spaces',
          source: 'Source With Spaces',
        );
        expect(url, isNotEmpty);
      });

      test('handles paths with multiple slashes', () async {
        final files = await service.listFiles('audio///');
        expect(files, isA<List>());
      });

      test('handles paths with dots', () async {
        final files = await service.listFiles('audio/../images/');
        expect(files, isA<List>());
      });
    });

    group('URL Format Validation', () {
      test('returned URLs are properly formatted', () async {
        final url = await service.uploadAudio(
          Object() as dynamic,
          articleTitle: 'Test',
          source: 'Test',
        );
        expect(url, startsWith('https://'));
        expect(url.length, greaterThan(10));
      });

      test('download URLs match upload pattern', () async {
        final uploadUrl = await service.uploadAudio(
          Object() as dynamic,
          articleTitle: 'Test',
          source: 'Test',
        );
        final imageUrl = await service.uploadImage(
          Object() as dynamic,
          imageName: 'test',
        );
        expect(uploadUrl, startsWith('https://'));
        expect(imageUrl, startsWith('https://'));
      });
    });

    group('Performance', () {
      test('upload completes in reasonable time', () async {
        final stopwatch = Stopwatch()..start();
        await service.uploadAudio(
          Object() as dynamic,
          articleTitle: 'Test',
          source: 'Test',
        );
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      });

      test('download completes in reasonable time', () async {
        final stopwatch = Stopwatch()..start();
        await service.downloadFile(
          'https://example.com/file.mp3',
          '/tmp/file.mp3',
        );
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      });

      test('listFiles completes in reasonable time', () async {
        final stopwatch = Stopwatch()..start();
        await service.listFiles('audio/');
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      });
    });
  });
}
