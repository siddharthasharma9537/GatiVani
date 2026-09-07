# Tests

## State of play

This suite was rebuilt in Phase 0 of [`docs/ORCHESTRATION_PLAN.md`](../../../docs/ORCHESTRATION_PLAN.md).

What was here before did not compile. Every file imported services that had
been deleted (`firebase_service.dart`, `gemini_service.dart`,
`news_service.dart`, `SarvamAIService`) or screens that moved from
`lib/screens/` to `lib/features/`. Because `ci.yml` ran `flutter test` with
`continue-on-error: true`, CI reported green the entire time. The old README
claimed ">95% service coverage" and described a `run_tests.sh` with unit /
widget / screen / integration layers; none of it had been true for a long
while.

All of it is gone. `flutter test` now blocks CI, so what lives here has to
pass.

## What is covered

- `services/sentence_timing_service_test.dart` — read-along highlight timing:
  binary search over timings, half-open interval boundaries, clamping past
  either end, and gap-free estimated word/sentence timings. Pure Dart, no
  plugins, no network.

That is a deliberately small honest baseline, not a target. It is also the
right first thing to protect: Sarvam forced alignment is disabled for cost, so
the player depends on these estimates for highlighting.

## Running them

```bash
cd packages/app
flutter test                                              # everything
flutter test test/services/sentence_timing_service_test.dart   # one file
flutter test --coverage                                   # writes coverage/lcov.info
```

## Adding tests

Prefer pure-Dart logic tests — they need no device, run in milliseconds, and
do not rot when the UI is restyled. Good next candidates, in rough order of
value:

1. `text_highlight_service.dart` — same read-along path, more logic.
2. The chunk-advance bookkeeping in `playback_service.dart`, which has
   accumulated several subtle fixes (chunk-source swaps, position freezing,
   duplicate prefetch suppression) and no test to hold them in place.
3. Telugu sentence-boundary detection, which has already regressed once.

Widget tests are welcome, but write them against components that actually
exist in `lib/design/components/` — checking the import resolves before
writing the test is the lesson of everything above.
