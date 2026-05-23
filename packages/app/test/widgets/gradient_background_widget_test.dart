/// Widget tests for GradientBackground component
///
/// GradientBackground wraps a child with a themed LinearGradient. The widget
/// resolves to a specific gradient based on:
///   * The [GatiVaniGradient] enum value passed in
///   * Whether the current ThemeData.brightness is dark
///   * The [adaptiveDark] flag (when true and brightness is dark, the
///     dark gradient is forced regardless of the enum value)
///
/// These tests verify resolution logic, child rendering, and that no
/// gestures are intercepted (DecoratedBox is gesture-transparent).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gativani/design/components/gradient_background.dart';
import 'package:gativani/design/theme/colors.dart';

void main() {
  group('GradientBackground Widget Tests', () {
    /// Helper to extract the resolved LinearGradient from the rendered widget.
    LinearGradient _readGradient(WidgetTester tester) {
      final decorated = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(GradientBackground),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      final decoration = decorated.decoration as BoxDecoration;
      return decoration.gradient as LinearGradient;
    }

    Widget buildSubject({
      Widget? child,
      GatiVaniGradient gradient = GatiVaniGradient.saffron,
      bool adaptiveDark = true,
      ThemeMode themeMode = ThemeMode.light,
    }) {
      return MaterialApp(
        themeMode: themeMode,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        home: Scaffold(
          body: GradientBackground(
            gradient: gradient,
            adaptiveDark: adaptiveDark,
            child: child ?? const Text('Child Content'),
          ),
        ),
      );
    }

    group('Rendering', () {
      testWidgets('renders child widget inside', (tester) async {
        await tester.pumpWidget(buildSubject(child: const Text('Hello')));
        expect(find.text('Hello'), findsOneWidget);
      });

      testWidgets('wraps child in a DecoratedBox', (tester) async {
        await tester.pumpWidget(buildSubject());
        expect(
          find.descendant(
            of: find.byType(GradientBackground),
            matching: find.byType(DecoratedBox),
          ),
          findsAtLeastNWidgets(1),
        );
      });

      testWidgets('default constructor uses saffron gradient', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GradientBackground(
                child: const SizedBox(),
              ),
            ),
          ),
        );
        final gradient = _readGradient(tester);
        expect(gradient.colors, equals(GradientPalette.saffronGradient.colors));
      });
    });

    group('Gradient resolution (light mode)', () {
      testWidgets('saffron gradient', (tester) async {
        await tester.pumpWidget(
          buildSubject(gradient: GatiVaniGradient.saffron),
        );
        expect(
          _readGradient(tester).colors,
          equals(GradientPalette.saffronGradient.colors),
        );
      });

      testWidgets('saffronCoral gradient', (tester) async {
        await tester.pumpWidget(
          buildSubject(gradient: GatiVaniGradient.saffronCoral),
        );
        expect(
          _readGradient(tester).colors,
          equals(GradientPalette.saffronCoralGradient.colors),
        );
      });

      testWidgets('teal gradient', (tester) async {
        await tester.pumpWidget(
          buildSubject(gradient: GatiVaniGradient.teal),
        );
        expect(
          _readGradient(tester).colors,
          equals(GradientPalette.teaGradient.colors),
        );
      });

      testWidgets('gold gradient', (tester) async {
        await tester.pumpWidget(
          buildSubject(gradient: GatiVaniGradient.gold),
        );
        expect(
          _readGradient(tester).colors,
          equals(GradientPalette.goldGradient.colors),
        );
      });

      testWidgets('neutral gradient', (tester) async {
        await tester.pumpWidget(
          buildSubject(gradient: GatiVaniGradient.neutral),
        );
        expect(
          _readGradient(tester).colors,
          equals(GradientPalette.neutralGradient.colors),
        );
      });

      testWidgets('dark gradient explicit value', (tester) async {
        await tester.pumpWidget(
          buildSubject(gradient: GatiVaniGradient.dark),
        );
        expect(
          _readGradient(tester).colors,
          equals(GradientPalette.darkGradient.colors),
        );
      });
    });

    group('Adaptive dark mode', () {
      testWidgets('uses dark gradient when adaptiveDark=true and in dark mode',
          (tester) async {
        await tester.pumpWidget(
          buildSubject(
            gradient: GatiVaniGradient.saffron,
            adaptiveDark: true,
            themeMode: ThemeMode.dark,
          ),
        );
        expect(
          _readGradient(tester).colors,
          equals(GradientPalette.darkGradient.colors),
        );
      });

      testWidgets(
          'uses requested gradient when adaptiveDark=false even in dark mode',
          (tester) async {
        await tester.pumpWidget(
          buildSubject(
            gradient: GatiVaniGradient.teal,
            adaptiveDark: false,
            themeMode: ThemeMode.dark,
          ),
        );
        expect(
          _readGradient(tester).colors,
          equals(GradientPalette.teaGradient.colors),
        );
      });

      testWidgets(
          'uses requested gradient when adaptiveDark=true but in light mode',
          (tester) async {
        await tester.pumpWidget(
          buildSubject(
            gradient: GatiVaniGradient.gold,
            adaptiveDark: true,
            themeMode: ThemeMode.light,
          ),
        );
        expect(
          _readGradient(tester).colors,
          equals(GradientPalette.goldGradient.colors),
        );
      });
    });

    group('Gesture pass-through', () {
      testWidgets('does not intercept tap events on child', (tester) async {
        var childTapped = 0;
        await tester.pumpWidget(
          buildSubject(
            child: GestureDetector(
              onTap: () => childTapped++,
              child: const SizedBox(
                width: 100,
                height: 100,
                child: Text('Tap me'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Tap me'));
        expect(childTapped, equals(1));
      });
    });

    group('Composition', () {
      testWidgets('can wrap complex layouts', (tester) async {
        await tester.pumpWidget(
          buildSubject(
            child: Column(
              children: const [
                Text('Header'),
                Text('Body'),
                Text('Footer'),
              ],
            ),
          ),
        );
        expect(find.text('Header'), findsOneWidget);
        expect(find.text('Body'), findsOneWidget);
        expect(find.text('Footer'), findsOneWidget);
      });

      testWidgets('rebuilds when gradient changes', (tester) async {
        await tester.pumpWidget(buildSubject(gradient: GatiVaniGradient.gold));
        expect(_readGradient(tester).colors,
            equals(GradientPalette.goldGradient.colors));

        await tester.pumpWidget(buildSubject(gradient: GatiVaniGradient.teal));
        expect(_readGradient(tester).colors,
            equals(GradientPalette.teaGradient.colors));
      });
    });

    group('Edge cases', () {
      testWidgets('handles empty child gracefully', (tester) async {
        await tester.pumpWidget(buildSubject(child: const SizedBox.shrink()));
        expect(find.byType(GradientBackground), findsOneWidget);
      });

      testWidgets('every enum value resolves to a non-null gradient',
          (tester) async {
        for (final value in GatiVaniGradient.values) {
          await tester.pumpWidget(buildSubject(gradient: value));
          // _readGradient throws if gradient is null
          final resolved = _readGradient(tester);
          expect(resolved, isA<LinearGradient>());
        }
      });
    });
  });
}
