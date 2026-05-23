// Backward-compat re-export. Canonical file: screens/review_screen.dart
// All new code should import review_screen.dart directly.
export 'review_screen.dart';

import 'review_screen.dart';
// Alias so any remaining callsite using OCRReviewScreen still compiles.
typedef OCRReviewScreen = ReviewScreen;
