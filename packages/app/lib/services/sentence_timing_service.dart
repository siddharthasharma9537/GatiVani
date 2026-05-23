/// A word or sentence with its exact timing in the audio
class SentenceTiming {
  final String text;
  final Duration startTime;
  final Duration endTime;
  final bool isWord;  // true = word, false = sentence

  SentenceTiming({
    required this.text,
    required this.startTime,
    required this.endTime,
    this.isWord = false,
  });

  Duration get duration => endTime - startTime;

  Map<String, dynamic> toJson() => {
        'text': text,
        'startMs': startTime.inMilliseconds,
        'endMs': endTime.inMilliseconds,
        'isWord': isWord,
      };

  static SentenceTiming fromJson(Map<String, dynamic> json) => SentenceTiming(
        text: json['text'] as String,
        startTime: Duration(milliseconds: json['startMs'] as int),
        endTime: Duration(milliseconds: json['endMs'] as int),
        isWord: json['isWord'] as bool? ?? false,
      );
}

/// Manages word and sentence timing metadata for perfect audio-text synchronization.
///
/// Supports both word-level (like music app lyrics) and sentence-level sync.
/// Word-level: Individual words are highlighted as spoken (perfect precision).
/// Sentence-level: Entire sentences are highlighted together (good balance).
class SentenceTimingService {
  /// Get the index for a given audio position using exact timings (binary search)
  static int getIndexForPosition(
    Duration position,
    List<SentenceTiming> timings,
  ) {
    if (timings.isEmpty) return 0;

    // Binary search for O(log n) efficiency
    int left = 0;
    int right = timings.length - 1;

    while (left <= right) {
      int mid = (left + right) ~/ 2;
      final timing = timings[mid];

      if (position >= timing.startTime && position < timing.endTime) {
        return mid;  // Found exact match
      } else if (position < timing.startTime) {
        right = mid - 1;
      } else {
        left = mid + 1;
      }
    }

    return (left - 1).clamp(0, timings.length - 1);
  }

  /// Split text into words (more granular than sentences)
  static List<String> wordsFromText(String text) {
    return text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// Build word-level timings from estimated durations
  /// This gives word-level sync (like Spotify lyrics)
  static List<SentenceTiming> buildEstimatedWordTimings(
    String text,
    Duration totalDuration,
  ) {
    final words = wordsFromText(text);
    if (words.isEmpty) return [];

    final timings = <SentenceTiming>[];
    final estimatedDurationPerWord =
        totalDuration.inMilliseconds / words.length;

    int cumulativeMs = 0;
    for (final word in words) {
      final startMs = cumulativeMs;
      final endMs = (cumulativeMs + estimatedDurationPerWord).round();

      timings.add(SentenceTiming(
        text: word,
        startTime: Duration(milliseconds: startMs),
        endTime: Duration(milliseconds: endMs),
        isWord: true,
      ));

      cumulativeMs = endMs;
    }

    return timings;
  }

  /// Build sentence timings from estimated durations
  /// Used as fallback when exact timing metadata isn't available
  static List<SentenceTiming> buildEstimatedSentenceTimings(
    List<String> sentences,
    Duration totalDuration,
  ) {
    if (sentences.isEmpty) return [];

    final timings = <SentenceTiming>[];
    final estimatedDurationPerSentence =
        totalDuration.inMilliseconds / sentences.length;

    int cumulativeMs = 0;
    for (final sentence in sentences) {
      final startMs = cumulativeMs;
      final endMs = (cumulativeMs + estimatedDurationPerSentence).round();

      timings.add(SentenceTiming(
        text: sentence,
        startTime: Duration(milliseconds: startMs),
        endTime: Duration(milliseconds: endMs),
        isWord: false,
      ));

      cumulativeMs = endMs;
    }

    return timings;
  }

  /// Get highlighted word from word-level timings
  static String? getHighlightedWord(
    Duration position,
    List<SentenceTiming> wordTimings,
  ) {
    if (wordTimings.isEmpty) return null;
    final index = getIndexForPosition(position, wordTimings);
    return wordTimings[index].text;
  }

  /// Get text with highlighted word inline
  static String getHighlightedText(
    Duration position,
    List<SentenceTiming> wordTimings,
  ) {
    if (wordTimings.isEmpty) return '';

    final currentIndex = getIndexForPosition(position, wordTimings);
    final highlightedWords = wordTimings.asMap().entries.map((entry) {
      final word = entry.value.text;
      return entry.key == currentIndex ? '→$word←' : word;
    }).toList();

    return highlightedWords.join(' ');
  }
}
