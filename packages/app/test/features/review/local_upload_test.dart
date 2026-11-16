import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gativani_app/features/review/paper_today_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('PDF upload, status polling and article loading use only the local API', (tester) async {
    const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
    final bytes = Uint8List.fromList(utf8.encode('%PDF-neutral-test'));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async => [
      {'name': 'garden_16-11-2026.pdf', 'size': bytes.length, 'bytes': bytes, 'path': '/tmp/garden.pdf'},
    ]);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    var uploaded = false;
    final oldEdition = Completer<http.Response>();
    final paths = <String>[];
    final job = {
      'id': 'test-job', 'edition': 'LOCAL-test', 'date': '16-11-2026', 'filename': 'garden_16-11-2026.pdf',
      'status': 'ready', 'stage': 'Ready', 'donePages': 1, 'totalPages': 1, 'articles': 1,
    };
    final client = MockClient((request) async {
      paths.add(request.url.path);
      expect(request.url.host, Uri.base.host);
      Object response;
      var code = 200;
      switch (request.url.path) {
        case '/review-api/editions':
          response = uploaded ? [{'edition': 'LOCAL-test', 'date': '16-11-2026', 'pages': 1}] : [{'edition': 'old', 'date': '12-11-2026', 'pages': 1}];
        case '/review-api/upload':
          expect(request.method, 'POST');
          expect(request.bodyBytes, bytes);
          uploaded = true;
          code = 202;
          response = {...job, 'status': 'extracting'};
        case '/review-api/upload-job':
          response = job;
        case '/review-api/paper':
          if (request.url.queryParameters['edition'] == 'old') return oldEdition.future;
          response = {'sections': [{'name': 'News', 'title': 'News', 'stories': [
            {'id': 'p1-g0', 'page': 1, 'headline': 'A garden visit', 'preview': 'Trees and flowers.', 'words': 3, 'graphic': false},
          ]}]};
        default:
          throw StateError('Unexpected request: ${request.url.path}');
      }
      return http.Response(jsonEncode(response), code);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: PaperTodayScreen()));
      await tester.pump();
      await tester.tap(find.text('Upload PDF locally'));
      await tester.pumpAndSettle();
      expect(find.text('A garden visit'), findsOneWidget);
      expect(find.text('Pages 1/1 · 1 articles'), findsOneWidget);
      expect(paths, containsAllInOrder(['/review-api/upload', '/review-api/upload-job', '/review-api/editions', '/review-api/paper']));
      oldEdition.complete(http.Response(jsonEncode({'sections': []}), 200));
      await tester.pumpAndSettle();
      expect(find.text('A garden visit'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  });
}
