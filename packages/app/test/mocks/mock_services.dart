/// Mock implementations of services for testing
import 'package:mockito/mockito.dart';
import 'package:gativani/services/firebase_service.dart';
import 'package:gativani/services/sarvam_ai_service.dart';
import 'package:gativani/services/gemini_service.dart';
import 'package:gativani/services/storage_service.dart';
import 'package:gativani/services/news_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Mock FirebaseService
class MockFirebaseService extends Mock implements FirebaseService {
  @override
  Future<void> initialize() async {}

  @override
  FirebaseAnalytics get analytics => MockFirebaseAnalytics();

  @override
  FirebaseMessaging get messaging => MockFirebaseMessaging();

  @override
  Future<void> logEvent(
    String name, {
    Map<String, Object?>? parameters,
  }) async {}

  @override
  Future<void> logScreenView(String screenName) async {}

  @override
  Future<String?> getFCMToken() async => 'test-fcm-token';
}

/// Mock FirebaseAnalytics
class MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

/// Mock FirebaseMessaging
class MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

/// Mock SarvamAIService
class MockSarvamAIService extends Mock implements SarvamAIService {
  @override
  void initialize() {}

  @override
  Future<String> extractTextFromImage(
    String imagePath, {
    String language = 'te',
  }) async =>
      'Extracted text from image';

  @override
  Future<String> textToSpeech(
    String text, {
    String language = 'te',
    String gender = 'female',
    double speed = 1.0,
  }) async =>
      'https://example.com/audio.mp3';

  @override
  Future<List<String>> batchTextToSpeech(
    List<String> texts, {
    String language = 'te',
    String gender = 'female',
  }) async =>
      ['https://example.com/audio1.mp3', 'https://example.com/audio2.mp3'];

  @override
  Future<bool> healthCheck() async => true;

  @override
  void dispose() {}
}

/// Mock GeminiService
class MockGeminiService extends Mock implements GeminiService {
  @override
  void initialize() {}

  @override
  Future<String> summarizeArticle(
    String articleText, {
    String language = 'te',
    int maxLength = 500,
  }) async =>
      'This is a summary of the article.';

  @override
  Future<String> generateAudioScript(
    String articleText, {
    String language = 'te',
    int durationMinutes = 30,
  }) async =>
      'Welcome to GatiVani. Today we have an interesting story...';

  @override
  Future<List<String>> batchSummarize(
    List<String> articles, {
    String language = 'te',
    int maxLength = 500,
  }) async =>
      ['Summary 1', 'Summary 2', 'Summary 3'];
}

/// Mock StorageService
class MockStorageService extends Mock implements StorageService {
  @override
  void initialize() {}

  @override
  Future<String> uploadAudio(
    dynamic file, {
    required String articleTitle,
    required String source,
  }) async =>
      'https://example.com/audio.mp3';

  @override
  Future<String> uploadImage(
    dynamic file, {
    required String imageName,
  }) async =>
      'https://example.com/image.jpg';

  @override
  Future<dynamic> downloadFile(
    String remoteUrl,
    String localPath,
  ) async {
    // Return a mock file
    return Future.value();
  }

  @override
  Future<void> deleteFile(String remoteUrl) async {}

  @override
  Future<dynamic> getFileMetadata(String remoteUrl) async => null;

  @override
  Future<List> listFiles(String directory) async => [];
}

/// Mock NewsService
class MockNewsService extends Mock implements NewsService {
  @override
  void initialize({String? backendUrl}) {}

  @override
  Future<List<Article>> getAllNews({
    int limitPerSource = 20,
    String language = 'te',
  }) async =>
      [];

  @override
  Future<List<Article>> getNewsBySource(
    String source, {
    int limit = 20,
    String language = 'te',
  }) async =>
      [];

  @override
  Future<List<Article>> search(
    String query, {
    String language = 'te',
  }) async =>
      [];

  @override
  Future<List<Article>> getRecentNews({
    int days = 7,
    String language = 'te',
  }) async =>
      [];

  @override
  void clearCache() {}

  @override
  void dispose() {}
}

/// Fake implementations for detailed testing
class FakeFirebaseService implements FirebaseService {
  bool initialized = false;
  List<String> loggedEvents = [];
  List<String> loggedScreens = [];

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  FirebaseAnalytics get analytics => throw UnimplementedError();

  @override
  FirebaseMessaging get messaging => throw UnimplementedError();

  @override
  Future<void> logEvent(
    String name, {
    Map<String, Object?>? parameters,
  }) async {
    loggedEvents.add(name);
  }

  @override
  Future<void> logScreenView(String screenName) async {
    loggedScreens.add(screenName);
  }

  @override
  Future<String?> getFCMToken() async => 'fake-fcm-token';
}

class FakeSarvamAIService implements SarvamAIService {
  bool initialized = false;
  int ocrCallCount = 0;
  int ttsCallCount = 0;
  String? errorToThrow;

  @override
  void initialize() {
    initialized = true;
  }

  @override
  Future<String> extractTextFromImage(
    String imagePath, {
    String language = 'te',
  }) async {
    if (errorToThrow != null) {
      throw SarvamAIException(errorToThrow!);
    }
    ocrCallCount++;
    return 'Extracted: test text';
  }

  @override
  Future<String> textToSpeech(
    String text, {
    String language = 'te',
    String gender = 'female',
    double speed = 1.0,
  }) async {
    if (errorToThrow != null) {
      throw SarvamAIException(errorToThrow!);
    }
    ttsCallCount++;
    return 'https://example.com/audio.mp3';
  }

  @override
  Future<List<String>> batchTextToSpeech(
    List<String> texts, {
    String language = 'te',
    String gender = 'female',
  }) async {
    if (errorToThrow != null) {
      throw SarvamAIException(errorToThrow!);
    }
    return List.generate(texts.length, (_) => 'https://example.com/audio.mp3');
  }

  @override
  Future<bool> healthCheck() async => true;

  @override
  void dispose() {}
}

class FakeNewsService implements NewsService {
  bool initialized = false;
  List<Article> articles = [];
  int cacheClears = 0;

  @override
  void initialize({String? backendUrl}) {
    initialized = true;
  }

  @override
  Future<List<Article>> getAllNews({
    int limitPerSource = 20,
    String language = 'te',
  }) async =>
      articles;

  @override
  Future<List<Article>> getNewsBySource(
    String source, {
    int limit = 20,
    String language = 'te',
  }) async =>
      articles.where((a) => a.source == source).toList();

  @override
  Future<List<Article>> search(
    String query, {
    String language = 'te',
  }) async =>
      articles
          .where((a) => a.title.toLowerCase().contains(query.toLowerCase()))
          .toList();

  @override
  Future<List<Article>> getRecentNews({
    int days = 7,
    String language = 'te',
  }) async =>
      articles;

  @override
  void clearCache() {
    cacheClears++;
  }

  @override
  void dispose() {}
}
