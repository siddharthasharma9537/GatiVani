/// Widget tests for SettingsScreen
///
/// SettingsScreen is intentionally self-contained: it holds its own state and
/// renders Material list tiles for theme, playback speed, auto-play, voice
/// language, Wi-Fi-only downloads, push notifications, and "About" entries.
///
/// We exercise:
///   * Initial render contains every section header
///   * Defaults match the values declared in _SettingsScreenState
///   * Toggling a SwitchListTile updates state and re-renders
///   * PopupMenuButton selections update the displayed subtitle
///   * "Privacy policy" and "Terms of service" show a SnackBar on tap
///   * Version footer renders

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gativani/screens/settings_screen.dart';

void main() {
  group('SettingsScreen', () {
    Widget buildSubject() {
      return const MaterialApp(
        home: SettingsScreen(),
      );
    }

    group('Initial Render', () {
      testWidgets('renders all section headers', (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        // _SectionHeader uppercases its label
        expect(find.text('APPEARANCE'), findsOneWidget);
        expect(find.text('PLAYBACK'), findsOneWidget);
        expect(find.text('VOICE & LANGUAGE'), findsOneWidget);
        expect(find.text('DATA & STORAGE'), findsOneWidget);
        expect(find.text('NOTIFICATIONS'), findsOneWidget);
        expect(find.text('ABOUT'), findsOneWidget);
      });

      testWidgets('renders default theme as "Follow system"',
          (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();
        expect(find.text('Follow system'), findsOneWidget);
      });

      testWidgets('renders default playback speed as 1.0x', (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();
        expect(find.text('1.0x'), findsOneWidget);
      });

      testWidgets('renders default voice language as Telugu', (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();
        expect(find.text('Telugu'), findsOneWidget);
      });

      testWidgets('renders version footer', (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();
        expect(find.text('Version'), findsOneWidget);
        expect(find.text('1.0.0'), findsOneWidget);
        expect(find.text('GatiVani'), findsOneWidget);
      });
    });

    group('Switch Tiles', () {
      testWidgets('auto-play next is on by default and toggles off',
          (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        final autoPlayFinder = find.widgetWithText(
          SwitchListTile,
          'Auto-play next article',
        );
        expect(autoPlayFinder, findsOneWidget);

        var tile = tester.widget<SwitchListTile>(autoPlayFinder);
        expect(tile.value, isTrue);

        await tester.tap(autoPlayFinder);
        await tester.pumpAndSettle();

        tile = tester.widget<SwitchListTile>(autoPlayFinder);
        expect(tile.value, isFalse);
      });

      testWidgets('download on Wi-Fi toggles state', (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        final finder = find.widgetWithText(
          SwitchListTile,
          'Download on Wi-Fi only',
        );
        expect(finder, findsOneWidget);

        var tile = tester.widget<SwitchListTile>(finder);
        expect(tile.value, isTrue);

        await tester.tap(finder);
        await tester.pumpAndSettle();

        tile = tester.widget<SwitchListTile>(finder);
        expect(tile.value, isFalse);
      });

      testWidgets('push notifications toggles state', (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        final finder = find.widgetWithText(
          SwitchListTile,
          'Push notifications',
        );
        expect(finder, findsOneWidget);

        var tile = tester.widget<SwitchListTile>(finder);
        expect(tile.value, isTrue);

        await tester.tap(finder);
        await tester.pumpAndSettle();

        tile = tester.widget<SwitchListTile>(finder);
        expect(tile.value, isFalse);
      });
    });

    group('Theme picker', () {
      testWidgets('selecting Dark updates subtitle', (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        // Find the theme tile and tap the popup menu
        final themeTileFinder = find.ancestor(
          of: find.text('Theme'),
          matching: find.byType(ListTile),
        );
        expect(themeTileFinder, findsOneWidget);

        // Tap the popup menu button (arrow_drop_down inside theme tile)
        final popupButton = find.descendant(
          of: themeTileFinder,
          matching: find.byType(PopupMenuButton<ThemeMode>),
        );
        await tester.tap(popupButton);
        await tester.pumpAndSettle();

        // Select "Dark"
        await tester.tap(find.text('Dark').last);
        await tester.pumpAndSettle();

        expect(find.text('Dark'), findsOneWidget);
      });

      testWidgets('selecting Light updates subtitle', (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        final themeTileFinder = find.ancestor(
          of: find.text('Theme'),
          matching: find.byType(ListTile),
        );
        final popupButton = find.descendant(
          of: themeTileFinder,
          matching: find.byType(PopupMenuButton<ThemeMode>),
        );
        await tester.tap(popupButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Light').last);
        await tester.pumpAndSettle();

        expect(find.text('Light'), findsOneWidget);
      });
    });

    group('Playback speed picker', () {
      testWidgets('selecting 1.5x updates subtitle', (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        final tileFinder = find.ancestor(
          of: find.text('Default playback speed'),
          matching: find.byType(ListTile),
        );
        final popupButton = find.descendant(
          of: tileFinder,
          matching: find.byType(PopupMenuButton<double>),
        );

        await tester.tap(popupButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('1.5x').last);
        await tester.pumpAndSettle();

        expect(find.text('1.5x'), findsOneWidget);
      });
    });

    group('Voice language picker', () {
      testWidgets('selecting English updates subtitle', (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        final tileFinder = find.ancestor(
          of: find.text('Voice language'),
          matching: find.byType(ListTile),
        );
        final popupButton = find.descendant(
          of: tileFinder,
          matching: find.byType(PopupMenuButton<String>),
        );

        await tester.tap(popupButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('English').last);
        await tester.pumpAndSettle();

        expect(find.text('English'), findsOneWidget);
      });

      testWidgets('language picker exposes Telugu, English, Hindi',
          (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        final tileFinder = find.ancestor(
          of: find.text('Voice language'),
          matching: find.byType(ListTile),
        );
        final popupButton = find.descendant(
          of: tileFinder,
          matching: find.byType(PopupMenuButton<String>),
        );
        await tester.tap(popupButton);
        await tester.pumpAndSettle();

        expect(find.text('Telugu'), findsWidgets);
        expect(find.text('English'), findsOneWidget);
        expect(find.text('Hindi'), findsOneWidget);
      });
    });

    group('About row taps', () {
      testWidgets('tapping Privacy policy shows SnackBar', (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Privacy policy'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.descendant(of: find.byType(SnackBar), matching: find.text('Privacy policy')),
            findsOneWidget);
      });

      testWidgets('tapping Terms of service shows SnackBar', (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Terms of service'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.descendant(of: find.byType(SnackBar), matching: find.text('Terms of service')),
            findsOneWidget);
      });
    });

    group('AppBar', () {
      testWidgets('AppBar title is "Settings"', (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: find.byType(AppBar), matching: find.text('Settings')),
          findsOneWidget,
        );
      });

      testWidgets('has flat elevation', (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();
        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        expect(appBar.elevation, equals(0));
      });
    });
  });
}
