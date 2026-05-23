/// Widget tests for SourceFilter and HorizontalSourceFilter components
/// Covers selection toggling, multi-select vs single-select, select-all/deselect-all,
/// and horizontal scrolling variant.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gativani/design/components/source_filter.dart';

void main() {
  List<NewsSourceModel> buildSources({int count = 3, int selectedIndex = -1}) {
    return List.generate(
      count,
      (i) => NewsSourceModel(
        id: 'source_$i',
        name: 'Source $i',
        isSelected: i == selectedIndex,
      ),
    );
  }

  group('NewsSourceModel', () {
    test('default isSelected is false', () {
      final source = NewsSourceModel(id: 'a', name: 'A');
      expect(source.isSelected, isFalse);
    });

    test('copyWith preserves identity fields and toggles selection', () {
      final source = NewsSourceModel(id: 'a', name: 'A');
      final copy = source.copyWith(isSelected: true);
      expect(copy.id, equals('a'));
      expect(copy.name, equals('A'));
      expect(copy.isSelected, isTrue);
    });

    test('copyWith without arguments preserves selection', () {
      final source = NewsSourceModel(id: 'a', name: 'A', isSelected: true);
      final copy = source.copyWith();
      expect(copy.isSelected, isTrue);
    });
  });

  group('SourceFilter Widget', () {
    Widget buildSubject({
      List<NewsSourceModel>? sources,
      Function(List<String>)? onChanged,
      bool allowMultiSelect = true,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SourceFilter(
            sources: sources ?? buildSources(),
            onSourcesChanged: onChanged ?? (_) {},
            allowMultiSelect: allowMultiSelect,
          ),
        ),
      );
    }

    testWidgets('renders all source chips', (tester) async {
      await tester.pumpWidget(buildSubject(sources: buildSources(count: 4)));
      for (int i = 0; i < 4; i++) {
        expect(find.text('Source $i'), findsOneWidget);
      }
    });

    testWidgets('renders header with selected count', (tester) async {
      await tester.pumpWidget(buildSubject(sources: buildSources(count: 3)));
      expect(find.text('News Sources'), findsOneWidget);
      expect(find.text('Selected: 0 / 3'), findsOneWidget);
    });

    testWidgets('selecting a source updates count and notifies parent',
        (tester) async {
      List<String> reportedIds = [];
      await tester.pumpWidget(buildSubject(
        sources: buildSources(count: 3),
        onChanged: (ids) => reportedIds = ids,
      ));

      await tester.tap(find.text('Source 0'));
      await tester.pumpAndSettle();

      expect(reportedIds, contains('source_0'));
      expect(find.text('Selected: 1 / 3'), findsOneWidget);
    });

    testWidgets('multi-select toggles independently', (tester) async {
      List<String> reportedIds = [];
      await tester.pumpWidget(buildSubject(
        sources: buildSources(count: 3),
        onChanged: (ids) => reportedIds = ids,
      ));

      await tester.tap(find.text('Source 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Source 2'));
      await tester.pumpAndSettle();

      expect(reportedIds.length, equals(2));
      expect(reportedIds, containsAll(['source_0', 'source_2']));
    });

    testWidgets('single-select mode replaces selection on tap',
        (tester) async {
      List<String> reportedIds = [];
      await tester.pumpWidget(buildSubject(
        sources: buildSources(count: 3),
        onChanged: (ids) => reportedIds = ids,
        allowMultiSelect: false,
      ));

      await tester.tap(find.text('Source 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Source 2'));
      await tester.pumpAndSettle();

      expect(reportedIds.length, equals(1));
      expect(reportedIds.first, equals('source_2'));
    });

    testWidgets('select all selects every source via popup menu',
        (tester) async {
      List<String> reportedIds = [];
      await tester.pumpWidget(buildSubject(
        sources: buildSources(count: 3),
        onChanged: (ids) => reportedIds = ids,
      ));

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select All'));
      await tester.pumpAndSettle();

      expect(reportedIds.length, equals(3));
      expect(find.text('Selected: 3 / 3'), findsOneWidget);
    });

    testWidgets('deselect all clears selection via popup menu',
        (tester) async {
      List<String> reportedIds = ['placeholder'];
      await tester.pumpWidget(buildSubject(
        sources: buildSources(count: 3, selectedIndex: 0),
        onChanged: (ids) => reportedIds = ids,
      ));

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deselect All'));
      await tester.pumpAndSettle();

      expect(reportedIds, isEmpty);
      expect(find.text('Selected: 0 / 3'), findsOneWidget);
    });

    testWidgets('initial selection is reflected in counter', (tester) async {
      await tester.pumpWidget(buildSubject(
        sources: buildSources(count: 4, selectedIndex: 1),
      ));
      expect(find.text('Selected: 1 / 4'), findsOneWidget);
    });

    testWidgets('selecting then deselecting same source clears it',
        (tester) async {
      List<String> reportedIds = [];
      await tester.pumpWidget(buildSubject(
        sources: buildSources(count: 2),
        onChanged: (ids) => reportedIds = ids,
      ));

      await tester.tap(find.text('Source 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Source 0'));
      await tester.pumpAndSettle();

      expect(reportedIds, isEmpty);
    });

    testWidgets('handles empty source list gracefully', (tester) async {
      await tester.pumpWidget(buildSubject(sources: []));
      expect(find.text('Selected: 0 / 0'), findsOneWidget);
    });
  });

  group('HorizontalSourceFilter Widget', () {
    Widget buildSubject({
      List<NewsSourceModel>? sources,
      Function(List<String>)? onChanged,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 80,
            child: HorizontalSourceFilter(
              sources: sources ?? buildSources(count: 5),
              onSourcesChanged: onChanged ?? (_) {},
            ),
          ),
        ),
      );
    }

    testWidgets('renders horizontal scroll view', (tester) async {
      await tester.pumpWidget(buildSubject());
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('renders all source chips horizontally', (tester) async {
      await tester.pumpWidget(buildSubject(sources: buildSources(count: 3)));
      expect(find.text('Source 0'), findsOneWidget);
      expect(find.text('Source 1'), findsOneWidget);
      expect(find.text('Source 2'), findsOneWidget);
    });

    testWidgets('tapping a chip toggles and notifies parent', (tester) async {
      List<String> reportedIds = [];
      await tester.pumpWidget(buildSubject(
        sources: buildSources(count: 3),
        onChanged: (ids) => reportedIds = ids,
      ));
      await tester.tap(find.text('Source 1'));
      await tester.pumpAndSettle();
      expect(reportedIds, contains('source_1'));
    });

    testWidgets('multi-select is allowed in horizontal variant',
        (tester) async {
      List<String> reportedIds = [];
      await tester.pumpWidget(buildSubject(
        sources: buildSources(count: 4),
        onChanged: (ids) => reportedIds = ids,
      ));

      await tester.tap(find.text('Source 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Source 2'));
      await tester.pumpAndSettle();

      expect(reportedIds, containsAll(['source_0', 'source_2']));
    });

    testWidgets('handles empty list gracefully', (tester) async {
      await tester.pumpWidget(buildSubject(sources: []));
      expect(tester.takeException(), isNull);
    });
  });
}
