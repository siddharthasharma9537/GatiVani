// Backward-compat re-export. Canonical file: transcript_sync_service.dart
export 'transcript_sync_service.dart';

// Alias so old call-sites using TextHighlightService still compile.
import 'transcript_sync_service.dart';
typedef TextHighlightService = TranscriptSyncService;
