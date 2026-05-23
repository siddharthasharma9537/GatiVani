/// Widget tests for SearchBarWidget and ExpandableSearchBar components
/// Covers debounced typing, clearing, voice/filter buttons, recent searches.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gativani/design/components/search_bar.dart';

void main() {
  group('SearchBarConfig', () {
    test('uses default hint and settings', () {
      final config = SearchBarConfig();
      expect(config.hintText, equals('Search articles...'));
      expect(config.minCharsToSearch, equals(2));
      expect(config.debounceDuration, equals(const Duration(milliseconds: 300)));
      expect(config.showFilters, isTrue);
      expect(config.showVoiceSearch, isTrue);
    });

    test('allows custom configuration', () {
      final config = SearchBarConfig(
        hintText: 'Find news',
        minCharsToSearch: 3,
        showFilters: false,
        showVoiceSearch: false,
      );
      expect(config.hintText, equals('Find news'));
      expect(config.minCharsToSearch, equals(3));
      expect(config.showFilters, isFalse);
      expect(config.showVoiceSearch, isFalse);
    });
  });

  group('SearchBarWidget', () {
    Widget buildSubject({
      SearchBarConfig? config,
      Function(String)? onSearchChanged,
      Function(String)? onSearchSubmitted,
      VoidCallback? onClear,
      VoidCallback? onFilterTap,
      VoidCallback? onVoiceSearchTap,
      bool isLoading = false,
      TextEditingController? controller,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SearchBarWidget(
            config: config ?? const SearchBarConfig(),
            onSearchChanged: onSearchChanged,
            onSearchSubmitted: onSearchSubmitted,
            onClear: onClear,
            onFilterTap: onFilterTap,
            onVoiceSearchTap: onVoiceSearchTap,
            isLoading: isLoading,
            controller: controller,
          ),
        ),
      );
    }

    testWidgets('renders hint text', (tester) async {
      await tester.pumpWidget(buildSubject());
      expect(find.text('Search articles...'), findsOneWidget);
    });

    testWidgets('renders search icon', (tester) async {
      await tester.pumpWidget(buildSubject());
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets('renders filter and voice icons when enabled', (tester) async {
      await tester.pumpWidget(buildSubject());
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    });

    testWidgets('hides filter and voice icons when disabled', (tester) async {
      await tester.pumpWidget(buildSubject(
        config: SearchBarConfig(showFilters: false, showVoiceSearch: false),
      ));
      expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
      expect(find.byIcon(Icons.tune_rounded), findsNothing);
    });

    testWidgets('voice search button triggers callback', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(buildSubject(onVoiceSearchTap: () {
        tapped = true;
      }));
      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      expect(tapped, isTrue);
    });

    testWidgets('filter button triggers callback', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(buildSubject(onFilterTap: () {
        tapped = true;
      }));
      await tester.tap(find.byIcon(Icons.tune_rounded));
      expect(tapped, isTrue);
    });

    testWidgets('debounces onSearchChanged calls', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(buildSubject(
        config: SearchBarConfig(
          minCharsToSearch: 2,
          debounceDuration: const Duration(milliseconds: 100),
        ),
        onSearchChanged: calls.add,
      ));

      await tester.enterText(find.byType(TextField), 'flutter');
      // Wait for debounce
      await tester.pump(const Duration(milliseconds: 150));

      expect(calls.length, equals(1));
      expect(calls.last, equals('flutter'));
    });

    testWidgets('short queries below minCharsToSearch are not reported',
        (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(buildSubject(
        config: SearchBarConfig(
          minCharsToSearch: 3,
          debounceDuration: const Duration(milliseconds: 50),
        ),
        onSearchChanged: calls.add,
      ));

      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump(const Duration(milliseconds: 100));

      expect(calls, isEmpty);
    });

    testWidgets('emptying input invokes onClear', (tester) async {
      bool cleared = false;
      final controller = TextEditingController(text: 'something');
      await tester.pumpWidget(buildSubject(
        controller: controller,
        onClear: () => cleared = true,
      ));

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(cleared, isTrue);
    });

    testWidgets('clear button shows when text is present and clears input',
        (tester) async {
      bool cleared = false;
      final controller = TextEditingController(text: 'some query');
      await tester.pumpWidget(buildSubject(
        controller: controller,
        onClear: () => cleared = true,
      ));
      await tester.pump();

      expect(find.byIcon(Icons.clear_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pump();

      expect(controller.text, isEmpty);
      expect(cleared, isTrue);
    });

    testWidgets('loading indicator replaces clear button when loading',
        (tester) async {
      final controller = TextEditingController(text: 'query');
      await tester.pumpWidget(buildSubject(
        controller: controller,
        isLoading: true,
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.clear_rounded), findsNothing);
    });

    testWidgets('submitting text invokes onSearchSubmitted', (tester) async {
      String? submitted;
      await tester.pumpWidget(buildSubject(
        onSearchSubmitted: (v) => submitted = v,
      ));
      await tester.enterText(find.byType(TextField), 'breaking news');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(submitted, equals('breaking news'));
    });
  });

  group('ExpandableSearchBar', () {
    Widget buildSubject({
      List<String> recentSearches = const [],
      Function(String)? onSearchSubmitted,
      VoidCallback? onClearRecent,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ExpandableSearchBar(
            recentSearches: recentSearches,
            onSearchSubmitted: onSearchSubmitted,
            onClearRecent: onClearRecent,
          ),
        ),
      );
    }

    testWidgets('renders embedded search bar', (tester) async {
      await tester.pumpWidget(buildSubject());
      expect(find.byType(SearchBarWidget), findsOneWidget);
    });

    testWidgets('does not show recent searches when list is empty',
        (tester) async {
      await tester.pumpWidget(buildSubject(recentSearches: const []));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('Recent Searches'), findsNothing);
    });

    testWidgets('shows recent searches on focus when list is non-empty',
        (tester) async {
      await tester.pumpWidget(buildSubject(
        recentSearches: const ['election', 'cricket', 'tech'],
      ));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('Recent Searches'), findsOneWidget);
      expect(find.text('election'), findsOneWidget);
      expect(find.text('cricket'), findsOneWidget);
      expect(find.text('tech'), findsOneWidget);
    });

    testWidgets('selecting a recent search submits it', (tester) async {
      String? submitted;
      await tester.pumpWidget(buildSubject(
        recentSearches: const ['election'],
        onSearchSubmitted: (s) => submitted = s,
      ));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('election'));
      await tester.pumpAndSettle();
      expect(submitted, equals('election'));
    });

    testWidgets('clear recent button invokes callback', (tester) async {
      bool cleared = false;
      await tester.pumpWidget(buildSubject(
        recentSearches: const ['old query'],
        onClearRecent: () => cleared = true,
      ));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(cleared, isTrue);
    });

    testWidgets('shows at most 5 recent searches', (tester) async {
      await tester.pumpWidget(buildSubject(
        recentSearches: const ['a', 'b', 'c', 'd', 'e', 'f', 'g'],
      ));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(5));
    });
  });
}
