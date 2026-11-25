import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gativani_app/features/paper/listen_panel.dart';
import 'package:gativani_app/services/tts/audio_cache.dart';
import 'package:gativani_app/services/tts/narration_controller.dart';
import 'package:gativani_app/services/tts/sentence_reader.dart';
import 'package:gativani_app/services/tts/voice_pack/pack_manifest.dart';
import 'package:gativani_app/services/tts/voice_pack/voice_pack_store.dart';

class TestPack implements VoicePackStore {
  @override
  VoicePackManifest get manifest => VoicePackManifest.indicTinyTelugu;
  @override
  Future<bool> isInstalled() async => false;
  @override
  Future<int> installedBytes() async => 0;
  @override
  Future<int?> freeBytes() async => 1000000000;
  @override
  Future<void> install(
          {void Function(int, int)? onProgress, CancelFlag? cancel}) async =>
      throw StateError('No downloads in tests');
  @override
  Future<void> delete() async {}
  @override
  Future<String> readText(String name) async =>
      throw StateError('No model in tests');
  @override
  Future<Map<String, String>> modelLocations() async => {};
}

class TestOutput implements SentenceOutput {
  final played = <String>[];
  Completer<void>? clip;
  bool paused = false;
  double speed = 1;
  @override
  String get label => 'synthetic';
  @override
  double? get realTimeFactor => null;
  @override
  Future<void> init() async {}
  @override
  Future<void> prepare(String text) async {}
  @override
  Future<void> play(String text) {
    played.add(text);
    return (clip = Completer<void>()).future;
  }

  void finish() {
    if (!(clip?.isCompleted ?? true)) clip!.complete();
  }

  @override
  Future<void> pause() async => paused = true;
  @override
  Future<void> resume() async => paused = false;
  @override
  Future<void> stop() async => finish();
  @override
  Future<void> setSpeed(double value) async => speed = value;
  @override
  Future<void> dispose() async => finish();
}

void main() {
  const narration =
      'తోటలో చెట్లు.\n\nతోటలో పూలు వికసించాయి.\n\nమొక్కలకు నీరు అవసరం.';
  late NarrationController controller;
  late List<TestOutput> outputs;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    outputs = [];
    controller = NarrationController.test(
      store: TestPack(),
      cache: MemoryAudioCache(),
      systemVoiceAvailable: () async => true,
      engineBuilder: (_) => throw StateError('No model in tests'),
      playerFactory: () => throw StateError('No real audio in tests'),
      systemOutputFactory: () {
        final output = TestOutput();
        outputs.add(output);
        return output;
      },
      idleRelease: Duration.zero,
    );
  });
  tearDown(() => controller.dispose());

  testWidgets(
      'reads entire narration in order with pause, resume, speed and voice changes',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListenPanel(narration: narration, controller: controller))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Listen'));
    await tester.pumpAndSettle();
    final first = outputs.single;
    expect(first.played, ['తోటలో చెట్లు.']);
    first.finish();
    await tester.pumpAndSettle();
    expect(first.played.last, 'తోటలో పూలు వికసించాయి.');
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(first.paused, true);
    await tester.tap(find.text('1.5×'));
    await tester.pumpAndSettle();
    expect(first.speed, 1.5);
    await tester.tap(find.text('Male'));
    await tester.pumpAndSettle();
    expect(controller.voice, 'male');
    expect(outputs.length, 2);
    final second = outputs.last;
    expect(second.played, isEmpty);
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(second.played, ['తోటలో పూలు వికసించాయి.']);
    expect(second.speed, 1.5);
    second.finish();
    await tester.pumpAndSettle();
    expect(second.played.last, 'మొక్కలకు నీరు అవసరం.');
    second.finish();
    await tester.pumpAndSettle();
    expect(find.text('Listen again'), findsOneWidget);
    expect(first.played.where((t) => t == 'తోటలో చెట్లు.').length, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
  testWidgets('Listen controls wrap at large text on a narrow device',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: ListenPanel(
                        narration: narration, controller: controller))))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
