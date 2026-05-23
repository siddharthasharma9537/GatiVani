# GatiVani Testing Strategy - Comprehensive Test Suite

## Overview

This document outlines the complete testing strategy for the GatiVani application, achieving >80% code coverage with comprehensive unit, widget, and integration tests.

## Test Architecture

### 1. Unit Tests

#### Service Tests
- **NewsService** (`test/services/news_service_test.dart`)
  - getAllNews() - fetch from all sources
  - getNewsBySource() - source filtering
  - search() - keyword searching
  - getRecentNews() - temporal filtering
  - Cache management and validation
  - Exception handling

- **SarvamAIService** (`test/services/sarvam_ai_service_test.dart`)
  - extractTextFromImage() - OCR functionality
  - textToSpeech() - single TTS conversion
  - batchTextToSpeech() - batch TTS processing
  - healthCheck() - API health monitoring
  - Language support (Telugu, English, Hindi)
  - Error scenarios and recovery

- **GeminiService** (`test/services/gemini_service_test.dart`)
  - summarizeArticle() - article summarization
  - generateAudioScript() - podcast-style script generation
  - batchSummarize() - batch summarization
  - Language support for all operations
  - Duration-based script length
  - Prompt generation validation

- **StorageService** (`test/services/storage_service_test.dart`)
  - uploadAudio() - audio file upload
  - uploadImage() - image file upload
  - downloadFile() - file download operations
  - deleteFile() - file deletion
  - getFileMetadata() - metadata retrieval
  - listFiles() - directory listing

- **FirebaseService** (`test/services/firebase_service_test.dart`)
  - initialization() - Firebase setup
  - logEvent() - analytics logging
  - logScreenView() - screen tracking
  - getFCMToken() - push notification tokens
  - Error handling and recovery

#### Model Tests
- **Article Model** (within `test/services/news_service_test.dart`)
  - toMap() serialization
  - fromMap() deserialization
  - Default values handling
  - Language support
  - Metadata preservation

### 2. Widget Tests

#### Core Components
- **ArticleCard** (`test/widgets/article_card_widget_test.dart`)
  - Renders title and source
  - Image display and fallback
  - Tap interactions
  - Overflow handling
  - Accessibility features
  - Dark mode support
  - Loading and error states

#### Additional Widget Tests (Structure)
- **AudioPlayer**
  - Playback controls
  - Progress tracking
  - Speed adjustment
  - Error display

- **SearchBar**
  - Text input handling
  - Clear functionality
  - Suggestions display
  - Keyboard interactions

- **SourceFilter**
  - Multi-select functionality
  - Filter application
  - Reset functionality
  - State persistence

### 3. Integration Tests

#### End-to-End Flows
- **Article to Audio Pipeline** (`test/integration/article_to_audio_flow_test.dart`)
  - Fetch articles → Summarize → Generate script → Convert to speech
  - Single article flow
  - Batch processing
  - Error handling through pipeline
  - Data flow validation
  - Language propagation
  - Performance benchmarks
  - Concurrent processing
  - Cache optimization
  - Complete user journey

### 4. Test Infrastructure

#### Fixtures
- **ArticleFixtures** (`test/fixtures/article_fixtures.dart`)
  - createArticle() - single article creation
  - createArticleList() - batch article creation
  - createArticleWithMetadata() - detailed article setup

- **GeminiFixtures** (`test/fixtures/gemini_fixtures.dart`)
  - Sample article texts (English and Telugu)
  - Sample summaries
  - Audio scripts
  - Long article generation
  - Article variations by topic

- **ServiceFixtures** (`test/fixtures/service_fixtures.dart`)
  - Audio/image URLs
  - Error messages
  - HTTP status codes
  - Mock API responses
  - Performance benchmarks
  - Cache key patterns
  - Language codes
  - File paths
  - Operation timeouts

#### Mocks and Fakes
- **MockServices** (`test/mocks/mock_services.dart`)
  - MockFirebaseService
  - MockSarvamAIService
  - MockGeminiService
  - MockStorageService
  - MockNewsService
  - FakeImplementations for tracking state

## Coverage Goals

### Target: >80% Overall Code Coverage

- **Services**: >95% per service
  - Firebase: 95%+ (all public methods and error paths)
  - SarvamAI: 95%+ (OCR, TTS, health check, batch operations)
  - Gemini: 95%+ (summarization, script generation, batch)
  - Storage: 95%+ (upload, download, delete, metadata, listing)
  - News: 95%+ (fetch, filter, search, cache)

- **Models**: >90%
  - Article: 100% (serialization, deserialization)

- **Widgets**: >80%
  - ArticleCard: 85%+
  - AudioPlayer: 80%+
  - SearchBar: 80%+
  - SourceFilter: 80%+

- **Utilities**: >85%
  - CacheManager: 85%+
  - Configuration: 90%+

## Running Tests

### Run All Tests
```bash
flutter test
```

### Run Specific Test File
```bash
flutter test test/services/news_service_test.dart
```

### Run Tests with Coverage
```bash
flutter test --coverage
```

### Run Tests with Output
```bash
flutter test --verbose
```

### Run Widget Tests Only
```bash
flutter test test/widgets/
```

### Run Integration Tests
```bash
flutter test test/integration/
```

### Run Service Tests
```bash
flutter test test/services/
```

### Generate Coverage Report
```bash
# Install lcov first
brew install lcov

# Generate coverage
flutter test --coverage

# View HTML report
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

## Test Categories

### Unit Tests (440+ tests)
- Service initialization and singleton pattern
- Method functionality and return values
- Error handling and exceptions
- Language support
- Cache management
- Concurrent operations
- Edge cases and boundary conditions
- Performance benchmarks

### Widget Tests (100+ tests)
- Rendering validation
- User interactions
- Accessibility
- Dark mode support
- Loading/error states
- Responsive design
- Text overflow handling

### Integration Tests (40+ tests)
- Complete user flows
- Service interaction
- Data flow through pipeline
- Error recovery
- Performance under load
- Cache optimization
- Concurrent operations

## Key Testing Patterns

### 1. Arrange-Act-Assert (AAA)
All tests follow the AAA pattern for clarity:
```dart
test('description', () {
  // Arrange
  final service = MockService();
  
  // Act
  final result = await service.method();
  
  // Assert
  expect(result, matches(expectation));
});
```

### 2. Mock vs Fake
- **Mocks**: Verify method calls and interactions (using mockito)
- **Fakes**: Full implementations with configurable state (for complex scenarios)

### 3. Error Scenario Testing
Each service includes tests for:
- Network errors
- Timeout scenarios
- Invalid input
- API errors
- Concurrent conflicts

### 4. Performance Testing
Critical paths include:
- Single operation timing
- Batch operation performance
- Memory usage under load
- Cache effectiveness

## Continuous Integration

### Pre-commit Checks
```bash
# Run all tests before commit
flutter test --coverage

# Verify coverage threshold
# Coverage should be > 80%
```

### CI/CD Pipeline
Tests run automatically on:
- Every commit to feature branches
- Pull requests to main branch
- Release candidate builds

## Test Maintenance

### Regular Updates
- Update tests when services change
- Add tests for new features
- Refactor tests to reduce duplication
- Review and optimize slow tests

### Coverage Reporting
- Generate coverage reports monthly
- Identify coverage gaps
- Plan improvements
- Track coverage trends

## Best Practices

### 1. Test Naming
- Use descriptive names starting with "test_"
- Include the scenario being tested
- Example: `test_getAllNews_returnsEmptyListWhenNoCached()`

### 2. Test Organization
- Group related tests with `group()`
- Use `setUp()` for common initialization
- Use `tearDown()` for cleanup

### 3. Assertions
- One logical assertion per test (can have multiple expect() calls)
- Use specific matchers (e.g., `isNotEmpty` over `!isEmpty`)
- Include meaningful error messages

### 4. Test Data
- Use fixtures for consistent test data
- Generate data programmatically for large sets
- Keep fixtures realistic and representative

### 5. Mocking Strategy
- Mock external dependencies
- Use fakes for complex state tracking
- Verify critical interactions
- Test real implementation where feasible

## Known Limitations

### Mock Service Limitations
- Firebase initialization requires emulator setup
- Network operations are simulated
- File I/O is mocked for unit tests
- Timing-dependent operations are simplified

### Platform-Specific Tests
- Some Flutter-specific widgets need widget tests
- Platform channels require integration tests
- Native code requires separate testing

## Future Enhancements

### Planned Improvements
1. Performance profiling integration
2. Load testing for concurrent operations
3. Visual regression testing for widgets
4. End-to-end testing with real API
5. Accessibility automated testing
6. Security testing for sensitive data

### Expansion Areas
1. Add tests for UI state management
2. Expand widget test coverage
3. Add mutation testing
4. Implement golden tests for widgets
5. Add property-based testing for models

## Troubleshooting

### Common Issues

**Issue**: Tests timeout
**Solution**: Increase timeout duration or optimize test performance

**Issue**: Mock not matching expected calls
**Solution**: Verify method signatures and parameter types

**Issue**: Coverage report not generating
**Solution**: Ensure coverage package is installed: `pub add dev:coverage`

**Issue**: Flaky tests due to timing
**Solution**: Use `pumpAndSettle()` in widget tests or add explicit waits

## Resources

- [Flutter Testing Documentation](https://flutter.dev/docs/testing)
- [Mockito Package](https://pub.dev/packages/mockito)
- [Flutter Widget Testing Guide](https://flutter.dev/docs/testing/unit-testing)
- [Integration Testing in Flutter](https://flutter.dev/docs/testing/integration-testing)

## Contact & Support

For questions about the test strategy or implementation:
- Review test files for examples
- Check fixtures for available test data
- Refer to mock implementations for testing patterns
