import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gativani_app/features/paper/today/paper_models.dart';
import 'package:gativani_app/features/paper/today/paper_repository.dart';
import 'paper_fixture.dart';

http.Response jsonResponse(http.Request request, Object value,
        [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'story preserves all roles, continuation and narration independently of display',
      () {
    final json = storyJson();
    final story = PaperStory.fromJson(json);
    expect(story.narration, json['narration_text']);
    expect(story.narration, isNot(contains('పూల చిత్రం')));
    expect(story.narration.split('తోటలో చెట్లు').length - 1, 1);
    expect(story.items.map((i) => i.role), [
      'headline',
      'kicker',
      'deck',
      'byline',
      'subheading',
      'body',
      'caption',
      'side'
    ]);
    expect(story.pages, [1, 2]);
    expect(story.continuation.last['linked'], false);
    expect(PaperStory.fromJson(story.toJson()).toJson(), json);
  });
  test('graphic images accept only hosted HTTPS URLs', () {
    for (final url in [
      'http://localhost/crop',
      '/review-api/crop',
      'file:///tmp/crop',
      'https://user:pass@example.invalid/a'
    ]) {
      expect(
          PaperStory.fromJson({...storyJson(), 'headline_image_url': url})
              .imageUrl,
          isNull);
    }
    expect(
        PaperStory.fromJson({
          ...storyJson(),
          'headline_image_url': 'https://example.invalid/crop.jpg'
        }).imageUrl,
        isNotNull);
  });
  test('unsupported roles, empty pages and unknown section reject bad payloads',
      () {
    expect(
        () => PaperStory.fromJson({
              ...storyJson(),
              'items': [
                {'role': 'marker', 'text': 'pointer'}
              ]
            }),
        throwsFormatException);
    expect(() => PaperStory.fromJson({...storyJson(), 'page_numbers': []}),
        throwsFormatException);
    expect(() => PaperStory.fromJson({...storyJson(), 'section': 'unknown'}),
        throwsFormatException);
  });
  test('section order matches printed page labels', () {
    expect(paperSectionTitles, [
      'Front page',
      'Editorial news',
      'Business',
      'Cinema',
      'Champion (sports)',
      'Vasundhara',
      'Pratibha',
      'Chaduvu',
      'Regional',
      'National',
      'Back page',
      'General news'
    ]);
  });
  test('latest days uses latest published date and joins edition titles',
      () async {
    final calls = <Uri>[];
    final client = SupabaseClient('https://example.invalid', 'synthetic-key',
        httpClient: MockClient((r) async {
      calls.add(r.url);
      return jsonResponse(
          r,
          calls.length == 1
              ? [
                  {'source_date': '2026-11-13'}
                ]
              : [
                  {
                    'edition': 'TELANGANA',
                    'source_date': '2026-11-13',
                    'paper_editions': {'title': 'Telangana'}
                  }
                ],
          200);
    }));
    final result = await PaperRepository(client: client).latestDays();
    expect(
        calls.first.queryParameters['order'], startsWith('source_date.desc'));
    expect(calls.first.queryParameters['limit'], '1');
    expect(calls.last.queryParameters['source_date'], 'eq.2026-11-13');
    expect(result.single.title, 'Telangana');
    await client.dispose();
  });
  test('empty published days does not issue a second query', () async {
    var calls = 0;
    final client = SupabaseClient('https://example.invalid', 'synthetic-key',
        httpClient: MockClient((r) async {
      calls++;
      return jsonResponse(r, []);
    }));
    expect(await PaperRepository(client: client).latestDays(), isEmpty);
    expect(calls, 1);
    await client.dispose();
  });
  test('story list paginates past REST row limits and scopes both filters',
      () async {
    final calls = <Uri>[];
    final client = SupabaseClient('https://example.invalid', 'synthetic-key',
        httpClient: MockClient((r) async {
      calls.add(r.url);
      expect(r.url.queryParameters['edition'], 'eq.TELANGANA');
      expect(r.url.queryParameters['source_date'], 'eq.2026-11-13');
      final start = int.parse(r.url.queryParameters['offset'] ?? '0');
      return jsonResponse(
          r,
          List.generate(
              start == 0 ? 200 : 1, (i) => storyJson(id: 's${start + i}')),
          200);
    }));
    final result = await PaperRepository(client: client)
        .stories(const PaperDay('TELANGANA', '2026-11-13', 'Telangana'));
    expect(result.length, 201);
    expect(calls.length, 2);
    expect(calls.last.queryParameters['offset'], '200');
    await client.dispose();
  });
  test(
      'single story scopes identity and propagates errors without treating them as empty',
      () async {
    var status = 200;
    final client = SupabaseClient('https://example.invalid', 'synthetic-key',
        httpClient: MockClient((r) async {
      expect(r.url.queryParameters['source_id'], 'eq.p1-g0');
      expect(r.url.queryParameters['edition'], 'eq.TELANGANA');
      expect(r.url.queryParameters['source_date'], 'eq.2026-11-13');
      return jsonResponse(
          r,
          status == 200
              ? storyJson()
              : {'message': 'synthetic failure', 'code': 'TEST'},
          status);
    }));
    final repo = PaperRepository(client: client);
    expect((await repo.story('TELANGANA', '2026-11-13', 'p1-g0'))!.id, 'p1-g0');
    status = 500;
    await expectLater(repo.story('TELANGANA', '2026-11-13', 'p1-g0'),
        throwsA(isA<PostgrestException>()));
    await client.dispose();
  });
  test(
      'last view survives repository recreation with selected section and graphic',
      () async {
    const day = PaperDay('TELANGANA', '2026-11-13', 'Telangana');
    final view = PaperView(
        [day],
        day,
        [
          PaperStory.fromJson({...storyJson(), 'headline_is_graphic': true})
        ],
        'front');
    await PaperRepository().cacheView(view);
    expect((await PaperRepository().cachedView())!.toJson(), view.toJson());
  });
  test('invalid cached content does not block a fresh load', () async {
    SharedPreferences.setMockInitialValues(
        {'published_paper_view_v1': '{invalid'});
    expect(await PaperRepository().cachedView(), isNull);
  });
}
