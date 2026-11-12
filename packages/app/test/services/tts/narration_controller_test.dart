import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gativani_app/services/tts/audio_cache.dart';
import 'package:gativani_app/services/tts/narration_controller.dart';
import 'package:gativani_app/services/tts/on_device_output.dart';
import 'package:gativani_app/services/tts/sentence_reader.dart';
import 'package:gativani_app/services/tts/tts_engine.dart';
import 'package:gativani_app/services/tts/voice_pack/pack_manifest.dart';
import 'package:gativani_app/services/tts/voice_pack/voice_pack_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store implements VoicePackStore {
  bool installed = false;
  Object? failWith;
  var deleted = false;
  @override
  VoicePackManifest get manifest => VoicePackManifest.indicTinyTelugu;
  @override
  Future<bool> isInstalled() async => installed;
  @override
  Future<int> installedBytes() async => installed ? manifest.totalBytes : 0;
  @override
  Future<int?> freeBytes() async => 1 << 40;
  @override
  Future<void> install({void Function(int done, int total)? onProgress, CancelFlag? cancel}) async {
    onProgress?.call(10, manifest.totalBytes);
    if (failWith != null) throw failWith!;
    if (cancel?.cancelled ?? false) throw DownloadCancelled();
    onProgress?.call(manifest.totalBytes, manifest.totalBytes);
    installed = true;
  }

  @override
  Future<void> delete() async {
    installed = false;
    deleted = true;
  }

  @override
  Future<String> readText(String name) async => '{}';
  @override
  Future<Map<String, String>> modelLocations() async => {};
}

class _Engine implements TtsEngine {
  var disposed = false;
  @override
  String get id => 'fake';
  @override
  List<String> get voices => const ['female', 'male'];
  @override
  Future<void> init() async {}
  @override
  Future<TtsAudio> synthesize(String text, {String? voice, double speed = 1.0}) async => TtsAudio(Float32List(2400), 24000);
  @override
  Future<void> dispose() async => disposed = true;
}

class _Player implements WavPlayer {
  @override
  Future<void> play(Uint8List wav, double speed) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> dispose() async {}
}

class _System implements SentenceOutput {
  @override
  String get label => 'system';
  @override
  double? get realTimeFactor => null;
  @override
  Future<void> init() async {}
  @override
  Future<void> prepare(String text) async {}
  @override
  Future<void> play(String text) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> dispose() async {}
}

const _text = 'మొదటి వాక్యం ఇక్కడ ఉంది. రెండో వాక్యం ఇక్కడ ఉంది.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  late _Engine engine;
  var builds = 0;

  NarrationController make({bool system = true, Duration idle = const Duration(milliseconds: 50)}) {
    SharedPreferences.setMockInitialValues({});
    store = _Store();
    engine = _Engine();
    builds = 0;
    return NarrationController.test(
      store: store,
      cache: MemoryAudioCache(),
      systemVoiceAvailable: () async => system,
      engineBuilder: (_) async {
        builds++;
        return engine;
      },
      playerFactory: _Player.new,
      systemOutputFactory: _System.new,
      idleRelease: idle,
    );
  }

  test('auto: on-device when the pack is installed, device voice when not, cloud when neither', () async {
    final c = make();
    await c.load();
    expect(c.packStatus, PackStatus.notInstalled);
    expect((await c.readerFor(_text))!.outputLabel, 'system');
    store.installed = true;
    await c.load();
    expect(c.packStatus, PackStatus.installed);
    expect((await c.readerFor(_text))!.outputLabel, 'on-device');

    final none = make(system: false);
    await none.load();
    expect(await none.readerFor(_text), isNull);
  });

  test('explicit choices: cloud -> null, system -> device voice, on-device without pack -> device voice', () async {
    final c = make();
    await c.load();
    await c.setEngine(NarrationEngine.cloud);
    expect(await c.readerFor(_text), isNull);
    await c.setEngine(NarrationEngine.system);
    expect((await c.readerFor(_text))!.outputLabel, 'system');
    await c.setEngine(NarrationEngine.onDevice);
    expect((await c.readerFor(_text))!.outputLabel, 'system');
    final noSystem = make(system: false);
    await noSystem.load();
    await noSystem.setEngine(NarrationEngine.system);
    expect(await noSystem.readerFor(_text), isNull);
  });

  test('engine and voice choices persist', () async {
    final c = make();
    await c.setEngine(NarrationEngine.onDevice);
    await c.setVoice('male');
    final again = NarrationController.test(
      store: store,
      cache: MemoryAudioCache(),
      systemVoiceAvailable: () async => true,
      engineBuilder: (_) async => engine,
      playerFactory: _Player.new,
      systemOutputFactory: _System.new,
    );
    await again.load();
    expect(again.engine, NarrationEngine.onDevice);
    expect(again.voice, 'male');
  });

  test('the model loads on the first sentence, is shared, and is released after the last reader closes', () async {
    final c = make();
    store.installed = true;
    await c.load();
    final r1 = (await c.readerFor(_text))!;
    final r2 = (await c.readerFor(_text))!;
    expect(builds, 0, reason: 'lazy: nothing loaded before a sentence is read');
    await r1.play();
    await r2.play();
    expect(builds, 1, reason: 'shared between readers');
    expect(c.engineResident, true);
    r1.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(c.engineResident, true, reason: 'one reader still open');
    r2.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(c.engineResident, false);
    expect(engine.disposed, true);
  });

  test('install: progress, success, failure, cancel, delete', () async {
    final c = make();
    await c.load();
    final states = <PackStatus>[];
    c.addListener(() => states.add(c.packStatus));
    await c.installPack();
    expect(c.packStatus, PackStatus.installed);
    expect(states, contains(PackStatus.installing));
    expect(c.packDone, c.packTotal);

    await c.deletePack();
    expect(c.packStatus, PackStatus.notInstalled);
    expect(store.deleted, true);

    store.failWith = InsufficientSpaceException(200 << 20, 10 << 20);
    await c.installPack();
    expect(c.packStatus, PackStatus.failed);
    expect(c.packError, contains('Not enough storage'));

    store.failWith = null;
    final f = c.installPack();
    c.cancelInstall();
    await f;
    expect(c.packStatus, PackStatus.installed, reason: 'a cancel that arrives after the last chunk does not break the install');
  });
}
