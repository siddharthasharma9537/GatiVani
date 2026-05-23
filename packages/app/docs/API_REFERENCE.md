# GatiVani API Reference

> **Version:** 1.0.0 | **Target SDK:** Dart ≥ 3.0.0 · Flutter ≥ 3.22.0

---

## Table of Contents

1. [Overview](#overview)
2. [NewsService](#newsservice)
3. [GeminiService](#geminiservice)
4. [SarvamAIService](#sarvamaiservice)
5. [FirebaseService](#firebaseservice)
6. [StorageService](#storageservice)
7. [CacheManager](#cachemanager)
8. [Core Utilities](#core-utilities)
   - [ServiceLogger](#servicelogger)
   - [RetryExecutor and CircuitBreaker](#retryexecutor-and-circuitbreaker)
   - [Exception Hierarchy](#exception-hierarchy)
   - [Result wrapper](#resultt)
9. [Data Models](#data-models)
10. [Configuration Reference](#configuration-reference)
11. [Error Codes](#error-codes)

---

## Overview

GatiVani's service layer is organized as five independently initializable singletons, each wrapping a distinct external dependency. All async methods throw typed subclasses of `ServiceException` on failure. Cross-cutting concerns (caching, logging, retry, circuit-breaking) are provided by shared core utilities.

```
┌─────────────────────────────────────────────────────────┐
│                      AppConfig / Secrets                │
└───────────────────────────┬─────────────────────────────┘
                            │
          ┌─────────────────┼─────────────────────┐
          │                 │                     │
    NewsService       GeminiService        SarvamAIService
  (Telugu news)    (AI summarization)    (OCR + TTS)
          │                 │                     │
          └────────┬────────┘                     │
                   │                              │
            FirebaseService               StorageService
          (Analytics + FCM)             (Audio + Images)

Cross-cutting:  CacheManager · ServiceLogger · RetryExecutor · CircuitBreaker
```

### Singleton pattern

Every service uses a private named constructor and a static instance:

```dart
// Always returns the same object
final news = NewsService();
final gemini = GeminiService();
```

Services must be initialized before use. The recommended sequence in `main()`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseService().initialize();   // must be first
  StorageService().initialize();
  SarvamAIService().initialize();
  GeminiService().initialize();
  NewsService().initialize();
  await CacheManager().initialize();
  runApp(const ProviderScope(child: GatiVaniApp()));
}
```

---

## NewsService

**File:** `lib/services/news_service.dart`

### Initialization

```dart
NewsService().initialize({String? backendUrl});
```

| Parameter    | Type      | Required | Description                                 |
|-------------|-----------|----------|---------------------------------------------|
| `backendUrl` | `String?` | No       | Override base URL for the TeluguNewsAPI proxy |

Creates a `Dio` HTTP client with:
- Connection and receive timeouts from `AppConfig.networkTimeoutSeconds` (30 s)
- `Content-Type: application/json`
- `LogInterceptor` when both `AppConfig.isDemo` and `AppConfig.enableLogging` are true

---

### `getAllNews`

```dart
Future<List<Article>> getAllNews({
  int limitPerSource = 20,
  String language = 'te',
}) async
```

Fetches from every source in `AppConfig.newspaperSources`. Results are in-memory cached for `AppConfig.newsCacheDurationMinutes` (30 min). Cache key: `all_{limitPerSource}_{language}`.

Individual source failures are swallowed (with optional logging); the method only throws if the overall orchestration fails.

**Returns:** `List<Article>` — merged across all sources.  
**Throws:** `NewsException`

---

### `getNewsBySource`

```dart
Future<List<Article>> getNewsBySource(
  String source, {
  int limit = 20,
  String language = 'te',
}) async
```

Fetches articles from a single named source. Cache key: `{source}_{limit}`.

| Parameter  | Type     | Default | Description                              |
|-----------|---------|---------|------------------------------------------|
| `source`  | `String` | —       | e.g. `'Andhra Jyothi'`                  |
| `limit`   | `int`   | `20`    | Maximum articles to return               |
| `language`| `String` | `'te'`  | BCP-47 code (`te`, `en`, `hi`)          |

**Throws:** `NewsException`

---

### `search`

```dart
Future<List<Article>> search(
  String query, {
  String language = 'te',
}) async
```

Case-insensitive substring match on `title` and `source` fields of all cached/fetched articles. Calls `getAllNews` internally.

---

### `getRecentNews`

```dart
Future<List<Article>> getRecentNews({
  int days = 7,
  String language = 'te',
}) async
```

Returns articles whose `fetchedAt` falls within the last `days` days.

---

### `clearCache`

```dart
void clearCache()
```

Evicts all in-memory news cache entries.

---

### `dispose`

```dart
void dispose()
```

Closes the `Dio` client and calls `clearCache()`. Call on app teardown.

---

## GeminiService

**File:** `lib/services/gemini_service.dart`  
**Package:** `google_generative_ai`  
**Model:** `Secrets.geminiModel` (default: `gemini-pro`)

### Initialization

```dart
GeminiService().initialize();
```

Creates a `GenerativeModel` with `Secrets.geminiApiKey`.

---

### `summarizeArticle`

```dart
Future<String> summarizeArticle(
  String articleText, {
  String language = 'te',
  int maxLength = 500,
}) async
```

Sends `articleText` to Gemini with a podcast-optimized prompt that instructs the model to produce natural spoken language, remove filler, and stay within `maxLength` words.

| Parameter     | Type     | Default | Description                                |
|--------------|---------|---------|---------------------------------------------|
| `articleText` | `String` | —       | Raw article body; **must not be empty**    |
| `language`   | `String` | `'te'`  | Target language (`te`, `en`, `hi`)         |
| `maxLength`  | `int`   | `500`   | Approximate word count cap                  |

**Prompt instructions sent to Gemini:**
- Podcast / audio delivery style
- Preserve key information and direct quotes
- Use natural spoken language (not formal written prose)
- Remove repetition and filler content

**Returns:** Summary string ready for TTS input.  
**Throws:** `GeminiException` — on empty input, API error, or timeout.

---

### `generateAudioScript`

```dart
Future<String> generateAudioScript(
  String articleText, {
  String language = 'te',
  int durationMinutes = 30,
}) async
```

Generates a full podcast-style narration script. Word count target = `durationMinutes × 130` (approximate speaking rate). The prompt requests intro, key points, quotes, conclusion, and `[PAUSE]` markers.

**Throws:** `GeminiException`

---

### `batchSummarize`

```dart
Future<List<String>> batchSummarize(
  List<String> articles, {
  String language = 'te',
  int maxLength = 500,
}) async
```

Sequentially summarizes each article. Returns summaries in input order. Throws on the first failure.

> For large batches use `BatchRetryExecutor` from `lib/services/core/retry_strategy.dart` to parallelize with controlled concurrency and per-item failure isolation.

---

### Language mapping

| Code | Language |
|------|---------|
| `te` | Telugu (default / fallback) |
| `en` | English |
| `hi` | Hindi |
| other | Falls back to Telugu |

---

## SarvamAIService

**File:** `lib/services/sarvam_ai_service.dart`  
**Base URL:** `Secrets.sarvamEndpoint` (`https://api.sarvam.ai`)  
**Auth:** `API-Subscription-Key: {Secrets.sarvamApiKey}` header on every request

### Initialization

```dart
SarvamAIService().initialize();
```

Configures `Dio` with auth headers, timeouts, and optional `LogInterceptor` in demo mode.

---

### `extractTextFromImage`

```dart
Future<String> extractTextFromImage(
  String imagePath, {
  String language = 'te',
}) async
```

**Endpoint:** `POST /ocr` (multipart/form-data)

| Form field | Value                    |
|-----------|--------------------------|
| `image`   | File bytes from `imagePath` |
| `language` | BCP-47 code             |
| `model`   | `Secrets.sarvamOcrModel` |

**Returns:** Extracted text from `response.data['result']['text']`.  
**Throws:** `SarvamAIException`

---

### `textToSpeech`

```dart
Future<String> textToSpeech(
  String text, {
  String language = 'te',
  String gender = 'female',
  double speed = 1.0,
}) async
```

**Endpoint:** `POST /tts`

**Request body:**
```json
{
  "inputs": [{ "source": "<text>" }],
  "target_language_code": "te",
  "speaker": "female",
  "pitch": 1.0,
  "model": "tts"
}
```

**Returns:** Audio content URL from `response.data['audios'][0]['audioContent']`.  
**Throws:** `SarvamAIException`

---

### `batchTextToSpeech`

```dart
Future<List<String>> batchTextToSpeech(
  List<String> texts, {
  String language = 'te',
  String gender = 'female',
}) async
```

Sends all texts in a single request using the `inputs` array. Returns audio URLs in the same order as input.

**Throws:** `SarvamAIException`

---

### `healthCheck`

```dart
Future<bool> healthCheck() async
```

`GET /health` — returns `true` on HTTP 200, `false` on any error.

---

### `dispose`

```dart
void dispose()
```

Closes the underlying `Dio` client.

---

## FirebaseService

**File:** `lib/services/firebase_service.dart`

### Initialization

```dart
await FirebaseService().initialize();
```

Calls `Firebase.initializeApp()` with `Secrets.firebaseConfig`. Side effects:
- Enables analytics collection when `AppConfig.enableAnalytics == true`
- Requests FCM permissions (`alert`, `badge`, `sound`)

**Throws:** `FirebaseInitializationException`

---

### Properties

| Property    | Type                | Description              |
|------------|---------------------|--------------------------|
| `analytics` | `FirebaseAnalytics` | Analytics instance       |
| `messaging` | `FirebaseMessaging` | Messaging instance       |

---

### `logEvent`

```dart
Future<void> logEvent(
  String name, {
  Map<String, Object?>? parameters,
}) async
```

Logs a custom analytics event. No-ops when `AppConfig.enableAnalytics == false`.

---

### `logScreenView`

```dart
Future<void> logScreenView(String screenName) async
```

---

### `getFCMToken`

```dart
Future<String?> getFCMToken() async
```

Returns the device FCM registration token, or `null` on error.

---

## StorageService

**File:** `lib/services/storage_service.dart`  
**Depends on:** Firebase initialized via `FirebaseService.initialize()`

### Initialization

```dart
StorageService().initialize();
```

Obtains `FirebaseStorage.instance`.

---

### `uploadAudio`

```dart
Future<String> uploadAudio(
  File file, {
  required String articleTitle,
  required String source,
}) async
```

Uploads to `{AppConfig.storageAudioPath}{source}-{articleTitle}-{timestamp}.mp3`.

Custom metadata stored on the object:

| Key            | Value                     |
|---------------|---------------------------|
| `articleTitle` | Provided value            |
| `source`       | Provided value            |
| `uploadedAt`   | ISO-8601 UTC timestamp    |

**Returns:** Firebase download URL string.  
**Throws:** `StorageException`

---

### `uploadImage`

```dart
Future<String> uploadImage(
  File file, {
  required String imageName,
}) async
```

Uploads JPEG to `{AppConfig.storageImagesPath}{imageName}-{timestamp}.jpg`.

**Returns:** Download URL.  
**Throws:** `StorageException`

---

### `downloadFile`

```dart
Future<File> downloadFile(String remoteUrl, String localPath) async
```

Creates parent directories as needed. Uses `Reference.writeToFile`.

**Throws:** `StorageException`

---

### `deleteFile`

```dart
Future<void> deleteFile(String remoteUrl) async
```

**Throws:** `StorageException`

---

### `getFileMetadata`

```dart
Future<FullMetadata?> getFileMetadata(String remoteUrl) async
```

Returns `null` on any error (non-throwing).

---

### `listFiles`

```dart
Future<List<Reference>> listFiles(String directory) async
```

**Throws:** `StorageException`

---

## CacheManager

**File:** `lib/utils/cache_manager.dart`  
**Architecture:** Memory LRU (100 items max) → Hive persistent box (`gativani_cache`)

### Initialization

```dart
await CacheManager().initialize();
```

Opens the Hive box. Idempotent — safe to call multiple times.

---

### `get<T>`

```dart
Future<T?> get<T>(String key) async
```

Checks memory first; falls back to Hive. Promotes Hive hits to memory. Returns `null` on miss or expiry.

---

### `set<T>`

```dart
Future<void> set<T>(
  String key,
  T value, {
  Duration? ttl,
  bool persistToHive = true,
}) async
```

Writes to memory and optionally Hive. Omit `ttl` for no expiry.

---

### `getOrCompute<T>`

```dart
Future<T> getOrCompute<T>(
  String key,
  Future<T> Function() compute, {
  Duration ttl = const Duration(hours: 1),
}) async
```

Cache-aside pattern. If the key is not cached, calls `compute()`, stores the result, and returns it.

```dart
// Example
final articles = await CacheManager().getOrCompute(
  'news_all_te',
  () => NewsService().getAllNews(),
  ttl: const Duration(minutes: 30),
);
```

---

### `contains`

```dart
bool contains(String key)
```

Synchronous — checks in-memory layer only.

---

### `remove` / `clear`

```dart
Future<void> remove(String key) async
Future<void> clear() async
```

`remove` targets one key in both tiers. `clear` wipes both entirely.

---

### `getMany` / `setMany`

```dart
Future<Map<String, dynamic>> getMany(List<String> keys) async
Future<void> setMany(Map<String, dynamic> entries, {Duration? ttl}) async
```

Batch operations iterate sequentially.

---

### `getStats`

```dart
Map<String, dynamic> getStats()
// { 'memoryCacheSize': 42, 'memoryMaxSize': 100 }
```

---

## Core Utilities

### ServiceLogger

**File:** `lib/services/core/logging.dart`  
**Global instance:** `logger` (top-level)

```dart
import 'package:gativani/services/core/logging.dart';

logger.info('Article fetched', category: 'NewsService', data: {'count': 5});
logger.error('TTS failed', category: 'SarvamAI', error: e, stackTrace: st);
```

#### Log levels

`debug` < `info` < `warning` < `error` < `critical`

#### Key API

| Method                                            | Description                                  |
|--------------------------------------------------|----------------------------------------------|
| `debug(msg, {category, data})`                   | Diagnostic detail                             |
| `info(msg, {category, data})`                    | Normal operations                             |
| `warning(msg, {category, data})`                 | Recoverable anomaly                           |
| `error(msg, {category, error, stackTrace})`      | Non-fatal error                               |
| `critical(msg, {category, error, stackTrace})`   | Fatal; requires intervention                  |
| `logException(exception, {category})`            | Convenience for `ServiceException`            |
| `logOperation(name, {duration, success, ...})`   | Record timed operation result                 |
| `getLogs({minLevel})`                            | All logs above threshold                      |
| `getLogsByCategory(category, {minLevel})`        | Filter by category string                     |
| `getErrors()`                                    | Shortcut: level ≥ error                       |
| `exportLogs()`                                   | `List<Map<String,dynamic>>` for persistence   |
| `getStats()`                                     | Counts, date range                            |
| `clearLogs()`                                    | Wipe all retained entries                     |

Maximum retained entries: **1000** (oldest evicted automatically).

---

### RetryExecutor and CircuitBreaker

**File:** `lib/services/core/retry_strategy.dart`

#### RetryConfig

```dart
const config = RetryConfig(
  maxAttempts: 3,
  initialDelay: Duration(milliseconds: 500),
  maxDelay: Duration(seconds: 30),
  backoffMultiplier: 2.0,
  retryOnTimeout: true,
  retryableStatusCodes: [408, 429, 500, 502, 503, 504],
  randomizeDelay: true,  // jitter prevents thundering herd
);
```

Delay for attempt `n`:
```
delay = min(initialDelay * backoffMultiplier^(n-1) * jitter, maxDelay)
```

#### RetryExecutor

```dart
final executor = RetryExecutor(
  config: config,
  circuitBreaker: CircuitBreaker(name: 'gemini'),
);

final result = await executor.execute(
  () => GeminiService().summarizeArticle(text),
  operationName: 'GeminiSummarize',
  shouldRetry: (e) => e is NetworkException,
);
```

#### CircuitBreaker

| State       | Behaviour                                                    |
|------------|--------------------------------------------------------------|
| `closed`   | All requests pass through                                     |
| `open`     | All requests immediately throw `CircuitBreakerException`      |
| `halfOpen` | One probe request; success closes, failure re-opens          |

| Parameter          | Default | Description                                      |
|-------------------|---------|--------------------------------------------------|
| `failureThreshold` | `5`     | Consecutive failures before opening               |
| `successThreshold` | `2`     | Consecutive successes to close from half-open     |
| `resetTimeout`     | `60 s`  | Wait before probing from open state               |

#### BatchRetryExecutor

```dart
final batch = BatchRetryExecutor(config: config);
final results = await batch.executeBatch<String>(
  operations,          // List<Future<T> Function()>
  concurrency: 3,      // max parallel in-flight
  batchName: 'TTS',
);
// results: List<Result<T>> — order matches operations list
```

---

### Exception Hierarchy

```
Exception
└── ServiceException (abstract)
    ├── NetworkException        isRetryable: true
    ├── TimeoutException        isRetryable: true  (carries Duration timeout)
    ├── ApiException            isRetryable: depends on statusCode
    ├── CacheException          isRetryable: true
    ├── StorageException        isRetryable: false
    ├── FirebaseException       isRetryable: code == 'unavailable'|'resource-exhausted'
    ├── RateLimitException      isRetryable: true  severity: warning  (carries Duration? retryAfter)
    ├── CircuitBreakerException isRetryable: false severity: warning  (carries Duration resetAfter)
    └── ValidationException     isRetryable: false (carries Map<String,String>? fieldErrors)
```

All exceptions expose:

| Property              | Type             | Description                          |
|----------------------|-----------------|--------------------------------------|
| `message`            | `String`        | Developer-facing detail               |
| `userFriendlyMessage`| `String`        | Safe to display in UI                 |
| `code`               | `String?`       | Machine-readable error code           |
| `isRetryable`        | `bool`          | Whether a retry is appropriate        |
| `severity`           | `ErrorSeverity` | `debug·info·warning·error·critical`   |
| `originalError`      | `dynamic`       | Wrapped underlying exception          |
| `stackTrace`         | `StackTrace?`   | Original stack trace                  |

---

### Result<T>

Functional result wrapper for safe error propagation without try/catch at every call site.

```dart
// Construction
final ok  = Result<String>.success('hello');
final err = Result<String>.failure(NetworkException(message: 'offline'));

// Consumption
if (result.isSuccess) {
  print(result.data);
} else {
  showError(result.error!.userFriendlyMessage);
}

// Transformation
final upper = result.map((s) => s.toUpperCase());

// Safe extraction
final value  = result.getOrElse('default');
final value2 = result.getOrThrow(); // throws stored exception if failure
```

---

## Data Models

### Article

```dart
class Article {
  final String title;
  final String source;     // newspaper name
  final String url;
  final String? imageUrl;
  final DateTime fetchedAt;
  final String language;   // BCP-47, default 'te'
}
```

Serialization:
- `Article.fromMap(Map<String, dynamic>)` — parse API response
- `article.toMap()` — JSON-serializable map

---

### ArticleCardData

UI display model (not persisted via API).

```dart
class ArticleCardData {
  final String title;
  final String source;
  final String? imageUrl;
  final DateTime publishedAt;
  final bool isBookmarked;
  final bool isRead;

  ArticleCardData copyWith({...});
}
```

---

### AudioPlayerState

```dart
class AudioPlayerState {
  final bool isPlaying;
  final Duration currentPosition;
  final Duration duration;
  final double playbackSpeed;   // 0.75 – 1.5 (configurable in AppConfig)
  final bool isLoading;

  double get progress;          // 0.0 – 1.0
}
```

---

### NewsSourceModel

```dart
class NewsSourceModel {
  final String id;          // URL-safe identifier
  final String name;        // Display name
  final String? logoUrl;
  final Color accentColor;  // per-source brand colour
  final bool isSelected;

  NewsSourceModel copyWith({bool? isSelected});
}
```

---

## Configuration Reference

### AppConfig (lib/config/app_config.dart)

| Constant                      | Type     | Default          | Description                          |
|------------------------------|---------|------------------|--------------------------------------|
| `appName`                    | `String` | `'GatiVani'`     | App display name                     |
| `appVersion`                 | `String` | `'1.0.0'`        | Semantic version                     |
| `environment`                | `AppEnvironment` | `demo`  | `demo`, `staging`, `production`      |
| `enableLogging`              | `bool`  | `true`           | Log to console                        |
| `enableAnalytics`            | `bool`  | `true`           | Firebase Analytics                    |
| `newsCacheDurationMinutes`   | `int`   | `30`             | In-memory news TTL                    |
| `newsMaxArticlesPerSource`   | `int`   | `20`             | Per-source article cap                |
| `networkTimeoutSeconds`      | `int`   | `30`             | HTTP timeout (all services)           |
| `networkRetryAttempts`       | `int`   | `3`              | Default retry count                   |
| `audioPlaybackSpeedMin`      | `double`| `0.75`           | Minimum playback speed                |
| `audioPlaybackSpeedMax`      | `double`| `1.5`            | Maximum playback speed                |
| `audioPlaybackSpeedDefault`  | `double`| `1.0`            | Default playback speed                |
| `supportedLanguages`         | `List<String>` | `['te','en','hi']` | Supported language codes    |
| `defaultLanguage`            | `String`| `'te'`           | Telugu default                        |
| `newspaperSources`           | `List<String>` | 5 papers | Active Telugu newspaper sources  |

---

## Error Codes

| Code                    | Exception Type           | Meaning                                    |
|------------------------|--------------------------|--------------------------------------------|
| `operation_timeout`     | `TimeoutException`       | Operation exceeded 30 s                    |
| `circuit_breaker_open`  | `CircuitBreakerException`| Circuit open; too many recent failures     |
| `max_retries_exceeded`  | `ApiException`           | Retry budget exhausted                     |
| `unavailable`           | `FirebaseException`      | Firebase temporarily unavailable           |
| `resource-exhausted`    | `FirebaseException`      | Firebase quota exceeded                    |
| HTTP `401`              | `ApiException`           | Authentication failure                     |
| HTTP `403`              | `ApiException`           | Access denied                              |
| HTTP `429`              | `ApiException` / `RateLimitException` | Rate limited by upstream  |
| HTTP `5xx`              | `ApiException`           | Server error (retryable)                   |
