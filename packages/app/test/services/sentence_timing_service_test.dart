/// Tests for SentenceTimingService — the read-along highlighting logic.
///
/// This replaces a test suite that had rotted into fiction: every previous test
/// imported services deleted long ago (`firebase_service`, `gemini_service`,
/// `news_service`) or screens moved to `lib/features/`, so `flutter test` could
/// not compile a single file. CI hid that with `continue-on-error: true` and
/// reported green regardless. See docs/ORCHESTRATION_PLAN.md Phase 0.
///
/// SentenceTimingService is chosen deliberately: it is pure Dart with no
/// plugins, no network and no Flutter bindings, so it runs anywhere and stays
/// fast. It also matters — with Sarvam forced alignment disabled for cost, the
/// player relies on these estimates for karaoke-style highlighting.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gativani_app/services/sentence_timing_service.dart';

void main() {
  group('SentenceTiming', () {
    test('round-trips through JSON', () {
      final original = SentenceTiming(
        text: 'తెలుగు',
        startTime: Duration(milliseconds: 1500),
        endTime: Duration(milliseconds: 2750),
        isWord: true,
      );

      final restored = SentenceTiming.fromJson(original.toJson());

      expect(restored.text, original.text);
      expect(restored.startTime, original.startTime);
      expect(restored.endTime, original.endTime);
      expect(restored.isWord, isTrue);
    });

    test('duration is the span between start and end', () {
      final t = SentenceTiming(
        text: 'x',
        startTime: Duration(seconds: 2),
        endTime: Duration(seconds: 5),
      );
      expect(t.duration, const Duration(seconds: 3));
    });

    test('isWord defaults to false when absent from JSON', () {
      final t = SentenceTiming.fromJson(
        const <String, dynamic>{'text': 'x', 'startMs': 0, 'endMs': 10},
      );
      expect(t.isWord, isFalse);
    });
  });

  group('getIndexForPosition', () {
    // 0–1s, 1–2s, 2–3s
    final timings = List.generate(
      3,
      (i) => SentenceTiming(
        text: 'seg$i',
        startTime: Duration(seconds: i),
        endTime: Duration(seconds: i + 1),
      ),
    );

    test('returns 0 for an empty list rather than throwing', () {
      expect(
        SentenceTimingService.getIndexForPosition(const Duration(seconds: 5), []),
        0,
      );
    });

    test('finds the segment containing the position', () {
      expect(
        SentenceTimingService.getIndexForPosition(
            const Duration(milliseconds: 500), timings),
        0,
      );
      expect(
        SentenceTimingService.getIndexForPosition(
            const Duration(milliseconds: 1500), timings),
        1,
      );
      expect(
        SentenceTimingService.getIndexForPosition(
            const Duration(milliseconds: 2500), timings),
        2,
      );
    });

    test('a boundary belongs to the segment it opens, not the one it closes',
        () {
      // Half-open intervals: [start, end). Without this, a position landing
      // exactly on a boundary highlights the line the reader has just left.
      expect(
        SentenceTimingService.getIndexForPosition(
            const Duration(seconds: 1), timings),
        1,
      );
      expect(
        SentenceTimingService.getIndexForPosition(
            const Duration(seconds: 2), timings),
        2,
      );
    });

    test('clamps past the end instead of running off the list', () {
      expect(
        SentenceTimingService.getIndexForPosition(
            const Duration(seconds: 99), timings),
        2,
      );
    });

    test('clamps before the start', () {
      expect(
        SentenceTimingService.getIndexForPosition(Duration.zero, timings),
        0,
      );
    });
  });

  group('wordsFromText', () {
    test('splits on runs of whitespace and drops empties', () {
      expect(
        SentenceTimingService.wordsFromText('  ఒక   రెండు\n\nమూడు  '),
        ['ఒక', 'రెండు', 'మూడు'],
      );
    });

    test('an all-whitespace string yields no words', () {
      expect(SentenceTimingService.wordsFromText('   \n  '), isEmpty);
    });
  });

  group('buildEstimatedWordTimings', () {
    test('covers the whole duration with no gaps between words', () {
      final timings = SentenceTimingService.buildEstimatedWordTimings(
        'ఒకటి రెండు మూడు నాలుగు',
        const Duration(seconds: 4),
      );

      expect(timings, hasLength(4));
      expect(timings.first.startTime, Duration.zero);
      // Each word begins exactly where the previous one ended — a gap here
      // shows up as a flicker of un-highlighted text mid-sentence.
      for (var i = 1; i < timings.length; i++) {
        expect(timings[i].startTime, timings[i - 1].endTime);
      }
      expect(timings.last.endTime, const Duration(seconds: 4));
      expect(timings.every((t) => t.isWord), isTrue);
    });

    test('returns nothing for empty text rather than dividing by zero', () {
      expect(
        SentenceTimingService.buildEstimatedWordTimings(
            '   ', const Duration(seconds: 10)),
        isEmpty,
      );
    });
  });

  group('buildEstimatedSentenceTimings', () {
    test('divides the duration across sentences without gaps', () {
      final timings = SentenceTimingService.buildEstimatedSentenceTimings(
        ['మొదటి వాక్యం.', 'రెండవ వాక్యం.'],
        const Duration(seconds: 10),
      );

      expect(timings, hasLength(2));
      expect(timings.first.startTime, Duration.zero);
      expect(timings[1].startTime, timings[0].endTime);
      expect(timings.last.endTime, const Duration(seconds: 10));
    });

    test('returns nothing for an empty sentence list', () {
      expect(
        SentenceTimingService.buildEstimatedSentenceTimings(
            const [], const Duration(seconds: 5)),
        isEmpty,
      );
    });
  });
}
