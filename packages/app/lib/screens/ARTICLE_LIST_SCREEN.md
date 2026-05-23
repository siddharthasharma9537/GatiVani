# ArticleListScreen Implementation

## Overview
The `ArticleListScreen` displays a list of articles from a newspaper with processing status, quality scores, and playback controls.

## Features

### Newspaper Metadata Header
- Newspaper title, date, and language
- Processing progress indicator (X of Y articles processed)
- Progress bar showing completion percentage

### Article Card Display
Each article card shows:
- **Status Indicator**: Icon showing article state (completed, processing, or failed)
- **Title**: Article headline (truncated if needed)
- **Section Badge**: Color-coded category badge (e.g., News, Government, Editorial)
- **Preview Text**: 50-character preview of article content
- **Quality Score**: Star icon + quality percentage (65-95%)
- **Action Icon**: Context-sensitive icon based on status

### Processing States

#### Completed
- Status: Green check icon
- Quality score displayed as percentage
- Play button icon for audio playback
- Tappable to open PlayerScreen

#### Processing
- Status: Loading spinner
- "Processing..." message
- Disabled until complete
- Right-side spinner

#### Failed
- Status: Red error icon
- "Failed to process" message
- Retry button icon
- Tappable to retry processing

### Empty State
Shows placeholder when no articles are available.

## Usage

### Basic Implementation
```dart
import 'package:gativani/screens/article_list_screen.dart';
import 'package:gativani/models/article.dart';

// Navigate to article list
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => ArticleListScreen(
      newspaperTitle: 'The Hindu',
      newspaperDate: 'May 23, 2026',
      language: 'Telugu',
      articles: [
        UploadedArticle(
          id: '1',
          title: 'Political Updates',
          content: 'Lorem ipsum dolor sit amet...',
          source: 'The Hindu',
          storageUrl: 'https://...',
          category: 'News',
          audioUrl: 'https://...',
          extractedAt: DateTime.now(),
        ),
        // ... more articles
      ],
    ),
  ),
);
```

### Integration with HomeScreen
Update the recent documents section to navigate to article list:
```dart
_buildArticleRow(BuildContext context, Map<String, String> item) {
  return InkWell(
    onTap: () {
      // Fetch articles for this newspaper and navigate
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArticleListScreen(
            newspaperTitle: item['title']!,
            newspaperDate: item['subtitle']!,
            language: 'Telugu',
            articles: [/* fetch from API */],
          ),
        ),
      );
    },
    // ... rest of card
  );
}
```

## ArticlePlayer Updates

The `ArticlePlayer` component has been enhanced to support multiple input methods:

### Constructor Options

#### Option 1: Direct Article Data (Legacy)
```dart
ArticlePlayer(
  audioUrl: 'https://...',
  articleImageUrl: 'https://...',
  articleText: 'Article content...',
  articleTitle: 'Article Title',
  onClose: () => Navigator.pop(context),
)
```

#### Option 2: Article Object (Recommended)
```dart
ArticlePlayer(
  article: UploadedArticle(...),
  onClose: () => Navigator.pop(context),
)
```

#### Option 3: Article ID (Future Enhancement)
```dart
ArticlePlayer(
  articleId: '123',
  onClose: () => Navigator.pop(context),
)
```
*Note: This option requires API integration to fetch article data.*

### Enhanced Features
- Graceful handling of missing audio/text
- Loading state when fetching by ID
- Error state with fallback UI
- Backward compatible with existing code
- Disabled play button when audio unavailable

## State Management

The component uses simple local state management:
- `_ArticleState` enum tracks article processing status
- Status is determined from `UploadedArticle.audioUrl` availability
- Retry logic simulates 2-second delay before attempting reprocessing

## Quality Score Calculation

Quality scores (65-95%) are based on content length:
- 5000+ characters: 95%
- 2000-4999 characters: 85%
- 500-1999 characters: 75%
- <500 characters: 65%

In production, this should come from the API response.

## Category Colors

Predefined color scheme for article categories:
- News: Accent purple
- Government: Success green
- Editorial: Blue
- Education: Purple
- Health: Pink
- Business: Orange
- Default: Secondary gray

## Error Handling

### Empty Articles
Shows placeholder icon and message when list is empty.

### Processing Failures
Displays error state with retry button. Clicking retry simulates reprocessing.

### Network Issues
Future: Handle API fetch failures gracefully with retry option.

## Design System Integration

Uses GatiVani design system:
- `GVColors`: Semantic color palette
- `GVTypography`: Consistent text styles
- `GVRadius`: Standard border radius values
- Light/dark mode support via `BuildContext`

## Files Modified

- `/packages/app/lib/screens/article_list_screen.dart` - New screen
- `/packages/app/lib/design/components/article_player.dart` - Enhanced component

## Testing

Example test case:
```dart
testWidgets('ArticleListScreen displays newspaper metadata', (WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ArticleListScreen(
        newspaperTitle: 'Test Newspaper',
        newspaperDate: 'May 23, 2026',
        language: 'Telugu',
        articles: [],
      ),
    ),
  );
  
  expect(find.text('Test Newspaper'), findsOneWidget);
  expect(find.text('May 23, 2026 • Telugu'), findsOneWidget);
});
```

## Future Enhancements

1. API integration for article fetching by ID
2. Real quality score from API
3. Pagination for large article lists
4. Search/filter functionality
5. Sorting by category, date, or quality
6. Bookmark/favorite articles
7. Share functionality
8. Offline support with local caching
