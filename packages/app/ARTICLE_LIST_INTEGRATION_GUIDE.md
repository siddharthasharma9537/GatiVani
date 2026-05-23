# Article List Screen Integration Guide

## Overview

The ArticleListScreen has been integrated into the main navigation flow. After a user uploads a document and reviews extracted text, they are now directed to the ArticleListScreen instead of directly to the PlayerScreen. This change supports future multi-article newspaper processing while maintaining backward compatibility with single-article uploads.

## Integration Changes

### 1. Navigation Flow Update

**Before:**
```
UploadContentScreen → ReviewScreen → PlayerScreen
```

**After:**
```
UploadContentScreen → ReviewScreen → ArticleListScreen → PlayerScreen (on tap)
```

### 2. Files Modified

#### `/packages/app/lib/screens/review_screen.dart`
- Added import: `article_list_screen.dart`
- Modified `_saveAndPlay()` to navigate to ArticleListScreen
- Added `_formatDate()` helper for date formatting
- Changed navigation from direct PlayerScreen to ArticleListScreen with metadata

#### `/packages/app/lib/main.dart`
- Added route configuration placeholder for article list navigation

#### `/packages/app/lib/screens/article_list_screen.dart`
- Removed duplicate `GVRadius` class definition (uses app_theme.dart's definition)

### 3. Key Implementation Details

ArticleListScreen now receives:
- `newspaperTitle`: Source of the article (e.g., "The Hindu")
- `newspaperDate`: Formatted date (e.g., "May 23, 2026")
- `language`: Language code (currently "Telugu")
- `articles`: List of UploadedArticle objects

## Features

### Article Display
- Article title
- 50-character content preview
- Category badge with color-coding:
  - News (purple/accent)
  - Government (green/success)
  - Editorial (blue)
  - Education (purple)
  - Health (pink)
  - Business (orange)
- Quality score percentage
- Processing status indicator

### Processing Indicators
- Completed: Green checkmark icon
- Processing: Spinner with progress bar
- Failed: Red error icon with retry button

### Progress Tracking
- Displays "Processing articles X of Y"
- Linear progress bar showing completion percentage
- Header shows newspaper metadata

### Navigation
- Tapping an article card navigates to PlayerScreen with full article queue
- Queue support allows playing articles in sequence
- Back button returns to article list

## Testing

### Prerequisites
- Physical Android device connected via USB (or emulator)
- Flutter development environment configured
- Internet connection for API calls

### Test Scenarios

#### Test 1: Single Article Upload (Basic)
1. Launch app on physical Android device
2. Navigate to upload screen (add document)
3. Select camera or gallery source
4. Capture/upload a document
5. Review extracted text in ReviewScreen
6. Tap "Save and play" button
7. **Expected Result:**
   - Navigates to ArticleListScreen
   - Shows 1 article in list (1 of 1)
   - Article card displays title, preview, category, quality score
   - Status shows "completed" (green checkmark)

#### Test 2: Article Playback from List
1. From ArticleListScreen (after Test 1):
2. Tap the article card or play button
3. **Expected Result:**
   - Navigates to PlayerScreen
   - Audio plays correctly
   - All playback controls work

#### Test 3: Back Navigation
1. From PlayerScreen, tap back button
2. **Expected Result:**
   - Returns to ArticleListScreen
   - Article list is preserved
   - Can tap another article (if multiple articles exist)

#### Test 4: Empty State (Error Case)
1. (Future) Upload a document that yields no articles
2. **Expected Result:**
   - Shows empty state message
   - "No articles" heading with explanation

#### Test 5: Retry Failed Article (Future Enhancement)
1. (Future) When article processing fails:
2. Tap the red refresh icon on failed article
3. **Expected Result:**
   - Article status changes to "processing"
   - After 2 seconds, status updates to "completed"

### Device Testing Commands

```bash
# Build and run on connected device
flutter run -d <device-id>

# Build release APK
flutter build apk --release

# Install APK on device
adb install -r build/app/outputs/flutter-apk/app-release.apk

# View live logs
flutter logs
```

## Backward Compatibility

- Single-article uploads work unchanged (they're wrapped in a single-item list)
- PlayerScreen functionality is preserved
- Audio playback works exactly as before
- All UI components and styling are consistent

## Future Enhancements

1. **Multi-article Support**: Backend processing of multiple articles per newspaper
2. **Batch Processing**: Progress tracking for large newspapers
3. **Article Filtering**: Filter by category or processing status
4. **Audio Quality Settings**: Per-article audio quality selection
5. **Offline Support**: Cache processed articles locally

## Troubleshooting

### Articles not displaying
- Verify AudioUrl is populated in UploadedArticle
- Check that article content is not empty
- Ensure device has internet connectivity

### Audio not playing
- Verify audio URL is valid and accessible
- Check that SarvamAIService successfully generated audio
- Review PlayerScreen implementation for any issues

### Navigation fails
- Ensure ArticleListScreen is properly imported
- Verify UploadedArticle model structure matches expectations
- Check Flutter logs for stack traces

## File Locations

- ArticleListScreen: `/packages/app/lib/screens/article_list_screen.dart`
- ReviewScreen: `/packages/app/lib/screens/review_screen.dart`
- PlayerScreen: `/packages/app/lib/screens/player_screen.dart`
- UploadedArticle model: `/packages/app/lib/models/article.dart`
- App theme/design system: `/packages/app/lib/design/app_theme.dart`

## Code Quality

- All imports are properly organized
- No duplicate class definitions
- Deprecated APIs replaced with modern alternatives
- Null safety enforced throughout
- Error handling included for edge cases
