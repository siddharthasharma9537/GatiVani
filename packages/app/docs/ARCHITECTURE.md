# GatiVani Architecture Guide

Comprehensive documentation of GatiVani's system architecture, design patterns, and data flow.

**Version**: 1.0.0  
**Last Updated**: May 2026  
**Status**: Production Ready

---

## Table of Contents

1. [High-Level Architecture](#high-level-architecture)
2. [Service Architecture](#service-architecture)
3. [Design Patterns](#design-patterns)
4. [Data Flow](#data-flow)
5. [Dependency Injection](#dependency-injection)
6. [Error Handling Strategy](#error-handling-strategy)
7. [Caching Architecture](#caching-architecture)
8. [Security Architecture](#security-architecture)

---

## High-Level Architecture

### System Overview

GatiVani follows a **Layered Architecture** with clear separation of concerns:

```
┌─────────────────────────────────────────────┐
│         Flutter UI Layer                     │
│  (Screens, Widgets, State Management)        │
└─────────────────────────────────────────────┘
                    ↕
┌─────────────────────────────────────────────┐
│      Application Service Layer               │
│  (Business Logic, Orchestration)             │
└─────────────────────────────────────────────┘
                    ↕
┌─────────────────────────────────────────────┐
│    Data & External Service Layer             │
│  (APIs, Storage, Caching)                    │
└─────────────────────────────────────────────┘
                    ↕
┌─────────────────────────────────────────────┐
│         External Services                    │
│  (Firebase, Sarvam AI, Gemini, News API)     │
└─────────────────────────────────────────────┘
```

---

### Directory Structure

```
lib/
├── main.dart                           # App entry point
├── config/
│   ├── app_config.dart                # Configuration constants
│   └── secrets.dart                   # API credentials & secrets
├── services/                           # Business logic layer
│   ├── firebase_service.dart          # Firebase integration
│   ├── sarvam_ai_service.dart         # OCR & TTS
│   ├── gemini_service.dart            # AI summarization
│   ├── storage_service.dart           # File storage
│   └── news_service.dart              # News fetching
├── models/                             # Data models (todo)
├── screens/                            # UI screens (todo)
├── widgets/                            # Reusable components (todo)
├── providers/                          # State management (todo)
├── utils/
│   └── cache_manager.dart             # Caching layer
├── design/                             # Design system
│   └── theme/
│       └── colors.dart                # Color palette
└── l10n/                               # Internationalization (todo)

test/
├── services/                           # Service tests
├── mocks/                              # Mock services
└── fixtures/                           # Test data
```

---

## Service Architecture

### Five Core Services

#### 1. Firebase Service

**Purpose**: Authentication, Analytics, Push Notifications  
**Pattern**: Singleton  
**Dependencies**: Firebase Core, Firebase Analytics, Firebase Messaging

```
┌──────────────────────────┐
│   FirebaseService        │
├──────────────────────────┤
│ - initialize()           │
│ - logEvent()             │
│ - logScreenView()        │
│ - getFCMToken()          │
└──────────────────────────┘
          ↓
   ┌─────────────────┐
   │ Firebase Backend│
   └─────────────────┘
```

**Flow**:
1. App initializes → `FirebaseService().initialize()`
2. Log events → `logEvent('event_name', parameters)`
3. Track screens → `logScreenView('screen_name')`
4. Get notifications → `getFCMToken()`

---

#### 2. Sarvam AI Service

**Purpose**: OCR (Text Extraction), TTS (Text-to-Speech)  
**Pattern**: Singleton  
**Dependencies**: Dio (HTTP client)

```
┌──────────────────────────┐
│  SarvamAIService         │
├──────────────────────────┤
│ - initialize()           │
│ - extractTextFromImage() │
│ - textToSpeech()         │
│ - batchTextToSpeech()    │
│ - healthCheck()          │
└──────────────────────────┘
          ↓
   ┌─────────────────┐
   │  Sarvam AI API  │
   └─────────────────┘
```

**Input/Output**:
- **Input**: Image file (PNG, JPG) or text string
- **Output**: Extracted text (OCR) or audio URL (TTS)
- **Languages**: Telugu, English, Hindi, Kannada, Tamil

---

#### 3. Gemini Service

**Purpose**: Article Summarization, Audio Script Generation  
**Pattern**: Singleton  
**Dependencies**: Google Generative AI SDK

```
┌──────────────────────────┐
│   GeminiService          │
├──────────────────────────┤
│ - initialize()           │
│ - summarizeArticle()     │
│ - generateAudioScript()  │
│ - batchSummarize()       │
└──────────────────────────┘
          ↓
   ┌──────────────────┐
   │ Gemini API       │
   └──────────────────┘
```

**Processing Pipeline**:
```
Article Text → Prompt Engineering → Gemini API → Summary/Script
```

---

#### 4. Storage Service

**Purpose**: File Upload/Download, Metadata Management  
**Pattern**: Singleton  
**Dependencies**: Firebase Storage

```
┌──────────────────────────┐
│   StorageService         │
├──────────────────────────┤
│ - uploadAudio()          │
│ - uploadImage()          │
│ - downloadFile()         │
│ - deleteFile()           │
│ - getFileMetadata()      │
│ - listFiles()            │
└──────────────────────────┘
          ↓
   ┌──────────────────────┐
   │ Firebase Storage     │
   │ (gs://bucket-name)   │
   └──────────────────────┘
```

**Storage Structure**:
```
gs://bucket/
├── audio/              # Generated audio files
│   └── source-title-timestamp.mp3
├── images/             # Article images
│   └── imagename-timestamp.jpg
└── metadata/           # Associated metadata
```

---

#### 5. News Service

**Purpose**: Article Fetching, Caching, Search  
**Pattern**: Singleton with internal caching  
**Dependencies**: Dio (HTTP client)

```
┌──────────────────────────┐
│    NewsService           │
├──────────────────────────┤
│ - getAllNews()           │
│ - getNewsBySource()      │
│ - search()               │
│ - getRecentNews()        │
│ - clearCache()           │
└──────────────────────────┘
       ↕ ↕ ↕ ↕ ↕
  ┌─────────────────────┐
  │  Newspaper APIs     │
  │  (TeluguNewsAPI,    │
  │   NewsAPI, etc.)    │
  └─────────────────────┘
```

**Caching Strategy**:
- Cache key: `source_limit_language`
- Cache duration: 30 minutes (configurable)
- Fallback: Return empty list on cache miss

---

### Service Lifecycle

```
App Start
    ↓
Initialize Services
    ├── FirebaseService.initialize()
    ├── SarvamAIService.initialize()
    ├── GeminiService.initialize()
    ├── StorageService.initialize()
    └── NewsService.initialize()
    ↓
App Ready
    ↓
Services Available for Use
    ├── Log events (Firebase)
    ├── Extract text (Sarvam AI)
    ├── Summarize (Gemini)
    ├── Upload/download files (Storage)
    └── Fetch news (News Service)
    ↓
App Shutdown
    ├── Cleanup resources
    └── Close connections
```

---

## Design Patterns

### 1. Singleton Pattern

All services use singleton pattern for resource efficiency and consistency.

**Implementation**:
```dart
class ServiceName {
  static final ServiceName _instance = ServiceName._internal();
  
  factory ServiceName() => _instance;
  
  ServiceName._internal();
  
  // Service methods...
}
```

**Usage**:
```dart
// Always returns same instance
final service1 = ServiceName();
final service2 = ServiceName();
assert(identical(service1, service2)); // true
```

**Benefits**:
- Single connection/state per service
- Memory efficient
- Thread-safe initialization
- Easy access from anywhere

---

### 2. Dependency Injection (Manual)

Services are manually injected into providers/widgets.

**Current Implementation**:
```dart
// Direct instantiation
final firebaseService = FirebaseService();

// Or with GetIt (to implement)
final getIt = GetIt.instance;
getIt.registerSingleton<FirebaseService>(FirebaseService());
```

**Future Pattern (GetIt)**:
```dart
// In main.dart initialization
void setupServiceLocator() {
  getIt.registerSingleton<FirebaseService>(FirebaseService());
  getIt.registerSingleton<SarvamAIService>(SarvamAIService());
  getIt.registerSingleton<GeminiService>(GeminiService());
  getIt.registerSingleton<StorageService>(StorageService());
  getIt.registerSingleton<NewsService>(NewsService());
}

// In widgets/providers
final firebaseService = getIt<FirebaseService>();
```

---

### 3. Repository Pattern

Services act as repositories, abstracting data source details.

```
UI Layer
    ↓
Repository Layer (Services)
    ↓ (hide implementation)
Data Sources (APIs, Storage)
```

**Service as Repository**:
```dart
// NewsService acts as repository for news data
class NewsService {
  // Abstracts TeluguNewsAPI details
  Future<List<Article>> getAllNews() async {
    // Internal implementation hidden
    // Could switch data source without affecting UI
  }
}
```

---

### 4. Observer Pattern (with Provider)

State changes are observed and propagated using Provider.

```
Service (Observable)
    ↓ (notifies)
Provider (Observer)
    ↓ (updates)
UI Widgets (Observers)
```

---

## Data Flow

### Complete Article Processing Flow

```
┌────────────────────────────────────────────────────────────────┐
│  User Opens Article                                            │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│  1. FETCH NEWS                                                 │
│  NewsService.getAllNews() / getNewsBySource()                  │
│  Cache check: 30-minute TTL                                    │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│  2. EXTRACT TEXT (if image/PDF)                                │
│  SarvamAIService.extractTextFromImage()                        │
│  Input: Image path                                             │
│  Output: Extracted text                                        │
│  Languages: te, en, hi, kn, ta                                 │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│  3. SUMMARIZE ARTICLE                                          │
│  GeminiService.summarizeArticle()                              │
│  Input: Full text                                              │
│  Output: 300-500 word summary                                  │
│  Use case: Quick news digest                                   │
└────────────────────────────────────────────────────────────────┘
          ↓ (OR)                                         ↓
┌──────────────────────────┐        ┌──────────────────────────┐
│  4A. AUDIO SCRIPT        │        │  4B. DIRECT TTS          │
│  GeminiService.          │        │  SarvamAIService.        │
│  generateAudioScript()   │        │  textToSpeech()          │
│  Output: 30-min script   │        │  Output: Audio URL       │
└──────────────────────────┘        └──────────────────────────┘
          ↓                                  ↓
┌────────────────────────────────────────────────────────────────┐
│  5. TEXT-TO-SPEECH                                             │
│  SarvamAIService.textToSpeech()                                │
│  Input: Script or summary                                      │
│  Output: Audio URL                                             │
│  Batch processing: Multiple articles                           │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│  6. STORE AUDIO                                                │
│  StorageService.uploadAudio()                                  │
│  Path: gs://bucket/audio/{source}-{title}-{timestamp}.mp3     │
│  Metadata: articleTitle, source, uploadedAt                    │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│  7. CACHE & TRACK                                              │
│  CacheManager.set() - Cache file URL                           │
│  FirebaseService.logEvent('audio_generated', metadata)         │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│  8. PLAYBACK                                                   │
│  Use just_audio to play from URL                               │
│  FirebaseService.logEvent('audio_played')                      │
└────────────────────────────────────────────────────────────────┘
```

### Data Model Flow

```
API Response
    ↓ (JSON)
Article Model
    ├── title: String
    ├── source: String
    ├── url: String
    ├── imageUrl: String?
    ├── fetchedAt: DateTime
    └── language: String
    ↓
Provider/State Management
    ↓
UI Widgets (HomeScreen, PlayerScreen)
```

---

## Dependency Injection

### Current Manual Approach

```dart
// Services are directly instantiated where needed
final newsService = NewsService();
final articles = await newsService.getAllNews();
```

### Recommended: GetIt Service Locator

**Setup in main.dart**:
```dart
import 'package:get_it/get_it.dart';

final getIt = GetIt.instance;

void setupServiceLocator() {
  // Register all services
  getIt.registerSingleton<FirebaseService>(FirebaseService());
  getIt.registerSingleton<SarvamAIService>(SarvamAIService());
  getIt.registerSingleton<GeminiService>(GeminiService());
  getIt.registerSingleton<StorageService>(StorageService());
  getIt.registerSingleton<NewsService>(NewsService());
  getIt.registerSingleton<CacheManager>(CacheManager());
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize cache
  await getIt<CacheManager>().initialize();
  
  // Initialize services
  setupServiceLocator();
  await getIt<FirebaseService>().initialize();
  getIt<SarvamAIService>().initialize();
  getIt<GeminiService>().initialize();
  getIt<StorageService>().initialize();
  getIt<NewsService>().initialize();
  
  runApp(MyApp());
}
```

**Usage in Widgets**:
```dart
class ArticleListWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final newsService = getIt<NewsService>();
    
    return FutureBuilder(
      future: newsService.getAllNews(),
      builder: (context, snapshot) {
        // Build UI
      },
    );
  }
}
```

---

## Error Handling Strategy

### Exception Hierarchy

```
Exception
├── FirebaseInitializationException
├── SarvamAIException
├── GeminiException
├── StorageException
└── NewsException
```

### Error Handling Flow

```
Service Method Call
    ↓
Try Block
    ├── On API Error
    │   └── Throw CustomException(message)
    ├── On Network Error
    │   └── Throw CustomException(message)
    └── On Unexpected Error
        └── Throw CustomException(message)
    ↓
Catch Block (Caller)
    ├── On CustomException
    │   ├── Log error
    │   ├── Show user-friendly message
    │   └── Try fallback/retry
    └── On Unexpected Error
        └── Log and report
```

### Error Recovery Strategies

**1. Retry with Exponential Backoff**:
```dart
Future<T> retryOperation<T>(
  Future<T> Function() operation,
  {int maxAttempts = 3}
) async {
  int attempt = 1;
  while (attempt <= maxAttempts) {
    try {
      return await operation();
    } catch (e) {
      if (attempt == maxAttempts) rethrow;
      await Future.delayed(
        Duration(seconds: (2 * attempt).toInt())
      );
      attempt++;
    }
  }
}
```

**2. Fallback Options**:
```dart
// If Sarvam AI TTS fails, try Gemini
Future<String> textToSpeech(String text) async {
  try {
    return await SarvamAIService().textToSpeech(text);
  } catch (e) {
    // Fallback: Use different provider
    print('Sarvam AI failed, trying fallback...');
    // Could use Google Cloud TTS, etc.
    rethrow;
  }
}
```

**3. Graceful Degradation**:
```dart
// Show cached data if API fails
final articles = await CacheManager().getOrCompute(
  'news_cache',
  () => NewsService().getAllNews(),
  ttl: Duration(hours: 1),
);
```

---

## Caching Architecture

### Two-Tier Caching System

```
┌─────────────────────────────────────────┐
│   Request for Data                       │
└─────────────────────────────────────────┘
                  ↓
        Check Memory Cache (L1)
                  ↓
        ┌─────────────────┐
        │ Found & Valid?  │
        └────────┬────────┘
           Yes ↙   ↘ No
            ↓       ↓
        Return  Check Persistent
                Cache (Hive)
                    ↓
            ┌───────────────┐
            │ Found & Valid?│
            └────────┬──────┘
               Yes ↙   ↘ No
                ↓       ↓
            Return  Fetch from API
            & Cache   & Cache
```

### Memory Cache

**Type**: LRU (Least Recently Used)  
**Max Size**: 100 items  
**TTL**: Optional (no expiration if null)  
**Eviction**: Removes least recently used item when full

```dart
// Usage
await CacheManager().set(
  'article_123',
  articleData,
  ttl: Duration(hours: 1),
);

final data = await CacheManager().get('article_123');
```

### Persistent Cache

**Type**: Hive-backed local storage  
**Location**: Device local storage  
**TTL**: Optional expiration support  
**Survives**: App restart, process termination

```dart
// Initialize
await CacheManager().initialize();

// Cache with TTL
await CacheManager().set(
  'news_list',
  articles,
  ttl: Duration(hours: 1),
  persistToHive: true,
);

// Check stats
final stats = CacheManager().getStats();
```

### Cache Invalidation Strategies

**1. Time-Based (TTL)**:
```dart
await CacheManager().set(
  'key',
  value,
  ttl: Duration(minutes: 30),
);
```

**2. Manual Invalidation**:
```dart
await CacheManager().remove('specific_key');
```

**3. Pattern-Based Invalidation**:
```dart
await CacheManager().invalidatePattern(
  RegExp('news_.*')
);
```

**4. Full Clear**:
```dart
await CacheManager().clear();
```

---

## Security Architecture

### Data Security

**1. API Key Management**:
- Store in `lib/config/secrets.dart`
- Never commit to version control
- Use environment variables in production
- Rotate keys regularly

**2. HTTPS Only**:
```dart
// All API calls use HTTPS
final client = Dio(
  BaseOptions(
    baseUrl: 'https://api.example.com',
  ),
);
```

**3. Input Validation**:
```dart
// Validate before processing
if (articleText.isEmpty) {
  throw GeminiException('Article text cannot be empty');
}
```

### Storage Security

**1. Firebase Storage Rules**:
```
// Only authenticated users can read/write
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /audio/{allPaths=**} {
      allow read, write: if request.auth != null;
    }
    match /images/{allPaths=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

**2. File Permissions**:
- Audio/image files stored with user/app ownership
- Metadata includes upload timestamp
- Delete old files on regular schedule

### Network Security

**1. Timeout Configuration**:
```dart
AppConfig.networkTimeoutSeconds = 30  // 30-second timeout
```

**2. Retry Policy**:
```dart
AppConfig.networkRetryAttempts = 3     // Retry up to 3 times
AppConfig.networkRetryDelay = Duration(seconds: 2)
```

**3. Error Logging** (secure):
```dart
// Log errors without exposing sensitive data
try {
  await operation();
} catch (e) {
  if (AppConfig.enableLogging) {
    print('Error: ${e.message}'); // Message only, not full error
  }
}
```

---

## Performance Considerations

### Optimization Strategies

**1. Lazy Loading**:
```dart
// Load articles on-demand
Future.delayed(Duration(seconds: 1), () {
  newsService.getAllNews();
});
```

**2. Batch Operations**:
```dart
// Process multiple items efficiently
final summaries = await GeminiService().batchSummarize(
  articles,
  language: 'te',
);
```

**3. Caching Strategy**:
```dart
// Aggressive caching for frequently accessed data
await CacheManager().set(
  'all_news',
  articles,
  ttl: Duration(hours: 1),
);
```

**4. Connection Reuse**:
```dart
// Services reuse HTTP connections via Dio
// Singleton pattern ensures single client instance
```

---

## Testing Architecture

### Test Structure

```
test/
├── services/
│   ├── firebase_service_test.dart
│   ├── sarvam_ai_service_test.dart
│   ├── gemini_service_test.dart
│   ├── storage_service_test.dart
│   └── news_service_test.dart
├── mocks/
│   └── mock_services.dart
└── fixtures/
    └── article_fixtures.dart
```

### Mock Services

```dart
// Fake service for testing
class FakeNewsService extends NewsService {
  @override
  Future<List<Article>> getAllNews() async {
    return [
      Article(title: 'Test', source: 'Test', ...)
    ];
  }
}
```

---

## Summary

GatiVani architecture emphasizes:
- **Separation of Concerns**: Clear service boundaries
- **Singleton Pattern**: Efficient resource usage
- **Error Handling**: Robust exception strategy
- **Caching**: Multi-tier caching for performance
- **Security**: API key management, input validation
- **Testability**: Mock services, fixtures, unit tests
