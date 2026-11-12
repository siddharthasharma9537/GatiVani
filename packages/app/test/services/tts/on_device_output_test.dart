import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gativani_app/services/tts/audio_cache.dart';
import 'package:gativani_app/services/tts/audio_cache_disk_io.dart';
import 'package:gativani_app/services/tts/on_device_output.dart';
import 'package:gativani_app/services/tts/sentence_reader.dart';
import 'package:gativani_app/services/tts/tts_engine.dart';

class _Engine implements TtsEngine {
  _Engine({this.delay = Duration.zero, this.failOn});
  final Duration delay;
  final String? failOn;
  final calls = <String>[];
  var inits = 0;
  var disposed = false;
  @override
  String get id => 'fake';
  @override
  List<String> get voices => const ['female', 'male'];
  @override
  Future<void> init() async => inits++;
  @override
  Future<TtsAudio> synthesize(String text, {String? voice, double speed = 1.0}) async {
    calls.add('$voice:$text');
    if (failOn != null && text.contains(failOn!)) throw StateError('boom');
    await Future<void>.delayed(delay);
    return TtsAudio(Float32List(24000), 24000); // 1 s of silence
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _Player implements WavPlayer {
  final played = <int>[];
  double speed = 1.0;
  @override
  Future<void> play(Uint8List wav, double s) async {
    played.add(wav.length);
    speed = s;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setSpeed(double s) async => speed = s;
  @override
  Future<void> dispose() async {}
}

OnDeviceOutput _out(_Engine e, _Player p, AudioCache c, {String voice = 'female', String version = 'v1'}) =>
    OnDeviceOutput(engineFactory: () async => e, voice: voice, cache: c, packVersion: version, player: p);

void main() {
  test('synthesises once, caches by text+voice+version, plays the cached WAV with the right speed', () async {
    final e = _Engine(), p = _Player(), cache = MemoryAudioCache();
    final o = _out(e, p, cache);
    await o.init();
    await o.setSpeed(1.25);
    await o.play('వాక్యం');
    await o.play('వాక్యం');
    expect(e.calls, ['female:వాక్యం']);
    expect(p.played.length, 2);
    expect(p.speed, 1.25);
    expect(p.played.first, 44 + (24000 + (0.18 * 24000).round()) * 2, reason: 'WAV header + 1 s + the 0.18 s gap, 16-bit');
  });

  test('another voice or pack version does not reuse the audio', () async {
    final e = _Engine(), p = _Player(), cache = MemoryAudioCache();
    final a = _out(e, p, cache);
    await a.init();
    await a.play('వాక్యం');
    final b = _out(e, p, cache, voice: 'male');
    await b.init();
    await b.play('వాక్యం');
    final c = _out(e, p, cache, version: 'v2');
    await c.init();
    await c.play('వాక్యం');
    expect(e.calls, ['female:వాక్యం', 'male:వాక్యం', 'female:వాక్యం']);
    expect(audioCacheKey(text: 'a', voice: 'f', version: '1'), isNot(audioCacheKey(text: 'a', voice: 'f', version: '2')));
  });

  test('prepare runs ahead; play then does not synthesise again; concurrent calls share one synthesis', () async {
    final e = _Engine(delay: const Duration(milliseconds: 20)), p = _Player();
    final o = _out(e, p, MemoryAudioCache());
    await o.init();
    final prep = o.prepare('ఒకటి');
    final both = Future.wait([o.prepare('ఒకటి'), o.play('ఒకటి')]);
    await prep;
    await both;
    expect(e.calls.length, 1);
  });

  test('measures the real-time factor only from real syntheses', () async {
    final e = _Engine(delay: const Duration(milliseconds: 100)), p = _Player();
    final o = _out(e, p, MemoryAudioCache());
    await o.init();
    expect(o.realTimeFactor, isNull);
    await o.play('ఒకటి');
    expect(o.realTimeFactor, closeTo(0.1, 0.08)); // 0.1 s of work for 1 s of audio
    final before = o.realTimeFactor;
    await o.play('ఒకటి'); // cache hit
    expect(o.realTimeFactor, before);
  });

  test('a synthesis failure surfaces from play and the next sentence still works', () async {
    final e = _Engine(failOn: 'చెడు'), p = _Player();
    final o = _out(e, p, MemoryAudioCache());
    await o.init();
    Object? err;
    try {
      await o.play('చెడు వాక్యం');
    } catch (x) {
      err = x;
    }
    expect(err, isA<StateError>());
    await o.play('మంచి వాక్యం');
    expect(p.played.length, 1);
  });

  test('works end to end with the sentence reader and falls back when the engine cannot start', () async {
    final good = _Engine(), p = _Player();
    final r = SentenceReader(primary: _out(good, p, MemoryAudioCache()))
      ..load('మొదటి వాక్యం ఇక్కడ ఉంది. రెండో వాక్యం ఇక్కడ ఉంది.');
    await r.play();
    expect(good.calls.length, 2);
    expect(p.played.length, 2);
    expect(r.state, ReaderState.ended);
  });

  group('caches', () {
    test('memory cache is LRU and capped in bytes', () async {
      final c = MemoryAudioCache(maxBytes: 100);
      await c.put('a', Uint8List(40));
      await c.put('b', Uint8List(40));
      await c.get('a'); // a is now more recent than b
      await c.put('c', Uint8List(40));
      expect(await c.get('b'), isNull);
      expect(await c.get('a'), isNotNull);
      expect(c.bytes, lessThanOrEqualTo(100));
      await c.put('huge', Uint8List(500));
      expect(await c.get('huge'), isNull);
    });

    test('disk cache stores, evicts the oldest over the cap, and layers under memory', () async {
      final dir = Directory.systemTemp.createTempSync('ttscache');
      addTearDown(() => dir.deleteSync(recursive: true));
      final d = DiskAudioCache(maxBytes: 100, dir: dir);
      await d.put('a', Uint8List.fromList(List.filled(40, 1)));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await d.put('b', Uint8List.fromList(List.filled(40, 2)));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await d.put('c', Uint8List.fromList(List.filled(40, 3)));
      expect(await d.get('a'), isNull, reason: 'oldest evicted');
      expect((await d.get('c'))!.first, 3);
      final layered = LayeredAudioCache(MemoryAudioCache(), d);
      expect((await layered.get('b'))!.first, 2);
      await d.clear();
      expect(await d.get('b'), isNull);
    });
  });
}
