/// Widget tests for AudioPlayerWidget component
/// Covers playback states, controls, progress, speed selection, and accessibility

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gativani/design/components/audio_player.dart';

void main() {
  group('AudioPlayerState', () {
    test('default constructor uses sensible defaults', () {
      final state = AudioPlayerState();
      expect(state.isPlaying, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.currentPosition, equals(Duration.zero));
      expect(state.duration, equals(Duration.zero));
      expect(state.playbackSpeed, equals(1.0));
    });

    test('progress returns 0 when duration is zero', () {
      final state = AudioPlayerState();
      expect(state.progress, equals(0.0));
    });

    test('progress is calculated correctly mid-playback', () {
      final state = AudioPlayerState(
        currentPosition: const Duration(seconds: 30),
        duration: const Duration(seconds: 120),
      );
      expect(state.progress, closeTo(0.25, 0.001));
    });

    test('progress reaches 1.0 at end of playback', () {
      final state = AudioPlayerState(
        currentPosition: const Duration(seconds: 60),
        duration: const Duration(seconds: 60),
      );
      expect(state.progress, equals(1.0));
    });

    test('progress handles fractional positions', () {
      final state = AudioPlayerState(
        currentPosition: const Duration(milliseconds: 1500),
        duration: const Duration(milliseconds: 3000),
      );
      expect(state.progress, closeTo(0.5, 0.001));
    });
  });

  group('AudioPlayerWidget', () {
    Widget buildSubject({
      AudioPlayerState? state,
      VoidCallback? onPlayPause,
      VoidCallback? onNextTrack,
      VoidCallback? onPreviousTrack,
      VoidCallback? onSkipForward,
      VoidCallback? onSkipBackward,
      Function(double)? onPositionChanged,
      Function(double)? onSpeedChanged,
      String? articleTitle,
      String? articleSource,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: AudioPlayerWidget(
            playerState: state ?? AudioPlayerState(),
            onPlayPause: onPlayPause ?? () {},
            onNextTrack: onNextTrack,
            onPreviousTrack: onPreviousTrack,
            onSkipForward: onSkipForward,
            onSkipBackward: onSkipBackward,
            onPositionChanged: onPositionChanged,
            onSpeedChanged: onSpeedChanged,
            articleTitle: articleTitle,
            articleSource: articleSource,
          ),
        ),
      );
    }

    testWidgets('renders without article title section by default',
        (tester) async {
      await tester.pumpWidget(buildSubject());
      expect(find.byType(AudioPlayerWidget), findsOneWidget);
    });

    testWidgets('renders article title when provided', (tester) async {
      await tester.pumpWidget(buildSubject(articleTitle: 'Breaking News'));
      expect(find.text('Breaking News'), findsOneWidget);
    });

    testWidgets('renders article source when provided alongside title',
        (tester) async {
      await tester.pumpWidget(buildSubject(
        articleTitle: 'Breaking News',
        articleSource: 'Andhra Jyothi',
      ));
      expect(find.text('Andhra Jyothi'), findsOneWidget);
    });

    testWidgets('source is hidden when title is null', (tester) async {
      await tester.pumpWidget(buildSubject(articleSource: 'Sakshi'));
      expect(find.text('Sakshi'), findsNothing);
    });

    testWidgets('shows play icon when not playing', (tester) async {
      await tester.pumpWidget(buildSubject(
        state: AudioPlayerState(isPlaying: false),
      ));
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('shows pause icon when playing', (tester) async {
      await tester.pumpWidget(buildSubject(
        state: AudioPlayerState(isPlaying: true),
      ));
      // Run animations and let the controller advance
      await tester.pump();
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    });

    testWidgets('tapping play/pause icon invokes callback', (tester) async {
      int tapCount = 0;
      await tester.pumpWidget(buildSubject(
        onPlayPause: () => tapCount++,
      ));

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      expect(tapCount, equals(1));
    });

    testWidgets('skip backward 10s control is present', (tester) async {
      await tester.pumpWidget(buildSubject());
      expect(find.byIcon(Icons.replay_10_outlined), findsOneWidget);
    });

    testWidgets('skip forward 10s control is present', (tester) async {
      await tester.pumpWidget(buildSubject());
      expect(find.byIcon(Icons.forward_10_outlined), findsOneWidget);
    });

    testWidgets('next track button invokes callback', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(buildSubject(onNextTrack: () => tapped = true));
      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      expect(tapped, isTrue);
    });

    testWidgets('previous track button invokes callback', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
          buildSubject(onPreviousTrack: () => tapped = true));
      await tester.tap(find.byIcon(Icons.skip_previous_rounded));
      expect(tapped, isTrue);
    });

    testWidgets('skip forward callback wires up', (tester) async {
      bool tapped = false;
      await tester
          .pumpWidget(buildSubject(onSkipForward: () => tapped = true));
      await tester.tap(find.byIcon(Icons.forward_10_outlined));
      expect(tapped, isTrue);
    });

    testWidgets('skip backward callback wires up', (tester) async {
      bool tapped = false;
      await tester
          .pumpWidget(buildSubject(onSkipBackward: () => tapped = true));
      await tester.tap(find.byIcon(Icons.replay_10_outlined));
      expect(tapped, isTrue);
    });

    testWidgets('current playback speed is shown on speed button',
        (tester) async {
      await tester.pumpWidget(buildSubject(
        state: AudioPlayerState(playbackSpeed: 1.25),
      ));
      expect(find.text('1.25x'), findsOneWidget);
    });

    testWidgets('opening speed menu shows speed options', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.tap(find.byIcon(Icons.speed_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Playback Speed'), findsOneWidget);
      for (final speed in ['0.5x', '0.75x', '1.0x', '1.25x', '1.5x', '2.0x']) {
        expect(find.text(speed), findsOneWidget);
      }
    });

    testWidgets('selecting a speed option invokes onSpeedChanged',
        (tester) async {
      double? selected;
      await tester.pumpWidget(buildSubject(
        onSpeedChanged: (s) => selected = s,
      ));
      await tester.tap(find.byIcon(Icons.speed_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.5x'));
      await tester.pumpAndSettle();
      expect(selected, equals(1.5));
    });

    testWidgets('loading indicator is shown when isLoading is true',
        (tester) async {
      await tester.pumpWidget(buildSubject(
        state: AudioPlayerState(isLoading: true),
      ));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('loading indicator hidden when isLoading is false',
        (tester) async {
      await tester.pumpWidget(buildSubject());
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('formats duration as mm:ss when under one hour',
        (tester) async {
      await tester.pumpWidget(buildSubject(
        state: AudioPlayerState(
          currentPosition: const Duration(minutes: 1, seconds: 5),
          duration: const Duration(minutes: 5),
        ),
      ));
      expect(find.text('01:05'), findsOneWidget);
      expect(find.text('05:00'), findsOneWidget);
    });

    testWidgets('formats duration as hh:mm:ss when over one hour',
        (tester) async {
      await tester.pumpWidget(buildSubject(
        state: AudioPlayerState(
          currentPosition: const Duration(hours: 1, minutes: 2, seconds: 3),
          duration: const Duration(hours: 2),
        ),
      ));
      expect(find.text('01:02:03'), findsOneWidget);
      expect(find.text('02:00:00'), findsOneWidget);
    });

    testWidgets('slider is interactable and reports position', (tester) async {
      double? lastReported;
      await tester.pumpWidget(buildSubject(
        state: AudioPlayerState(
          currentPosition: const Duration(seconds: 30),
          duration: const Duration(seconds: 120),
        ),
        onPositionChanged: (v) => lastReported = v,
      ));

      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);

      // Drag the slider via gesture
      await tester.drag(slider, const Offset(200, 0));
      await tester.pump();
      expect(lastReported, isNotNull);
    });

    testWidgets('progress slider value is clamped within [0,1]',
        (tester) async {
      // Set a state that would produce progress > 1 if not clamped
      await tester.pumpWidget(buildSubject(
        state: AudioPlayerState(
          currentPosition: const Duration(seconds: 200),
          duration: const Duration(seconds: 100),
        ),
      ));

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, lessThanOrEqualTo(1.0));
      expect(slider.value, greaterThanOrEqualTo(0.0));
    });

    testWidgets('didUpdateWidget animates play button when state flips',
        (tester) async {
      final widget = StatefulBuilder(
        builder: (context, setState) {
          bool playing = false;
          return MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  AudioPlayerWidget(
                    playerState: AudioPlayerState(isPlaying: playing),
                    onPlayPause: () => setState(() => playing = !playing),
                  ),
                ],
              ),
            ),
          );
        },
      );
      await tester.pumpWidget(widget);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();
      // Animation completes without throwing
      expect(find.byType(AudioPlayerWidget), findsOneWidget);
    });

    testWidgets('handles disposal cleanly', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      // No exceptions = pass
      expect(tester.takeException(), isNull);
    });
  });
}
