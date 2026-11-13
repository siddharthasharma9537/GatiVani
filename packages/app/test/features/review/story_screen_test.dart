import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gativani_app/features/review/paper_today_screen.dart';

http.Response story(String id) => http.Response(jsonEncode({
      'page': 1,
      'headline': 'Story $id',
      'graphic': null,
      'label': 'Page',
      'section': 'News',
      'items': <Object>[],
      'narration': '',
    }), 200);

void main() {
  testWidgets('query changes reload the story and late responses cannot replace its headline', (tester) async {
    final pending = <String, Completer<http.Response>>{};
    final client = MockClient((request) {
      final id = request.url.queryParameters['id']!;
      return (pending[id] = Completer<http.Response>()).future;
    });
    await http.runWithClient(() async {
      Widget screen(String id) => MaterialApp(home: StoryScreen(edition: 'Test', date: 'today', id: id));
      await tester.pumpWidget(screen('first'));
      await tester.pumpWidget(screen('second'));
      pending['second']!.complete(story('second'));
      await tester.pumpAndSettle();
      expect(find.text('Story second'), findsOneWidget);
      pending['first']!.complete(story('first'));
      await tester.pumpAndSettle();
      expect(find.text('Story second'), findsOneWidget);
      expect(find.text('Story first'), findsNothing);
      await tester.pumpWidget(screen('third'));
      expect(find.text('Story second'), findsNothing);
      pending['third']!.complete(story('third'));
      await tester.pumpAndSettle();
      expect(find.text('Story third'), findsOneWidget);
    }, () => client);
  });
}
