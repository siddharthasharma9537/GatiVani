// Fake repository and fake player only: no network, no audio device, no Supabase, no Worker.
// Synthetic ids and neutral Telugu text.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gativani_app/features/paper/audio/paper_audio_models.dart';
import 'package:gativani_app/features/paper/audio/paper_audio_player.dart';
import 'package:gativani_app/features/paper/audio/paper_audio_repository.dart';
import 'package:gativani_app/features/paper/audio/paper_audio_ui.dart';
import 'package:gativani_app/services/settings_provider.dart';

Map<String, dynamic> row(int rank, String id, {String? key}) => {
      'edition': 'TELANGANA',
      'source_date': '2026-11-25',
      'story_id': id,
      'rank': rank,
      'page': rank,
      'headline': 'నమూనా వార్త $rank',
      'object_key': key ??
          'paper/TELANGANA/25-11-2026/${rank.toString().padLeft(3, '0')}_$id.m4a',
      'bucket': 'gativani-paper-audio',
      'content_type': 'audio/mp4',
      'bytes': 1000,
      'sha256': 'a' * 64,
      'duration_seconds': 60.0,
      'voice': 'tarun_te_narration',
      'model': 'bulbul:v4-flash',
      'characters': 100,
      'created_at': '2026-11-25T05:40:12Z',
    };

class FakeRepo extends PaperAudioRepository {
  FakeRepo({this.rows = const [], this.fail = false})
      : super(
            workerUrl: 'https://worker.example.test', accessToken: () => 'tok');
  List<Map<String, dynamic>> rows;
  bool fail;
  @override
  Future<PaperAudioPlaylist> playlist(String edition, String isoDate) async {
    if (fail) throw StateError('synthetic');
    return PaperAudioPlaylist(rows.map(PaperAudioStory.fromJson));
  }
}

class FakePlayer extends PaperAudioPlayer {
  PaperAudioState _s = PaperAudioState.idle;
  double _speed = 1;
  final log = <String>[];
  @override
  PaperAudioState get state => _s;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = const Duration(seconds: 60);
  @override
  double get speed => _speed;
  void set(PaperAudioState s) {
    _s = s;
    notifyListeners();
  }

  @override
  Future<void> load(PaperAudioStory story, {bool autoplay = true}) async {
    log.add('load ${story.storyId} autoplay=$autoplay');
    set(autoplay ? PaperAudioState.playing : PaperAudioState.paused);
  }

  @override
  Future<void> play() async {
    log.add('play');
    set(PaperAudioState.playing);
  }

  @override
  Future<void> pause() async {
    log.add('pause');
    set(PaperAudioState.paused);
  }

  @override
  Future<void> stop() async {
    log.add('stop');
    set(PaperAudioState.idle);
  }

  @override
  Future<void> seek(Duration to) async => log.add('seek ${to.inSeconds}');
  @override
  Future<void> setSpeed(double s) async {
    _speed = s;
    log.add('speed $s');
    notifyListeners();
  }
}

Widget host(Widget child) => ChangeNotifierProvider(
    create: (_) => SettingsProvider(), child: MaterialApp(home: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('models', () {
    test('rows parse and a URL or bad key is rejected', () {
      final s = PaperAudioStory.fromJson(row(1, 'sample_a'));
      expect(s.workerPath, 'TELANGANA/25-11-2026/001_sample_a.m4a');
      for (final bad in [
        'https://bucket.example/paper/x.m4a',
        '../paper/TELANGANA/25-11-2026/001_a.m4a',
        'paper/TELANGANA/25-11-2026/1_a.m4a',
      ]) {
        expect(() => PaperAudioStory.fromJson(row(1, 'a', key: bad)),
            throwsFormatException);
      }
      expect(() => PaperAudioStory.fromJson({...row(1, 'a'), 'rank': 0}),
          throwsFormatException);
    });
    test('playlist is ordered by rank, with next and previous', () {
      final list = PaperAudioPlaylist([row(3, 'c'), row(1, 'a'), row(2, 'b')]
          .map(PaperAudioStory.fromJson));
      expect(list.stories.map((s) => s.storyId), ['a', 'b', 'c']);
      expect(list.next('a')!.storyId, 'b');
      expect(list.next('c'), isNull);
      expect(list.previous('a'), isNull);
      expect(list.previous('c')!.storyId, 'b');
      expect(list.totalSeconds, 180);
    });
  });

  group('repository', () {
    test('queries the day by edition and date, ordered by rank', () async {
      final calls = <Uri>[];
      final client = SupabaseClient('https://example.invalid', 'synthetic-key',
          httpClient: MockClient((r) async {
        calls.add(r.url);
        return http.Response(jsonEncode([row(2, 'b'), row(1, 'a')]), 200,
            request: r,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }));
      final list = await PaperAudioRepository(
              client: client, workerUrl: 'https://w.example.test/')
          .playlist('TELANGANA', '2026-11-25');
      expect(list.stories.first.storyId, 'a');
      expect(calls.single.path, '/rest/v1/paper_story_audio');
      expect(calls.single.queryParameters['edition'], 'eq.TELANGANA');
      expect(calls.single.queryParameters['source_date'], 'eq.2026-11-25');
      expect(calls.single.queryParameters['order'], contains('rank'));
    });
    test('bytes come from the Worker with the bearer token only', () async {
      late http.Request seen;
      final repo = PaperAudioRepository(
        workerUrl: 'https://w.example.test/',
        accessToken: () => 'tok',
        httpClient: MockClient((r) async {
          seen = r;
          return http.Response.bytes(Uint8List.fromList([1, 2, 3]), 200);
        }),
      );
      final story = PaperAudioStory.fromJson(row(1, 'sample_a'));
      expect(await repo.fetchBytes(story), [1, 2, 3]);
      expect(seen.url.toString(),
          'https://w.example.test/paper-audio/TELANGANA/25-11-2026/001_sample_a.m4a');
      expect(seen.headers['Authorization'], 'Bearer tok');
    });
    test('refuses without a session and reports a 403 as unavailable',
        () async {
      final signedOut = PaperAudioRepository(
          workerUrl: 'https://w.example.test', accessToken: () => null);
      expect(() => signedOut.headers, throwsStateError);
      final denied = PaperAudioRepository(
        workerUrl: 'https://w.example.test',
        accessToken: () => 'tok',
        httpClient: MockClient((r) async => http.Response('', 403)),
      );
      expect(() => denied.fetchBytes(PaperAudioStory.fromJson(row(1, 'a'))),
          throwsA(isA<http.ClientException>()));
    });
    test('no Worker URL means the feature is off', () {
      expect(PaperAudioRepository().configured, isFalse);
    });
  });

  group('entry card', () {
    testWidgets('hidden for an empty list, an error and an unconfigured build',
        (t) async {
      for (final repo in [
        FakeRepo(),
        FakeRepo(fail: true),
        PaperAudioRepository(),
      ]) {
        await t.pumpWidget(host(PaperAudioEntry(
            edition: 'TELANGANA', date: '2026-11-25', repository: repo)));
        await t.pumpAndSettle();
        expect(find.byType(ListTile), findsNothing);
      }
    });
    testWidgets('shown with the count when there are stories', (t) async {
      await t.pumpWidget(host(PaperAudioEntry(
          edition: 'TELANGANA',
          date: '2026-11-25',
          repository: FakeRepo(rows: [row(1, 'a'), row(2, 'b')]))));
      await t.pumpAndSettle();
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.textContaining('2 stories'), findsOneWidget);
    });
  });

  group('panel and story screen', () {
    GoRouter router(FakePlayer player, FakeRepo repo, String id,
            {bool autoplay = false}) =>
        GoRouter(
            initialLocation:
                '/paper/today/audio/story?edition=TELANGANA&date=2026-11-25&id=$id${autoplay ? '&autoplay=1' : ''}',
            routes: [
              GoRoute(
                  path: '/paper/today/audio/story',
                  builder: (_, s) => PaperAudioStoryScreen(
                        edition: s.uri.queryParameters['edition']!,
                        date: s.uri.queryParameters['date']!,
                        id: s.uri.queryParameters['id']!,
                        autoplay: s.uri.queryParameters['autoplay'] == '1',
                        repository: repo,
                        playerFactory: (_) => player,
                      )),
            ]);
    Future<void> open(WidgetTester t, GoRouter r) async {
      await t.pumpWidget(ChangeNotifierProvider(
          create: (_) => SettingsProvider(),
          child: MaterialApp.router(routerConfig: r)));
      await t.pumpAndSettle();
    }

    final rows = [row(1, 'a'), row(2, 'b'), row(3, 'c')];

    testWidgets('loads the story paused, shows headline and position',
        (t) async {
      final player = FakePlayer();
      await open(t, router(player, FakeRepo(rows: rows), 'b'));
      expect(player.log, ['load b autoplay=false']);
      expect(find.text('నమూనా వార్త 2'), findsOneWidget);
      expect(find.text('Story 2 of 3'), findsOneWidget);
    });
    testWidgets('play, pause, speed and stop reach the player', (t) async {
      final player = FakePlayer();
      await open(t, router(player, FakeRepo(rows: rows), 'b'));
      await t.tap(find.byIcon(Icons.play_arrow_rounded));
      await t.pump();
      expect(player.state, PaperAudioState.playing);
      await t.tap(find.byIcon(Icons.pause_rounded));
      await t.pump();
      expect(player.state, PaperAudioState.paused);
      await t.tap(find.text('1.5×'));
      await t.pump();
      expect(player.speed, 1.5);
      await t.tap(find.byIcon(Icons.stop_rounded));
      await t.pump();
      expect(player.log, containsAll(['play', 'pause', 'speed 1.5', 'stop']));
    });
    testWidgets(
        'next story goes to the next rank and previous is disabled at the start',
        (t) async {
      final player = FakePlayer();
      await open(t, router(player, FakeRepo(rows: rows), 'a'));
      final prev = t.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.skip_previous_rounded));
      expect(prev.onPressed, isNull);
      await t.tap(find.byIcon(Icons.skip_next_rounded));
      await t.pumpAndSettle();
      expect(find.text('నమూనా వార్త 2'), findsOneWidget);
    });
    testWidgets('next is disabled on the last story', (t) async {
      await open(t, router(FakePlayer(), FakeRepo(rows: rows), 'c'));
      final next = t.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.skip_next_rounded));
      expect(next.onPressed, isNull);
    });
    testWidgets('finishing a story moves on to the next one, autoplaying',
        (t) async {
      final player = FakePlayer();
      await open(t, router(player, FakeRepo(rows: rows), 'a', autoplay: true));
      expect(player.log.first, 'load a autoplay=true');
      player.set(PaperAudioState.ended);
      await t.pumpAndSettle();
      expect(find.text('నమూనా వార్త 2'), findsOneWidget);
    });
    testWidgets(
        'a story that is not in the list, or a failed load, shows unavailable',
        (t) async {
      await open(t, router(FakePlayer(), FakeRepo(rows: rows), 'zzz'));
      expect(find.textContaining('not available'), findsOneWidget);
      await open(t, router(FakePlayer(), FakeRepo(fail: true), 'a'));
      expect(find.textContaining('not available'), findsOneWidget);
    });
    testWidgets('the seek bar seeks and the panel shows both clocks',
        (t) async {
      final player = FakePlayer()..position = const Duration(seconds: 5);
      await open(t, router(player, FakeRepo(rows: rows), 'a'));
      expect(find.text('0:05'), findsOneWidget);
      expect(find.text('1:00'), findsOneWidget);
      await t.tap(find.byType(Slider));
      await t.pump();
      expect(player.log.any((l) => l.startsWith('seek')), isTrue);
    });
  });
}
