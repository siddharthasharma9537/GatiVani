import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:gativani_app/features/paper/today/paper_models.dart';
import 'package:gativani_app/features/paper/today/paper_repository.dart';
import 'package:gativani_app/features/paper/today/today_screen.dart';
import 'package:gativani_app/features/paper/today/story_screen.dart';
import 'package:gativani_app/services/settings_provider.dart';
import 'paper_fixture.dart';

const day = PaperDay('TELANGANA', '2026-11-13', 'Telangana');
const ap = PaperDay('ANDHRA-PRADESH', '2026-11-13', 'Andhra Pradesh');

class FakeRepository extends PaperRepository {
  List<PaperDay> days = [day, ap];
  List<PaperStory> data = [PaperStory.fromJson(storyJson(narration: ''))];
  PaperView? cached;
  bool fail = false;
  Future<PaperStory?> Function(String)? fetch;
  Completer<List<PaperDay>>? pending;
  int refreshes = 0;
  @override
  Future<List<PaperDay>> latestDays() async {
    refreshes++;
    if (fail) throw StateError('synthetic');
    return pending == null ? days : await pending!.future;
  }

  @override
  Future<List<PaperStory>> stories(PaperDay day) async {
    if (fail) throw StateError('synthetic');
    return data.where((s) => s.edition == day.edition).toList();
  }

  @override
  Future<PaperStory?> story(String edition, String date, String id) async {
    if (fail) throw StateError('synthetic');
    if (fetch != null) return fetch!(id);
    return data.where((s) => s.id == id).firstOrNull;
  }

  @override
  Future<PaperView?> cachedView() async => cached;
  @override
  Future<void> cacheView(PaperView view) async => cached = view;
}

Widget app(Widget child, {double scale = 1}) => ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child: MaterialApp(
          home: child,
          builder: (_, child) => MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: child!)),
    );

void main() {
  testWidgets(
      'loading, source, sections in paper order, and info without banner',
      (tester) async {
    final repo = FakeRepository()..pending = Completer<List<PaperDay>>();
    repo.data = [
      PaperStory.fromJson(storyJson(section: 'general', narration: '')),
      PaperStory.fromJson(storyJson(id: 'front', narration: ''))
    ];
    await tester.pumpWidget(app(TodayPaperScreen(repository: repo)));
    await tester.pump();
    expect(find.text('Loading paper…'), findsOneWidget);
    repo.pending!.complete([day]);
    await tester.pumpAndSettle();
    expect(find.text('Source: Eenadu e-paper, 2026-11-13'), findsOneWidget);
    expect(
        find
            .byType(ChoiceChip)
            .evaluate()
            .map((e) => ((e.widget as ChoiceChip).label as Text).data),
        ['Front page · 1', 'General news · 1']);
    expect(find.textContaining('AI proposal'), findsNothing);
    await tester.tap(find.byTooltip('About this text'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Telugu readings are AI proposals'),
        findsOneWidget);
  });
  testWidgets('empty, error and retry states', (tester) async {
    final repo = FakeRepository()..fail = true;
    await tester.pumpWidget(app(TodayPaperScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load the paper'), findsOneWidget);
    repo.fail = false;
    repo.days = [];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No paper has been published yet.'), findsOneWidget);
  });
  testWidgets('cached view and selected section remain readable on failure',
      (tester) async {
    final story =
        PaperStory.fromJson(storyJson(section: 'general', narration: ''));
    final repo = FakeRepository()
      ..cached = PaperView([day], day, [story], 'general')
      ..fail = true;
    await tester.pumpWidget(app(TodayPaperScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('తోటలో చెట్లు'), findsOneWidget);
    expect(find.textContaining('Showing saved paper.'), findsOneWidget);
    expect(
        (tester.widget(find.byType(ChoiceChip)) as ChoiceChip).selected, true);
  });
  testWidgets(
      'section changes are cached and edition switch loads independent stories',
      (tester) async {
    final repo = FakeRepository();
    repo.data.addAll([
      PaperStory.fromJson({
        ...storyJson(id: 'general', section: 'general', narration: ''),
        'headline': 'సాధారణ వార్త'
      }),
      PaperStory.fromJson({
        ...storyJson(id: 'ap', edition: ap.edition, narration: ''),
        'headline': 'మొక్కల వార్త'
      }),
    ]);
    await tester.pumpWidget(app(TodayPaperScreen(repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('General news · 1'));
    await tester.pumpAndSettle();
    expect(repo.cached!.section, 'general');
    expect(find.text('సాధారణ వార్త'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Andhra Pradesh').last);
    await tester.pumpAndSettle();
    expect(find.text('మొక్కల వార్త'), findsOneWidget);
    expect(find.text('సాధారణ వార్త'), findsNothing);
  });
  testWidgets('pull to refresh queries again', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(app(TodayPaperScreen(repository: repo)));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(repo.refreshes, 2);
  });
  testWidgets('graphic tile has neutral text and no invented image URL',
      (tester) async {
    final repo = FakeRepository()
      ..data = [
        PaperStory.fromJson({
          ...storyJson(narration: ''),
          'headline': '',
          'headline_is_graphic': true
        })
      ];
    await tester.pumpWidget(app(TodayPaperScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('headline: graphic'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
  testWidgets('list and story navigate using scoped identity', (tester) async {
    final repo = FakeRepository();
    final router = GoRouter(routes: [
      GoRoute(
          path: '/', builder: (_, __) => TodayPaperScreen(repository: repo)),
      GoRoute(
          path: '/paper/today/story',
          builder: (_, state) {
            expect(state.uri.queryParameters,
                {'edition': day.edition, 'date': day.date, 'id': 'p1-g0'});
            return PublishedStoryScreen(
                edition: day.edition,
                date: day.date,
                id: 'p1-g0',
                repository: repo);
          }),
    ]);
    await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('తోటలో చెట్లు'));
    await tester.pumpAndSettle();
    expect(find.byType(PublishedStoryScreen), findsOneWidget);
    expect(find.text('తోటలో చెట్లు'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
  testWidgets(
      'story roles keep captions and side notes apart and headline appears once',
      (tester) async {
    final story = PaperStory.fromJson(storyJson());
    await tester.pumpWidget(app(Scaffold(
        body: SingleChildScrollView(
            child: PublishedStoryText(story: story, lang: 'en')))));
    expect(find.text('తోటలో చెట్లు'), findsOneWidget);
    expect(find.text('Byline: రచయిత'), findsOneWidget);
    expect(find.text('పూల రంగులు'), findsOneWidget);
    expect(find.text('Photo captions'), findsOneWidget);
    expect(find.text('Also on this page'), findsOneWidget);
    expect(find.text('Continues on page 3 · Part not matched'), findsOneWidget);
    final captionContainer = find.ancestor(
        of: find.text('పూల చిత్రం'), matching: find.byType(Container));
    expect(captionContainer, findsWidgets);
  });
  testWidgets('story reload ignores late old identity responses',
      (tester) async {
    final pending = <String, Completer<PaperStory?>>{};
    final repo = FakeRepository()
      ..fetch = (id) => (pending[id] = Completer<PaperStory?>()).future;
    Widget screen(String id) => app(PublishedStoryScreen(
        edition: day.edition, date: day.date, id: id, repository: repo));
    await tester.pumpWidget(screen('one'));
    await tester.pump();
    await tester.pumpWidget(screen('two'));
    await tester.pump();
    pending['two']!.complete(PaperStory.fromJson(
        {...storyJson(id: 'two', narration: ''), 'headline': 'రెండో వార్త'}));
    await tester.pumpAndSettle();
    pending['one']!
        .complete(PaperStory.fromJson(storyJson(id: 'one', narration: '')));
    await tester.pumpAndSettle();
    expect(find.text('రెండో వార్త'), findsOneWidget);
    expect(find.text('తోటలో చెట్లు'), findsNothing);
  });
  testWidgets('story missing and failed with cached body states',
      (tester) async {
    final repo = FakeRepository()..data = [];
    await tester.pumpWidget(app(PublishedStoryScreen(
        edition: day.edition, date: day.date, id: 'gone', repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('This story is no longer available.'), findsOneWidget);
    repo.cached = PaperView(
        [day], day, [PaperStory.fromJson(storyJson(narration: ''))], 'front');
    repo.fail = true;
    await tester.pumpWidget(app(PublishedStoryScreen(
        edition: day.edition, date: day.date, id: 'p1-g0', repository: repo)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Showing saved paper.'), findsOneWidget);
    expect(find.text('తోటలో చెట్లు'), findsOneWidget);
  });
  testWidgets('large text on narrow phone keeps list and story readable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeRepository();
    await tester.pumpWidget(app(TodayPaperScreen(repository: repo), scale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(app(
        PublishedStoryScreen(
            edition: day.edition,
            date: day.date,
            id: 'p1-g0',
            repository: repo),
        scale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('తోటలో చెట్లు'), findsOneWidget);
  });
  testWidgets('Telugu language switches paper chrome and section labels',
      (tester) async {
    final settings = SettingsProvider()..setLanguage('te');
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: settings,
        child:
            MaterialApp(home: TodayPaperScreen(repository: FakeRepository()))));
    await tester.pumpAndSettle();
    expect(find.text('నేటి పత్రిక'), findsOneWidget);
    expect(find.text('మొదటి పేజీ · 1'), findsOneWidget);
    expect(find.text('మూలం: ఈనాడు ఈ పత్రిక, 2026-11-13'), findsOneWidget);
    expect(find.byTooltip('ఈ పాఠ్యం గురించి'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
}
