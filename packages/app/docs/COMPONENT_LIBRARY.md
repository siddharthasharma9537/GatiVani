# GatiVani Component Library

Complete reference for all UI components in the GatiVani design system.

**Version**: 1.0.0
**Last Updated**: May 2026
**Target Audience**: Flutter developers building GatiVani screens

---

## Table of Contents

1. [Design System Overview](#design-system-overview)
2. [Color Palette](#color-palette)
3. [Typography](#typography)
4. [Spacing & Layout](#spacing--layout)
5. [ArticleCard](#articlecard)
6. [AudioPlayerWidget](#audioplayerwidget)
7. [SearchBarWidget](#searchbarwidget)
8. [ExpandableSearchBar](#expandablesearchbar)
9. [SourceFilter](#sourcefilter)
10. [HorizontalSourceFilter](#horizontalsourcefilter)
11. [Loading & State Components](#loading--state-components)
12. [Accessibility](#accessibility)

---

## Design System Overview

GatiVani uses a custom design system built on top of Flutter's Material 3. The system is rooted in Telugu cultural identity, using a saffron-inspired primary palette with teal accents and gold highlights.

### File Locations

```
lib/design/
├── theme/
│   ├── colors.dart          # Full color palette and schemes
│   └── theme_data.dart      # ThemeData builders, spacing, border radius
└── components/
    ├── article_card.dart    # ArticleCard widget
    ├── audio_player.dart    # AudioPlayerWidget
    ├── search_bar.dart      # SearchBarWidget, ExpandableSearchBar
    ├── source_filter.dart   # SourceFilter, HorizontalSourceFilter
    ├── loading_states.dart  # Skeleton loaders, error/empty states
    └── index.dart           # Barrel export
```

Import all components at once:

```dart
import 'package:gativani/design/components/index.dart';
```

---

## Color Palette

All colors are defined in `lib/design/theme/colors.dart`.

### Primary Colors (Saffron)

Represents the cultural identity of Telangana and Andhra Pradesh.

| Token | Hex | Usage |
|---|---|---|
| `PrimaryColors.saffronBase` | `#E67E22` | Primary CTAs, active states |
| `PrimaryColors.saffronLight` | `#F5A962` | Hover states, secondary actions |
| `PrimaryColors.saffronLighter` | `#FAD7B3` | Backgrounds, light highlights |
| `PrimaryColors.saffronDark` | `#C1620C` | Dark mode primary, text on light |
| `PrimaryColors.saffronDarker` | `#8B4513` | Focus states, deep emphasis |

```dart
// Usage
Container(
  color: PrimaryColors.saffronBase,
  child: Text('Listen Now'),
)
```

### Accent Colors

| Token | Hex | Usage |
|---|---|---|
| `AccentColors.teaBase` | `#008B8B` | Secondary CTAs, success states |
| `AccentColors.teaLight` | `#20B2AA` | Hover, secondary highlights |
| `AccentColors.goldBase` | `#D4AF37` | Premium features, highlights |
| `AccentColors.coralBase` | `#FF6B6B` | Bookmarks, engagement, favorites |
| `AccentColors.steelBlue` | `#4A5568` | Secondary text, borders, disabled |

### Semantic Colors

| Token | Usage |
|---|---|
| `SemanticColors.successBase` | Success, completion, valid states |
| `SemanticColors.errorBase` | Errors, destructive actions |
| `SemanticColors.warningBase` | Warnings, caution states |
| `SemanticColors.infoBase` | Informational messages |

### Gradients

```dart
// Saffron gradient — primary action buttons, play button
GradientPalette.saffronGradient

// Saffron to Coral — featured sections
GradientPalette.saffronCoralGradient

// Teal gradient — secondary actions
GradientPalette.teaGradient

// Gold gradient — premium features
GradientPalette.goldGradient
```

**Example**:
```dart
Container(
  decoration: BoxDecoration(
    gradient: GradientPalette.saffronGradient,
    borderRadius: GatiVaniBorderRadius.buttonRadius,
  ),
  child: Text('Play', style: TextStyle(color: Colors.white)),
)
```

### Color Schemes

The app ships with both light and dark Material 3 color schemes:

```dart
// Access the full Material 3 color scheme
GatiVaniColorScheme.lightColorScheme
GatiVaniColorScheme.darkColorScheme
```

The schemes are applied automatically via `buildLightTheme()` and `buildDarkTheme()` in `theme_data.dart`. Never hard-code colors — always reference `Theme.of(context).colorScheme.*` in widgets.

---

## Typography

The app uses four font families registered in `pubspec.yaml`:

| Family | Usage |
|---|---|
| `Inter` | Primary UI text (weights 400, 500, 600, 700) |
| `JetBrainsMono` | Code samples, timestamps |
| `Mallanna` | Telugu body text |
| `NotoSerifTelugu` | Telugu headlines |

All type styles are accessed via Flutter's standard `theme.textTheme.*` API. The `buildLightTheme()` / `buildDarkTheme()` functions configure all text styles globally.

```dart
// Usage pattern
Text(
  'Article Title',
  style: Theme.of(context).textTheme.titleLarge,
)
```

---

## Spacing & Layout

Spacing constants are defined in `theme_data.dart` as `GatiVaniSpacing`:

| Token | Value | Usage |
|---|---|---|
| `GatiVaniSpacing.xs` | 4dp | Tight gaps |
| `GatiVaniSpacing.sm` | 8dp | Small gaps, chip padding |
| `GatiVaniSpacing.md` | 12dp | Medium gaps |
| `GatiVaniSpacing.lg` | 16dp | Standard padding |
| `GatiVaniSpacing.xl` | 24dp | Section spacing |
| `GatiVaniSpacing.xxl` | 32dp | Large section spacing |

Border radius constants are defined as `GatiVaniBorderRadius`:

| Token | Value | Usage |
|---|---|---|
| `GatiVaniBorderRadius.sm` | 4 | Small elements |
| `GatiVaniBorderRadius.md` | 8 | Buttons, inputs |
| `GatiVaniBorderRadius.lg` | 12 | Cards |
| `GatiVaniBorderRadius.chipRadius` | `BorderRadius.circular(20)` | Chips, pills |
| `GatiVaniBorderRadius.cardRadius` | `BorderRadius.circular(12)` | Cards |
| `GatiVaniBorderRadius.buttonRadius` | `BorderRadius.circular(8)` | Buttons |

---

## ArticleCard

**File**: `lib/design/components/article_card.dart`

A stateful card component that displays a newspaper article with image, source badge, timestamp, and action buttons. Supports hover elevation animation on web/desktop.

### Data Model

```dart
class ArticleCardData {
  final String title;          // Article headline (required)
  final String source;         // Newspaper name (required)
  final String? imageUrl;      // Featured image URL (optional)
  final DateTime publishedAt;  // Publication timestamp (required)
  final bool isBookmarked;     // Bookmark state (default: false)
  final bool isRead;           // Read state (default: false)
}
```

### Props

```dart
ArticleCard({
  Key? key,
  required ArticleCardData article,   // Article data to display
  required VoidCallback onTap,        // Tap handler (navigates to player)
  VoidCallback? onBookmarkToggle,     // Bookmark toggle callback
  VoidCallback? onShareTap,           // Share button callback
})
```

### Basic Usage

```dart
ArticleCard(
  article: ArticleCardData(
    title: 'తెలంగాణలో నీటి సంక్షోభం పరిష్కారానికి కొత్త ప్రణాళిక',
    source: 'Sakshi',
    imageUrl: 'https://example.com/article-image.jpg',
    publishedAt: DateTime.now().subtract(const Duration(hours: 2)),
    isBookmarked: false,
    isRead: false,
  ),
  onTap: () => context.pushNamed('player', pathParameters: {'id': articleId}),
  onBookmarkToggle: () => _toggleBookmark(article),
  onShareTap: () => _shareArticle(article),
)
```

### Features

- **Hover animation**: On web/desktop, card elevation animates from 1 to 8 on hover using `MouseRegion` + `AnimationController`.
- **Image loading**: Shows `CircularProgressIndicator` while image loads; falls back to `Icons.image_not_supported_outlined` on error.
- **Read badge**: When `isRead: true`, displays a checkmark overlay on the image.
- **Bookmark indicator**: Bookmark icon fills with `AccentColors.coralBase` when `isBookmarked: true`.
- **Relative timestamps**: `publishedAt` is shown as "now", "2h ago", "3d ago", or `MM/DD` format.

### Layout

```
┌─────────────────────────────────────┐
│  [Article Image 180px height]       │
│  [Read badge overlay if isRead]     │
├─────────────────────────────────────┤
│  [Source Badge]  [2h ago]           │
│                                     │
│  Article Title (max 3 lines)        │
│                                     │
│  [Listen ▶]  [Bookmark]  [Share]   │
└─────────────────────────────────────┘
```

### Skeleton Loader

Use `ArticleCardSkeleton` during loading:

```dart
// Single skeleton
const ArticleCardSkeleton()

// List of skeletons
ArticleListSkeleton(
  itemCount: 6,
)
```

---

## AudioPlayerWidget

**File**: `lib/design/components/audio_player.dart`

A full-featured audio player control panel. Stateless — all state is passed in via `AudioPlayerState` and updated through callbacks.

### State Model

```dart
class AudioPlayerState {
  final bool isPlaying;               // Playback active
  final Duration currentPosition;     // Current seek position
  final Duration duration;            // Total audio duration
  final double playbackSpeed;         // Current speed (0.5–2.0)
  final bool isLoading;               // Show loading indicator

  // Computed
  double get progress              // 0.0–1.0 progress fraction
}
```

### Props

```dart
AudioPlayerWidget({
  Key? key,
  required AudioPlayerState playerState,       // Current player state
  required VoidCallback onPlayPause,           // Play/pause toggle
  VoidCallback? onNextTrack,                   // Skip to next article
  VoidCallback? onPreviousTrack,               // Go to previous article
  VoidCallback? onSkipForward,                 // Skip forward 10 seconds
  VoidCallback? onSkipBackward,                // Rewind 10 seconds
  Function(double)? onPositionChanged,         // Seek — receives ms position
  Function(double)? onSpeedChanged,            // Speed change — receives speed
  String? articleTitle,                        // Shown in header
  String? articleSource,                       // Shown in header subtitle
})
```

### Basic Usage

```dart
AudioPlayerWidget(
  playerState: AudioPlayerState(
    isPlaying: _isPlaying,
    currentPosition: _position,
    duration: _duration,
    playbackSpeed: _speed,
    isLoading: _isLoading,
  ),
  onPlayPause: _handlePlayPause,
  onSkipForward: () => _seek(_position + const Duration(seconds: 10)),
  onSkipBackward: () => _seek(_position - const Duration(seconds: 10)),
  onPositionChanged: (ms) => _seek(Duration(milliseconds: ms.toInt())),
  onSpeedChanged: (speed) => setState(() => _speed = speed),
  onNextTrack: _loadNextArticle,
  onPreviousTrack: _loadPreviousArticle,
  articleTitle: 'Government Announces New Policies',
  articleSource: 'Andhra Jyothi',
)
```

### Features

- **Play/pause button**: Saffron gradient circle with scale animation on state change.
- **Progress slider**: Draggable with 4dp track height, saffron active color.
- **Time display**: Current position and total duration in `MM:SS` or `H:MM:SS` format.
- **Speed picker**: Bottom sheet with options 0.5×, 0.75×, 1×, 1.25×, 1.5×, 2×.
- **Loading bar**: `LinearProgressIndicator` displayed below controls when `isLoading: true`.
- **Animated icon**: Play/pause icon scales with `ScaleTransition` via `AnimationController`.

### Layout

```
┌─────────────────────────────────────┐
│  Article Title                      │
│  Source Name                        │
├─────────────────────────────────────┤
│  ████████████░░░░░░░░  [slider]     │
│  01:23                      04:30   │
├─────────────────────────────────────┤
│  [⏪10]  [⏮]  [  ▶  ]  [⏭]  [10⏩]│
├─────────────────────────────────────┤
│  [1.0× Speed]   [Volume]            │
├─────────────────────────────────────┤
│  [loading bar if isLoading]         │
└─────────────────────────────────────┘
```

### Integrating with just_audio

```dart
// In your state class:
late AudioPlayer _player;

void initState() {
  super.initState();
  _player = AudioPlayer();
  _player.positionStream.listen((pos) => setState(() => _position = pos));
  _player.durationStream.listen((dur) => setState(() => _duration = dur ?? Duration.zero));
  _player.playingStream.listen((playing) => setState(() => _isPlaying = playing));
}

AudioPlayerState get _playerState => AudioPlayerState(
  isPlaying: _isPlaying,
  currentPosition: _position,
  duration: _duration,
  playbackSpeed: _speed,
);

void _handlePlayPause() {
  if (_isPlaying) {
    _player.pause();
  } else {
    _player.play();
  }
}
```

---

## SearchBarWidget

**File**: `lib/design/components/search_bar.dart`

A customizable search input with debounced search, clear button, voice search icon, and filter icon.

### Configuration

```dart
class SearchBarConfig {
  final String hintText;              // Placeholder text (default: 'Search articles...')
  final String? labelText;            // Optional floating label
  final Duration debounceDuration;    // Debounce delay (default: 300ms)
  final int minCharsToSearch;         // Minimum chars before triggering (default: 2)
  final bool showFilters;             // Show filter icon button (default: true)
  final bool showVoiceSearch;         // Show voice icon button (default: true)
}
```

### Props

```dart
SearchBarWidget({
  Key? key,
  SearchBarConfig config,                       // Configuration (optional)
  Function(String)? onSearchChanged,            // Called on debounced input
  Function(String)? onSearchSubmitted,          // Called on keyboard submit
  VoidCallback? onClear,                        // Called when search is cleared
  VoidCallback? onFilterTap,                    // Filter button callback
  VoidCallback? onVoiceSearchTap,               // Voice icon callback
  bool isLoading,                               // Show spinner instead of clear
  TextEditingController? controller,            // External controller (optional)
  FocusNode? focusNode,                         // External focus node (optional)
})
```

### Basic Usage

```dart
SearchBarWidget(
  config: SearchBarConfig(
    hintText: 'Search Telugu news...',
    debounceDuration: const Duration(milliseconds: 400),
    minCharsToSearch: 3,
  ),
  onSearchChanged: (query) {
    setState(() => _searchQuery = query);
    _filterArticles(query);
  },
  onClear: () => setState(() => _searchQuery = ''),
  onFilterTap: _showFilterPanel,
  isLoading: _isSearching,
)
```

### Features

- **Debounced search**: `onSearchChanged` fires only after `debounceDuration` with no new input, preventing excessive API calls.
- **Minimum chars**: Search triggers only when input length >= `minCharsToSearch`.
- **Focus ring**: Border width increases to 2 and glows with primary color on focus.
- **Loading state**: When `isLoading: true`, shows a `CircularProgressIndicator` instead of the clear button.
- **Clear button**: Appears when the field has content and `isLoading` is false.

### Layout

```
┌─────────────────────────────────────────────┐
│  [🔍]  Input field...          [✕] [🎤] [⚙]│
└─────────────────────────────────────────────┘
```

---

## ExpandableSearchBar

**File**: `lib/design/components/search_bar.dart`

An extended search bar that shows recent searches in an animated dropdown when the field is focused.

### Props

```dart
ExpandableSearchBar({
  Key? key,
  SearchBarConfig config,
  List<String> recentSearches,               // List to show in dropdown
  Function(String)? onSearchChanged,
  Function(String)? onSearchSubmitted,
  VoidCallback? onClear,
  Function(String)? onRecentSearchTap,       // Called when a recent item is tapped
  VoidCallback? onClearRecent,               // "Clear all" button callback
})
```

### Usage

```dart
ExpandableSearchBar(
  recentSearches: _recentSearches,
  onSearchSubmitted: (query) {
    setState(() {
      _recentSearches = [query, ..._recentSearches.take(4)];
    });
    _performSearch(query);
  },
  onRecentSearchTap: (query) => _performSearch(query),
  onClearRecent: () => setState(() => _recentSearches = []),
)
```

### Features

- Shows up to 5 recent searches in the dropdown.
- Dropdown animates in with `ScaleTransition` (0.95 → 1.0).
- Dismisses when the field loses focus.
- "Clear" button wipes all recent searches.

---

## SourceFilter

**File**: `lib/design/components/source_filter.dart`

A grid/wrap layout multi-select filter for newspaper sources. Each source renders as an animated chip with optional logo.

### Source Model

```dart
class NewsSourceModel {
  final String id;              // Unique identifier (e.g., 'andhra-jyothi')
  final String name;            // Display name (e.g., 'Andhra Jyothi')
  final String? logoUrl;        // Optional logo URL
  final Color accentColor;      // Chip accent color (default: saffronBase)
  final bool isSelected;        // Selection state
}
```

### Props

```dart
SourceFilter({
  Key? key,
  required List<NewsSourceModel> sources,
  required Function(List<String>) onSourcesChanged,  // Returns selected IDs
  bool allowMultiSelect,                             // default: true
  ScrollPhysics? scrollPhysics,
})
```

### Usage

```dart
final List<NewsSourceModel> _sources = [
  NewsSourceModel(
    id: 'andhra-jyothi',
    name: 'Andhra Jyothi',
    accentColor: PrimaryColors.saffronBase,
  ),
  NewsSourceModel(
    id: 'sakshi',
    name: 'Sakshi',
    accentColor: AccentColors.goldBase,
  ),
  NewsSourceModel(
    id: 'namasthe-telangana',
    name: 'Namasthe Telangana',
    accentColor: AccentColors.teaBase,
  ),
];

SourceFilter(
  sources: _sources,
  onSourcesChanged: (selectedIds) {
    setState(() => _activeFilters = selectedIds);
    _applyFilters();
  },
  allowMultiSelect: true,
)
```

### Features

- **Animated chips**: `AnimatedContainer` handles color transition between selected/unselected states in 200ms.
- **Select All / Deselect All**: `PopupMenuButton` in the header row.
- **Source counter**: Header shows "Selected: 2 / 5".
- **Selected state**: Chip background changes to `accentColor`; icon and text turn white; glow shadow added.
- **Single select mode**: Set `allowMultiSelect: false` to allow only one source at a time.

### Layout

```
┌─────────────────────────────────────┐
│  News Sources    Selected: 2/5  [⋮]│
│                                     │
│  [Andhra Jyothi ✓]  [Sakshi]       │
│  [Namasthe Telangana]  [Prajasakti] │
└─────────────────────────────────────┘
```

---

## HorizontalSourceFilter

**File**: `lib/design/components/source_filter.dart`

A compact horizontal scrolling variant of the source filter, suitable for AppBar or top-of-screen placement.

### Props

```dart
HorizontalSourceFilter({
  Key? key,
  required List<NewsSourceModel> sources,
  required Function(List<String>) onSourcesChanged,
  ScrollController? scrollController,
})
```

### Usage

```dart
// Typically placed below the AppBar
HorizontalSourceFilter(
  sources: _sources,
  onSourcesChanged: (selectedIds) {
    setState(() => _selectedSources = selectedIds);
  },
)
```

### Features

- Horizontal `SingleChildScrollView` with `BouncingScrollPhysics`.
- Compact chip design — no logos, no header row.
- Same animated selection behavior as `SourceFilter`.

---

## Loading & State Components

**File**: `lib/design/components/loading_states.dart`

### ArticleCardSkeleton

A skeleton loader that matches the exact dimensions of `ArticleCard`. Uses a `FadeTransition` between 0.3 and 0.7 opacity to simulate a shimmer effect.

```dart
ArticleCardSkeleton(
  animationDuration: const Duration(seconds: 1), // default
)
```

### ArticleListSkeleton

A `ListView` of `ArticleCardSkeleton` items for loading states.

```dart
ArticleListSkeleton(
  itemCount: 6,    // default: 6
)
```

### ErrorStateWidget

A centered error display with icon, title, message, and optional retry button.

```dart
ErrorStateWidget(
  title: 'Could not load articles',
  message: 'Check your internet connection and try again.',
  icon: Icons.wifi_off_outlined,
  onRetry: _retryLoad,
  retryButtonText: 'Try Again',
)
```

**Props**:

| Prop | Type | Default | Description |
|---|---|---|---|
| `title` | String | required | Error headline |
| `message` | String? | null | Optional body text |
| `icon` | IconData | `Icons.error_outline` | Leading icon |
| `onRetry` | VoidCallback? | null | If set, shows retry button |
| `retryButtonText` | String? | `'Retry'` | Button label |

### EmptyStateWidget

A centered empty state with icon, title, subtitle, and optional action.

```dart
EmptyStateWidget(
  title: 'No Articles Found',
  subtitle: 'Try adjusting your search or filters',
  icon: Icons.newspaper_outlined,
  onAction: _clearFilters,
  actionButtonText: 'Clear Filters',
)
```

**Props**:

| Prop | Type | Default | Description |
|---|---|---|---|
| `title` | String | required | Empty state headline |
| `subtitle` | String? | null | Optional body text |
| `icon` | IconData | `Icons.inbox_outlined` | Leading icon |
| `onAction` | VoidCallback? | null | If set, shows action button |
| `actionButtonText` | String? | `'Take Action'` | Button label |

### LoadingOverlay

Overlays a semi-transparent loading spinner on top of a child widget.

```dart
LoadingOverlay(
  isLoading: _isProcessing,
  message: 'Generating audio...',
  child: YourContentWidget(),
)
```

**Props**:

| Prop | Type | Default | Description |
|---|---|---|---|
| `isLoading` | bool | required | Controls visibility |
| `child` | Widget | required | Content behind overlay |
| `message` | String? | null | Optional label below spinner |

### ShimmerLoading

Wraps any widget with a shimmer gradient animation for skeleton loading.

```dart
ShimmerLoading(
  duration: const Duration(seconds: 2),
  child: Container(
    width: 200,
    height: 20,
    color: Colors.grey[300],
  ),
)
```

### RetryButton

A standalone retry button with loading state.

```dart
RetryButton(
  onRetry: _retryLoad,
  label: 'Retry',
  isLoading: _isRetrying,
  icon: Icons.refresh,
)
```

---

## Accessibility

All components follow accessibility best practices:

### Semantic Labels

Every interactive element has a `tooltip` or `semanticsLabel`:

```dart
// Bookmark button
IconButton(
  onPressed: widget.onBookmarkToggle,
  icon: Icon(Icons.bookmark_outline),
  tooltip: 'Bookmark',  // Shown to screen readers
)

// Play button
InkWell(
  onTap: widget.onPlayPause,
  child: Icon(Icons.play_arrow_rounded),
)
// Wrap with Semantics if needed:
Semantics(
  label: 'Play article',
  child: InkWell(...),
)
```

### Color Contrast

All color combinations meet WCAG AA (4.5:1) contrast ratio:
- White text on saffron (`#E67E22`): 3.1:1 — use for large text or icons only
- Dark text (`#1A202C`) on white backgrounds: 17.1:1
- White text on teal (`#008B8B`): 4.6:1

### Touch Targets

All interactive elements meet the 48×48dp minimum touch target:
- `IconButton` defaults to 48×48
- `ArticleCard` play button is padded to 48×48 minimum
- Source filter chips are padded to at least 44dp height

### Dark Mode

All components fully support dark mode via `Theme.of(context).colorScheme.*`. No hard-coded colors are used — all colors reference the color scheme. The app follows `ThemeMode.system` by default.

### Telugu Script

- `NotoSerifTelugu` and `Mallanna` fonts are bundled for correct Telugu rendering.
- Text `overflow: TextOverflow.ellipsis` is used on all truncated strings.
- `maxLines` constraints are tuned for Telugu script which tends to be wider than Latin equivalents.

---

## Component Usage in Screens

### HomeScreen

```dart
// Full screen composition example
Scaffold(
  appBar: AppBar(title: const Text('GatiVani')),
  body: Column(
    children: [
      // Search
      Padding(
        padding: const EdgeInsets.all(GatiVaniSpacing.lg),
        child: SearchBarWidget(
          onSearchChanged: _onSearch,
          onClear: _clearSearch,
          onFilterTap: _showSourceFilter,
        ),
      ),
      // Horizontal source chips
      HorizontalSourceFilter(
        sources: _sources,
        onSourcesChanged: _onSourcesChanged,
      ),
      // Articles or loading state
      Expanded(
        child: _isLoading
            ? const ArticleListSkeleton()
            : _articles.isEmpty
                ? EmptyStateWidget(
                    title: 'No Articles',
                    subtitle: 'Try a different search',
                    onAction: _clearSearch,
                    actionButtonText: 'Clear',
                  )
                : ListView.separated(
                    itemCount: _articles.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: GatiVaniSpacing.lg),
                    itemBuilder: (context, i) => ArticleCard(
                      article: _articles[i],
                      onTap: () => _openPlayer(_articles[i]),
                    ),
                  ),
      ),
    ],
  ),
)
```

### PlayerScreen

```dart
// Full player composition
Scaffold(
  body: Column(
    children: [
      // Article image header
      if (article.imageUrl != null)
        Image.network(article.imageUrl!, height: 250, fit: BoxFit.cover),
      // Player controls
      Padding(
        padding: const EdgeInsets.all(GatiVaniSpacing.lg),
        child: AudioPlayerWidget(
          playerState: _playerState,
          onPlayPause: _handlePlayPause,
          onSkipForward: _skipForward,
          onSkipBackward: _skipBackward,
          onPositionChanged: _seekTo,
          onSpeedChanged: _changeSpeed,
          articleTitle: article.title,
          articleSource: article.source,
        ),
      ),
      // Error overlay if needed
      if (_hasError)
        ErrorStateWidget(
          title: 'Playback Error',
          message: _errorMessage,
          onRetry: _retryPlayback,
        ),
    ],
  ),
)
```

---

## Adding New Components

Follow this pattern for any new component:

1. Create the file in `lib/design/components/`.
2. Export it from `lib/design/components/index.dart`.
3. Use `GatiVaniSpacing.*` for all padding/spacing.
4. Use `GatiVaniBorderRadius.*` for all border radii.
5. Use `Theme.of(context).colorScheme.*` for all colors — never hard-code.
6. Add a `tooltip` to all icon buttons.
7. Support both light and dark themes (test with `ThemeMode.dark`).
8. Write widget tests in `test/widgets/`.
