// Backward-compat re-export. Canonical file: design/components/transcript_player.dart
// All new code should import transcript_player.dart directly.
export 'transcript_player.dart';

import 'transcript_player.dart';
// Alias so any callsite using EnhancedAudioPlayer still compiles.
typedef EnhancedAudioPlayer = TranscriptPlayer;
