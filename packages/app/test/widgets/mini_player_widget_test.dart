/// Widget tests for MiniPlayer component
///
/// MiniPlayer is a presentational widget that docks above the bottom nav.
/// It takes an [AudioPlayerState] plus callbacks and is decoupled from any
/// audio backend, which makes it a great unit-level widget test target.
///
/// Coverage areas:
///   * Renders title, source and progress
///   * Toggles play/pause icon based on playerState.isPlaying
///   * Invokes onPlayPause / onTap / onClose callbacks
///   * Optional close button visibility
///   * Progress indicator value clamping
///   * Accessibility semantics
///   * Long title / source overflow
///   * Dark mode rendering

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gativani/design/components/audio_player.dart';
import 'package:gativani/design/components/mini_player.dart';

void main() {
  group('MiniPlayer Widget Tests', () {
    /// Helper to build the widget under test with sensible defaults.
    Widget buildSubject({
      AudioPlayerState? state,
      String title = 'Test Article',
      String source = 'Test Source',
      VoidCallback? onPlayPause,
      VoidCallback? onTap,
      VoidCallback? onClose,
      ThemeMode themeMode = ThemeMode.light,
    }) {
      return MaterialApp(
        themeMode: themeMode,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        home: Scaffold(
          body: MiniPlayer(
            playerState: state ?? AudioPlayerState(),
            title: title,
            source: source,
            onPlayPause: onPlayPause ?? () {},
            onTap: onTap,
            onClose: onClose,
          ),
        ),
      );
    }

    group('Rendering', () {
      testWidgets('renders title text', (tester) async {
        await tester.pumpWidget(
          buildSubject(title: 'Breaking News Story'),
        );
        expect(find.text('Breaking News Story'), findsOneWidget);
      });

      testWidgets('renders source text', (tester) async {
        await tester.pumpWidget(
          buildSubject(source: 'Andhra Jyothi'),
        );
        expect(find.text('Andhra Jyothi'), findsOneWidget);
      });

      testWidgets('renders headphone artwork icon', (tester) async {
        await tester.pumpWidget(buildSubject());
        expect(find.byIcon(Icons.headphones_rounded), findsOneWidget);
      });

      testWidgets('renders linear progress indicator', (tester) async {
        await tester.pumpWidget(buildSubject());
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      });
    });

    group('Play/Pause Icon State', () {
      testWidgets('shows play icon when not playing', (tester) async {
        await tester.pumpWidget(
          buildSubject(state: AudioPlayerState(isPlaying: false)),
        );
        expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
        expect(find.byIcon(Icons.pause_circle_filled_rounded), findsNothing);
      });

      testWidgets('shows pause icon when playing', (tester) async {
        await tester.pumpWidget(
          buildSubject(state: AudioPlayerState(isPlaying: true)),
        );
        expect(find.byIcon(Icons.pause_circle_filled_rounded), findsOneWidget);
        expect(find.byIcon(Icons.play_circle_fill_rounded), findsNothing);
      });

      testWidgets('play button has correct tooltip when not playing',
          (tester) async {
        await tester.pumpWidget(
          buildSubject(state: AudioPlayerState(isPlaying: false)),
        );
        expect(find.byTooltip('Play'), findsOneWidget);
      });

      testWidgets('play button has correct tooltip when playing',
          (tester) async {
        await tester.pumpWidget(
          buildSubject(state: AudioPlayerState(isPlaying: true)),
        );
        expect(find.byTooltip('Pause'), findsOneWidget);
      });
    });

    group('Callbacks', () {
      testWidgets('onPlayPause fires when icon button is tapped',
          (tester) async {
        var tapped = 0;
        await tester.pumpWidget(
          buildSubject(onPlayPause: () => tapped++),
        );
        await tester.tap(find.byIcon(Icons.play_circle_fill_rounded));
        expect(tapped, equals(1));
      });

      testWidgets('onTap fires when the player surface is tapped',
          (tester) async {
        var tapped = 0;
        await tester.pumpWidget(
          buildSubject(onTap: () => tapped++),
        );
        // Tap on the title text area (not the icon button)
        await tester.tap(find.text('Test Article'));
        expect(tapped, equals(1));
      });

      testWidgets('onClose fires when close icon is tapped', (tester) async {
        var closed = 0;
        await tester.pumpWidget(
          buildSubject(onClose: () => closed++),
        );
        await tester.tap(find.byIcon(Icons.close_rounded));
        expect(closed, equals(1));
      });

      testWidgets('onClose button is hidden when callback is null',
          (tester) async {
        await tester.pumpWidget(buildSubject(onClose: null));
        expect(find.byIcon(Icons.close_rounded), findsNothing);
      });
    });

    group('Progress Indicator', () {
      testWidgets('reflects playerState.progress value', (tester) async {
        await tester.pumpWidget(
          buildSubject(
            state: AudioPlayerState(
              currentPosition: const Duration(seconds: 30),
              duration: const Duration(seconds: 120),
            ),
          ),
        );

        final indicator =
            tester.widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator));
        expect(indicator.value, closeTo(0.25, 0.001));
      });

      testWidgets('clamps progress at zero', (tester) async {
        await tester.pumpWidget(buildSubject());
        final indicator =
            tester.widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator));
        expect(indicator.value, equals(0.0));
      });

      testWidgets('clamps progress to <= 1.0 even if state overshoots',
          (tester) async {
        // currentPosition > duration -> progress > 1.0 in raw form
        await tester.pumpWidget(
          buildSubject(
            state: AudioPlayerState(
              currentPosition: const Duration(seconds: 200),
              duration: const Duration(seconds: 100),
            ),
          ),
        );
        final indicator =
            tester.widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator));
        expect(indicator.value, lessThanOrEqualTo(1.0));
      });
    });

    group('Accessibility', () {
      testWidgets('exposes container semantics with title and source',
          (tester) async {
        await tester.pumpWidget(
          buildSubject(title: 'Hello', source: 'World'),
        );
        // Semantics node should contain combined label
        expect(
          find.bySemanticsLabel(RegExp(r'Hello.*World')),
          findsOneWidget,
        );
      });
    });

    group('Overflow Handling', () {
      testWidgets('long title renders with ellipsis maxLines=1',
          (tester) async {
        final longTitle = 'Very long article title ' * 20;
        await tester.pumpWidget(
          buildSubject(title: longTitle),
        );
        final textWidget = tester.widget<Text>(find.text(longTitle));
        expect(textWidget.maxLines, equals(1));
        expect(textWidget.overflow, equals(TextOverflow.ellipsis));
      });

      testWidgets('long source renders with ellipsis maxLines=1',
          (tester) async {
        final longSource = 'A very long source name ' * 10;
        await tester.pumpWidget(
          buildSubject(source: longSource),
        );
        final textWidget = tester.widget<Text>(find.text(longSource));
        expect(textWidget.maxLines, equals(1));
        expect(textWidget.overflow, equals(TextOverflow.ellipsis));
      });
    });

    group('Theming', () {
      testWidgets('renders without crashing in dark mode', (tester) async {
        await tester.pumpWidget(
          buildSubject(themeMode: ThemeMode.dark),
        );
        expect(find.byType(MiniPlayer), findsOneWidget);
      });

      testWidgets('uses Material elevation', (tester) async {
        await tester.pumpWidget(buildSubject());
        final material = tester.widget<Material>(
          find.descendant(
            of: find.byType(MiniPlayer),
            matching: find.byType(Material),
          ).first,
        );
        expect(material.elevation, equals(8));
      });
    });

    group('Edge Cases', () {
      testWidgets('handles empty title and source', (tester) async {
        await tester.pumpWidget(
          buildSubject(title: '', source: ''),
        );
        expect(find.byType(MiniPlayer), findsOneWidget);
      });

      testWidgets('handles loading state', (tester) async {
        await tester.pumpWidget(
          buildSubject(state: AudioPlayerState(isLoading: true)),
        );
        expect(find.byType(MiniPlayer), findsOneWidget);
      });

      testWidgets('handles unicode title (Telugu)', (tester) async {
        const teluguTitle = 'తెలుగు సమాచారం';
        await tester.pumpWidget(
          buildSubject(title: teluguTitle),
        );
        expect(find.text(teluguTitle), findsOneWidget);
      });
    });
  });
}
