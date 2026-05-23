# GatiVani Test Suite

This directory contains the full test suite for the GatiVani Flutter
application, organized by test scope.

## Layout

```
test/
  fixtures/        Reusable test data (articles, Gemini responses, service constants)
  mocks/           Mockito + hand-written fakes for every service
  services/        Unit tests for the 5 core services
  widgets/         Widget tests for atomic UI components
  screens/         Widget tests for full-screen widgets (Settings, Bookmarks)
  integration/     End-to-end flow tests that compose multiple services
```

## Running tests

A wrapper script is provided to run subsets of the suite consistently. From
the repository root:

```bash
# All tests
scripts/run_tests.sh

# A specific layer
scripts/run_tests.sh unit         # test/services/
scripts/run_tests.sh widget       # test/widgets/
scripts/run_tests.sh screen       # test/screens/
scripts/run_tests.sh integration  # test/integration/

# Full suite with coverage (writes coverage/lcov.info; HTML if lcov installed)
scripts/run_tests.sh coverage
```

Equivalent direct invocations:

```bash
flutter test                              # All tests
flutter test test/services/news_service_test.dart   # Single file
flutter test --coverage                   # Coverage output
genhtml coverage/lcov.info -o coverage/html         # HTML report
open coverage/html/index.html             # macOS
```

## Layers in detail

### Unit tests (`test/services/`)

One file per service. Each file uses the corresponding
`FakeXService` / `MockXService` from `test/mocks/mock_services.dart` so that
no real network or platform plugin is touched.

Covered services:
- `FirebaseService` — analytics events, FCM tokens, init guard, exception types
- `SarvamAIService` — OCR, TTS, batch TTS, error injection
- `GeminiService` — summarization, audio script generation, batch ops
- `StorageService` — uploads, downloads, listing, deletion
- `NewsService` — fetch, search, filter, cache, Article model round-trip

Each suite is organized into `group(...)` blocks for **Initialization**,
**Happy path**, **Edge cases**, **Exception handling**, **Concurrency**, and
**Performance** to make extension predictable.

### Widget tests (`test/widgets/`)

Tests for individual design-system components:
- `article_card_widget_test.dart`
- `audio_player_widget_test.dart`
- `mini_player_widget_test.dart` *(progress clamp, play/pause icon swap,
  callbacks, semantics, dark-mode rendering)*
- `gradient_background_widget_test.dart` *(every gradient enum, adaptive dark
  resolution, gesture pass-through)*
- `search_bar_widget_test.dart`
- `source_filter_widget_test.dart`
- `loading_states_widget_test.dart`

### Screen tests (`test/screens/`)

Full-screen widget tests that drive interaction:
- `settings_screen_test.dart` — defaults, popup menus, switch toggles,
  snackbars
- `bookmarks_screen_test.dart` — skeleton -> loaded -> empty state, wrapped
  in a real `GoRouter` so navigation calls don't blow up

### Integration tests (`test/integration/`)

Compose multiple services in a single flow:
- `article_to_audio_flow_test.dart` — fetch -> summarize -> generate script
  -> TTS, including batch processing, search, filter, and concurrent flows.
- `offline_cache_fallback_test.dart` — cache hit/miss behavior, typed
  exception surfacing when AI services fail, Article model serialization
  round-trip (the contract Hive/SharedPreferences relies on).

These are pure-Dart integration tests so they run with `flutter test` and
don't require a device. The `integration_test` package is wired in
`pubspec.yaml` for when on-device flows are added later.

## Mock / Fake strategy

`test/mocks/mock_services.dart` exports two flavors for every service:

| Flavor   | Purpose                                                  |
|----------|----------------------------------------------------------|
| `MockX`  | `extends Mock implements X` (mockito-style verification) |
| `FakeX`  | Hand-rolled stub with mutable state and error injection  |

Use **Mocks** when you want to assert call counts (`verify(mock.foo()).called(1)`).
Use **Fakes** when you want a behaving stand-in (e.g. `service.articles = ...`,
`service.errorToThrow = '...'`).

The fakes are the recommended starting point for new tests — they are easier
to read and rarely need updating when the production API changes.

## Fixtures

Located in `test/fixtures/`:

- `article_fixtures.dart` — `ArticleFixtures.createArticle(...)` and
  `createArticleList(...)`.
- `gemini_fixtures.dart` — sample article/summary/script text in English and
  Telugu, generators for long-form content, prompt patterns.
- `service_fixtures.dart` — common URLs, error messages, HTTP status code
  table, performance benchmarks, language codes, retry configs.

## Coverage targets

| Layer       | Target | Notes                                          |
|-------------|--------|------------------------------------------------|
| Services    | >95%   | Achieved via FakeX + MockX combinations        |
| Widgets     | >80%   | Each design-system component has a dedicated file |
| Screens     | >80%   | Settings + Bookmarks; new screens add tests here |
| Overall     | >80%   | Reported via `flutter test --coverage`         |

Generate a local coverage report:

```bash
scripts/run_tests.sh coverage
open coverage/html/index.html
```

## Adding new tests

1. **Service test** — copy an existing file in `test/services/`. Pull the
   fake from `mocks/mock_services.dart`; if the service is new, add a new
   fake alongside the existing ones.
2. **Widget test** — copy an existing file in `test/widgets/`. Use the
   `buildSubject({...})` helper pattern at the top of the file for default
   arguments. Group tests by concern (Rendering, Callbacks, Edge Cases).
3. **Screen test** — wrap in `MaterialApp.router` if the screen uses
   `go_router` (see `bookmarks_screen_test.dart`).
4. **Integration test** — compose multiple services from
   `mocks/mock_services.dart`. Reset state in `setUp`.

## Conventions

- Top-of-file doc comment explains coverage areas.
- Tests live inside named `group(...)` blocks; use **Initialization**,
  **Rendering**, **Callbacks**, **Edge Cases**, **Performance**,
  **Concurrent Operations**, **Exception Handling** as the standard
  hierarchy where applicable.
- Prefer `expect(actual, matcher)` over assertions.
- Use Telugu / Hindi / English content side-by-side for any text input to
  guarantee Unicode safety.
