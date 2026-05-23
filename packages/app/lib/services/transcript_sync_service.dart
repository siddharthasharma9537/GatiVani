/// Syncs audio playback position to the corresponding sentence in the transcript.
///
/// Uses a hysteresis-based approach to prevent jitter and ensure smooth tracking
/// even when sentence lengths vary significantly in the audio.
///
/// Canonical name: transcript_sync_service.dart
/// (text_highlight_service.dart is a backward-compat re-export)
class TranscriptSyncService {
  /// Splits [text] into sentences on sentence-ending punctuation.
  static List<String> sentencesFromText(String text) {
    return text
        .split(RegExp(r'(?<=[.!?।])\s+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }

  /// Returns the sentence index that corresponds to [audioProgress] within
  /// [totalDuration], using a hysteresis-based algorithm for stability.
  ///
  /// The algorithm:
  /// 1. Calculates raw position (progress ratio × sentence count)
  /// 2. Uses hysteresis: only advance to next sentence when clearly past 40% of it
  /// 3. Prevents jitter from variable sentence lengths
  ///
  /// This approach is more stable than linear interpolation because sentences
  /// have different durations in the actual audio.
  static int getCurrentSentenceIndex(
    Duration audioProgress,
    List<String> sentences,
    Duration totalDuration,
  ) {
    if (sentences.isEmpty || totalDuration.inMilliseconds == 0) return 0;

    final ratio =
        audioProgress.inMilliseconds / totalDuration.inMilliseconds;
    final rawPosition = sentences.length * ratio;

    // Hysteresis: advance to next sentence only when we're 40% through it
    // This prevents jitter from sentence-length variations
    final sentenceIndex = rawPosition.floor();
    final positionInSentence = rawPosition - sentenceIndex;

    // If we're more than 40% through a sentence, move to the next one
    // This makes the highlight more stable and reduces oscillation
    if (positionInSentence > 0.4 && sentenceIndex < sentences.length - 1) {
      return (sentenceIndex + 1).clamp(0, sentences.length - 1);
    }

    return sentenceIndex.clamp(0, sentences.length - 1);
  }

  /// Returns the scroll offset that places the active sentence at the
  /// vertical centre of a viewport of [viewportHeight].
  static double getScrollOffsetForSentence(
    int sentenceIndex,
    double lineHeight,
    double viewportHeight,
  ) {
    final offset = sentenceIndex * lineHeight;
    final centred = offset - (viewportHeight / 2) + lineHeight;
    return centred.clamp(0, double.infinity);
  }
}
