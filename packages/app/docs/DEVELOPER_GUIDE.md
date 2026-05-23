# GatiVani Developer Guide

Complete guide for developers to set up, develop, test, and deploy GatiVani.

**Version**: 1.0.0  
**Last Updated**: May 2026  
**Target Audience**: Dart/Flutter developers

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Development Environment Setup](#development-environment-setup)
3. [Project Structure](#project-structure)
4. [Running Services Locally](#running-services-locally)
5. [Testing](#testing)
6. [Debugging](#debugging)
7. [Common Issues & Solutions](#common-issues--solutions)
8. [Development Workflow](#development-workflow)
9. [Code Style & Best Practices](#code-style--best-practices)

---

## Prerequisites

### Required Software

- **Flutter**: 3.0.0 or higher
- **Dart**: 3.0.0 or higher
- **Android Studio** (for Android development) or **Xcode** (for iOS)
- **Git**: Version control
- **VS Code** or **Android Studio**: IDE

### System Requirements

**macOS**:
```bash
# Check Dart/Flutter versions
dart --version
flutter --version

# Install Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Flutter
brew install flutter

# Or download from https://flutter.dev/docs/get-started/install/macos
```

**Linux**:
```bash
# Install Flutter
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:`pwd`/flutter/bin"
```

**Windows**:
- Download Flutter from https://flutter.dev/docs/get-started/install/windows
- Add Flutter to PATH

### API Credentials

You'll need credentials for:

1. **Firebase**
   - Google Cloud Project
   - Firebase Project ID
   - API Keys

2. **Sarvam AI**
   - API Key
   - Endpoint URL

3. **Google Gemini**
   - API Key

4. **News APIs**
   - TeluguNewsAPI credentials (if applicable)

---

## Development Environment Setup

### 1. Clone Repository

```bash
cd ~/Projects
git clone https://github.com/yourusername/gativani-app.git
cd gativani-app
```

### 2. Get Flutter Dependencies

```bash
# Get all pub packages
flutter pub get

# Run code generation (for freezed, json_serializable, etc.)
flutter pub run build_runner build

# Or with clean rebuild
flutter pub run build_runner clean
flutter pub run build_runner build --delete-conflicting-outputs
```

### 3. Configure Secrets

Create `lib/config/secrets.dart`:

```dart
class Secrets {
  // Firebase Configuration
  static const String firebaseApiKey = 'your-firebase-api-key';
  static const String firebaseAppId = 'your-app-id';
  static const String firebaseMessagingSenderId = 'your-messaging-sender-id';
  static const String firebaseProjectId = 'your-project-id';
  static const String firebaseStorageBucket = 'your-storage-bucket';
  static const String firebaseAuthDomain = 'your-auth-domain';
  static const String firebaseMeasurementId = 'your-measurement-id';

  // Sarvam AI Configuration
  static const String sarvamApiKey = 'your-sarvam-api-key';
  static const String sarvamEndpoint = 'https://api.sarvam.ai';
  static const String sarvamOcrModel = 'sarvam-ocr-v1';
  static const String sarvamTtsModel = 'sarvam-tts-v1';

  // Gemini Configuration
  static const String geminiApiKey = 'your-gemini-api-key';
  static const String geminiModel = 'gemini-pro';

  // Storage Configuration
  static const String firebaseStoragePath = 'gativani/';
}
```

### 4. Platform-Specific Setup

#### iOS

```bash
cd ios
pod install
cd ..

# Minimum iOS version: 13.0
# Open ios/Podfile and verify:
# platform :ios, '13.0'

# Run on iOS
flutter run -d iphone
```

#### Android

```bash
# Minimum Android version: API 21 (Android 5.0)
# Verify in android/app/build.gradle:
# minSdkVersion 21

# Enable multidex in android/app/build.gradle:
# multiDexEnabled true

flutter run
```

#### Web

```bash
# Chrome must be installed
flutter run -d chrome

# Or Firefox
flutter run -d firefox

# Or build for web
flutter build web
```

### 5. Verify Setup

```bash
# Check flutter doctor
flutter doctor

# Expected output:
# ✓ Flutter (Channel stable, 3.x.x, ...)
# ✓ Android toolchain
# ✓ Xcode (iOS)
# ✓ VS Code with Flutter extension
# ✓ Connected devices

# Run app in debug mode
flutter run
```

---

## Project Structure

### Directory Organization

```
lib/
├── main.dart                              # App entry point
│
├── config/
│   ├── app_config.dart                   # Configuration constants
│   └── secrets.dart                      # API credentials
│
├── services/                              # Business logic (Singleton pattern)
│   ├── firebase_service.dart             # Firebase integration
│   ├── sarvam_ai_service.dart            # OCR & TTS
│   ├── gemini_service.dart               # AI summarization
│   ├── storage_service.dart              # File storage
│   └── news_service.dart                 # News fetching
│
├── models/                                # Data models (TODO)
│   ├── article.dart
│   ├── newspaper.dart
│   └── user.dart
│
├── screens/                               # UI Screens (TODO)
│   ├── home_screen.dart
│   ├── player_screen.dart
│   └── search_screen.dart
│
├── widgets/                               # Reusable UI components (TODO)
│   ├── article_card.dart
│   ├── player_controls.dart
│   └── filter_panel.dart
│
├── providers/                             # State management (TODO)
│   ├── article_provider.dart
│   └── player_provider.dart
│
├── utils/
│   ├── cache_manager.dart               # Caching layer
│   └── extensions.dart                  # Extension methods
│
├── design/                                # Design system
│   ├── theme/
│   │   ├── colors.dart
│   │   ├── typography.dart
│   │   └── spacing.dart
│   └── widgets/
│
└── l10n/                                  # Internationalization (TODO)
    ├── app_en.arb
    ├── app_te.arb
    └── app_hi.arb

test/
├── services/                              # Service unit tests
│   ├── firebase_service_test.dart
│   ├── sarvam_ai_service_test.dart
│   ├── gemini_service_test.dart
│   ├── storage_service_test.dart
│   └── news_service_test.dart
│
├── mocks/                                 # Mock services for testing
│   └── mock_services.dart
│
└── fixtures/                              # Test data
    └── article_fixtures.dart
```

---

## Running Services Locally

### Firebase Emulator

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Initialize Firebase
firebase login
firebase init

# Start emulator
firebase emulators:start --import=./backup

# In app, connect to emulator
// In main.dart
if (kDebugMode) {
  FirebaseAuth.instance.useEmulator('localhost', 9099);
  FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
}
```

### Sarvam AI Mock Server

Create a local mock server for development:

```bash
# Create mock_server.js
npm init -y
npm install express body-parser

# mock_server.js
const express = require('express');
const app = express();
app.use(express.json());

app.post('/ocr', (req, res) => {
  res.json({ result: { text: 'Mock OCR text' } });
});

app.post('/tts', (req, res) => {
  res.json({ audios: [{ audioContent: 'data:audio/mp3;...' }] });
});

app.listen(8000, () => console.log('Mock server running'));
```

### Gemini Local Testing

```dart
// In secrets.dart for development
static const String geminiApiKey = 'test-key-for-development';

// Test summarization without API
Future<String> testSummarization() async {
  final testText = 'Government announces new policies...';
  final summary = await GeminiService().summarizeArticle(testText);
  print('Summary: $summary');
}
```

---

## Testing

### Running Tests

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/services/firebase_service_test.dart

# Run with coverage
flutter test --coverage

# Generate coverage report
lcov --list coverage/lcov.info
```

### Writing Unit Tests

```dart
// test/services/my_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gativani/services/my_service.dart';

void main() {
  group('MyService', () {
    late MyService service;
    
    setUp(() {
      service = MyService();
    });
    
    test('initialization sets flag', () async {
      expect(service.initialized, false);
      await service.initialize();
      expect(service.initialized, true);
    });
    
    test('operation returns expected result', () async {
      final result = await service.operation();
      expect(result, isNotNull);
    });
    
    test('exception is thrown on error', () async {
      expect(
        () => service.failingOperation(),
        throwsA(isA<ServiceException>()),
      );
    });
  });
}
```

### Mocking Services

```dart
// Using mockito
import 'package:mockito/mockito.dart';

class MockNewsService extends Mock implements NewsService {}

void main() {
  test('UI shows articles from service', () async {
    final mockNews = MockNewsService();
    
    when(mockNews.getAllNews()).thenAnswer(
      (_) async => [testArticle],
    );
    
    final articles = await mockNews.getAllNews();
    expect(articles.length, 1);
  });
}
```

### Test Fixtures

```dart
// test/fixtures/article_fixtures.dart
final testArticle = Article(
  title: 'Test Article',
  source: 'Sakshi',
  url: 'https://example.com',
  imageUrl: 'https://example.com/image.jpg',
  fetchedAt: DateTime.now(),
  language: 'te',
);

final testArticles = [testArticle, testArticle];
```

---

## Debugging

### Debug Mode

```bash
# Run in debug mode (default)
flutter run

# Debug with verbose output
flutter run -v

# Debug on physical device
flutter run -d <device-id>
```

### DevTools

```bash
# Open DevTools
flutter pub global activate devtools
devtools

# Or integrated with IDE
# VS Code: Run > Open DevTools
# Android Studio: Run > Open DevTools
```

### Logging

```dart
// Using logger package
import 'package:logger/logger.dart';

final logger = Logger();

logger.d('Debug message');
logger.i('Info message');
logger.w('Warning message');
logger.e('Error message', error, stackTrace);

// Using print (development only)
if (AppConfig.enableLogging) {
  print('Debug info: $info');
}
```

### Breakpoints & Step Debugging

```dart
// Set breakpoint in IDE (click line number)
void myFunction() {
  int x = 5;  // ← Click here to set breakpoint
  return x * 2;
}

// Run in debug mode and step through code
```

### Performance Monitoring

```dart
// Measure execution time
final stopwatch = Stopwatch()..start();

final articles = await newsService.getAllNews();

stopwatch.stop();
print('Fetch took ${stopwatch.elapsedMilliseconds}ms');
```

---

## Common Issues & Solutions

### Issue 1: Build Runner Conflicts

**Problem**: `flutter pub run build_runner build` fails with conflicts

**Solution**:
```bash
# Clean and rebuild
flutter pub run build_runner clean
flutter pub run build_runner build --delete-conflicting-outputs

# Or update all dependencies
flutter pub upgrade
```

### Issue 2: Pod Installation Failure (iOS)

**Problem**: `pod install` fails in iOS setup

**Solution**:
```bash
cd ios

# Clean pods
rm Podfile.lock
rm -rf Pods

# Update pod repo
pod repo update

# Reinstall
pod install

cd ..
```

### Issue 3: Firebase Initialization Error

**Problem**: `FirebaseInitializationException: Failed to initialize Firebase`

**Solution**:
```dart
// Check secrets are properly set
print('Firebase Project: ${Secrets.firebaseProjectId}');

// Verify Firebase is configured for your project
// https://console.firebase.google.com

// Check platform-specific configuration:
// iOS: GoogleService-Info.plist
// Android: google-services.json
```

### Issue 4: API Key Errors

**Problem**: `401 Unauthorized` or API key errors

**Solution**:
```dart
// Verify secrets.dart has correct keys
// Check API key permissions in respective console
// Ensure API is enabled in Google Cloud/Sarvam AI console
// Check IP restrictions if applicable

// Test with hardcoded key temporarily
static const String testApiKey = 'test-key';
```

### Issue 5: Network Timeout

**Problem**: API calls timeout frequently

**Solution**:
```dart
// Increase timeout in AppConfig
class AppConfig {
  static const int networkTimeoutSeconds = 60;  // Was 30
}

// Or per-request:
await _client.get(
  '/endpoint',
  options: Options(
    sendTimeout: Duration(seconds: 60),
    receiveTimeout: Duration(seconds: 60),
  ),
);
```

### Issue 6: Cache Issues

**Problem**: Stale cached data being served

**Solution**:
```dart
// Clear cache
await CacheManager().clear();

// Or specific key
await CacheManager().remove('cache_key');

// Check cache stats
final stats = CacheManager().getStats();
print('Cache size: ${stats['memoryCacheSize']}');
```

---

## Development Workflow

### Feature Development Workflow

```
1. Create feature branch
   git checkout -b feature/feature-name

2. Set up dependencies
   flutter pub get

3. Create/update service
   lib/services/my_service.dart

4. Write unit tests
   test/services/my_service_test.dart

5. Test locally
   flutter test

6. Create screens/widgets
   lib/screens/my_screen.dart
   lib/widgets/my_widget.dart

7. Integrate with state management
   lib/providers/my_provider.dart

8. Manual testing
   flutter run

9. Code review and commit
   git add .
   git commit -m "feat: add feature-name"

10. Push and create PR
    git push origin feature/feature-name
```

### Commit Message Convention

```
feat: add new feature
fix: fix bug in service
docs: update documentation
refactor: refactor code structure
test: add unit tests
chore: update dependencies
style: format code
```

### Pull Request Checklist

- [ ] Tests pass (`flutter test`)
- [ ] Code is formatted (`flutter format .`)
- [ ] No analyzer issues (`flutter analyze`)
- [ ] Documentation updated
- [ ] Secrets not committed
- [ ] Version updated (if applicable)

---

## Code Style & Best Practices

### Dart Style Guide

```dart
// 1. Use meaningful variable names
final articlesFromYesterday = articles
    .where((a) => a.fetchedAt.isBefore(DateTime.now().subtract(Duration(days: 1))))
    .toList();

// ✓ GOOD
// ✗ BAD: articles.where((a) => ...)

// 2. Use const constructors
final colors = const [Colors.red, Colors.green];

// 3. Use async/await instead of .then()
final articles = await newsService.getAllNews();

// ✗ AVOID:
// newsService.getAllNews().then((articles) { ... });

// 4. Use null coalescing
final name = user?.name ?? 'Unknown';

// 5. Use final by default, var for closures only
final user = User(); // final
var x = 0; // var only if type is obvious

// 6. Use string interpolation
print('User: ${user.name}'); // GOOD
print('User: ' + user.name); // Avoid concatenation

// 7. Format code
flutter format lib/ test/

// 8. Use effective Dart naming
class ArticleProvider {} // PascalCase
final myVariable = 'value'; // camelCase
const MAX_ATTEMPTS = 3; // UPPER_CASE for constants
```

### Service Implementation Template

```dart
/// [ServiceName] - Purpose and description
/// Handles [specific functionality]
/// 
/// Pattern: Singleton for efficient resource management
/// 
/// Example:
/// ```dart
/// final service = MyService();
/// await service.initialize();
/// final result = await service.operation();
/// ```

class MyService {
  static final MyService _instance = MyService._internal();

  factory MyService() => _instance;

  MyService._internal();

  late Client _client;
  bool initialized = false;

  /// Initialize service with configuration
  Future<void> initialize() async {
    if (initialized) return;
    try {
      _client = Client();
      initialized = true;
      if (AppConfig.enableLogging) {
        print('MyService initialized');
      }
    } catch (e) {
      throw ServiceException('Initialization failed: $e');
    }
  }

  /// Main operation with proper error handling
  Future<Result> operation(String param) async {
    try {
      _validateInput(param);
      return await _performOperation(param);
    } on ValidationException {
      rethrow;
    } on ClientException catch (e) {
      throw ServiceException('Operation failed: ${e.message}');
    } catch (e) {
      throw ServiceException('Unexpected error: $e');
    }
  }

  void _validateInput(String param) {
    if (param.isEmpty) {
      throw ValidationException('Parameter cannot be empty');
    }
  }

  Future<Result> _performOperation(String param) async {
    // Implementation
  }

  void dispose() {
    _client.close();
  }
}

class ServiceException implements Exception {
  final String message;
  ServiceException(this.message);
  @override
  String toString() => 'ServiceException: $message';
}
```

### Error Handling Best Practices

```dart
// 1. Use try-catch for service calls
try {
  final result = await service.operation();
} on ServiceException catch (e) {
  // Handle known error
  print('Service error: ${e.message}');
} catch (e) {
  // Handle unexpected error
  print('Unexpected error: $e');
  rethrow; // Re-throw for caller to handle
}

// 2. Provide meaningful error messages
throw ServiceException(
  'Failed to fetch articles: API returned ${response.statusCode}'
);

// 3. Use custom exceptions, not generic Exception
// ✓ GOOD: throw ServiceException('message')
// ✗ AVOID: throw Exception('message')

// 4. Don't swallow exceptions silently
// ✗ AVOID:
// try {
//   operation();
// } catch (e) {
//   // Silent failure
// }

// ✓ GOOD:
try {
  operation();
} catch (e) {
  if (AppConfig.enableLogging) print('Error: $e');
  rethrow;
}
```

### Testing Best Practices

```dart
// 1. Use descriptive test names
test('getAllNews returns list of articles', () async {
  // test implementation
});

// 2. Follow AAA pattern (Arrange, Act, Assert)
test('service caches articles', () async {
  // ARRANGE
  final service = NewsService();
  
  // ACT
  final result = await service.getAllNews();
  
  // ASSERT
  expect(result, isNotEmpty);
});

// 3. Test error cases
test('throws exception on API error', () async {
  expect(
    () => service.failingOperation(),
    throwsA(isA<ServiceException>()),
  );
});

// 4. Mock external dependencies
final mockService = MockNewsService();
when(mockService.getAllNews()).thenAnswer((_) async => testArticles);
```

---

## Resources

### Official Documentation
- [Flutter Docs](https://flutter.dev/docs)
- [Dart Language](https://dart.dev)
- [Firebase for Flutter](https://firebase.flutter.dev)
- [Android Studio Guide](https://developer.android.com/studio)
- [Xcode Help](https://developer.apple.com/xcode)

### Libraries
- [Dio HTTP Client](https://pub.dev/packages/dio)
- [Provider State Management](https://pub.dev/packages/provider)
- [Hive Local Storage](https://pub.dev/packages/hive)
- [Firebase Packages](https://pub.dev/publishers/firebase.google.com)

### Useful Tools
- [FlutterFlow](https://flutterflow.io) - Visual UI builder
- [Firebase Emulator](https://firebase.google.com/docs/emulator-suite)
- [Dart DevTools](https://dart.dev/tools/dart-devtools)
- [JSON to Dart](https://javiercbk.github.io/json_to_dart)

---

## Getting Help

- **GitHub Issues**: Report bugs and request features
- **Discussions**: Ask questions and share ideas
- **Email**: developer-support@example.com
- **Slack Community**: Join development channel

---

**Happy Coding!**
