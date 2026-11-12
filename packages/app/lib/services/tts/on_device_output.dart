import 'dart:async';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import 'audio_cache.dart';
import 'sentence_reader.dart';
import 'tts_engine.dart';

/// Plays one WAV clip. Completes when the clip ended or [stop] was called.
abstract class WavPlayer {
  Future<void> play(Uint8List wav, double speed);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> setSpeed(double speed);
  Future<void> dispose();
}

/// [WavPlayer] on just_audio. The clip goes in as a data: URI (a sentence is ~0.5-1 MB), which every platform's player takes.
/// A NEW AudioPlayer is made for every clip: reusing one player and calling setAudioSource again left the web player on its first
/// clip, so the first sentence was heard over and over while the reader moved on. just_audio's own audio-session handling pauses
/// for a phone call or another app's audio and resumes afterwards.
class JustAudioWavPlayer implements WavPlayer {
  AudioPlayer? _p;
  Completer<void>? _done;
  double _speed = 1.0;

  @override
  Future<void> play(Uint8List wav, double speed) async {
    final old = _p;
    _p = null;
    await old?.dispose();
    final p = AudioPlayer(handleInterruptions: true);
    final done = Completer<void>();
    _p = p;
    _done = done;
    _speed = speed;
    final sub = p.processingStateStream.listen((s) {
      if (s == ProcessingState.completed && !done.isCompleted) done.complete();
    });
    try {
      await p.setAudioSource(AudioSource.uri(Uri.dataFromBytes(wav, mimeType: 'audio/wav')));
      await p.setSpeed(_speed);
      if (!done.isCompleted) unawaited(p.play());
      await done.future;
    } finally {
      await sub.cancel();
      if (identical(_p, p)) _p = null;
      await p.dispose();
    }
  }

  @override
  Future<void> pause() async => _p?.pause();
  @override
  Future<void> resume() async {
    final p = _p;
    if (p != null) unawaited(p.play());
  }

  @override
  Future<void> stop() async {
    final d = _done;
    if (d != null && !d.isCompleted) d.complete();
    await _p?.stop();
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _p?.setSpeed(speed);
  }

  @override
  Future<void> dispose() => stop();
}

/// The on-device model as a [SentenceOutput]: synthesises each sentence once (at 1.0x), caches the WAV by text + voice +
/// pack version, hands it to a [WavPlayer], and measures the real-time factor so the reader can fall back when this phone
/// is too slow. One synthesis runs at a time.
class OnDeviceOutput implements SentenceOutput {
  OnDeviceOutput({
    required this.engineFactory,
    required this.voice,
    required this.cache,
    required this.packVersion,
    required this.player,
    this.gapSeconds = 0.18,
  });

  final Future<TtsEngine> Function() engineFactory;
  final String voice;
  final AudioCache cache;
  final String packVersion;
  final WavPlayer player;
  final double gapSeconds;

  TtsEngine? _engine;
  Future<void> _chain = Future.value();
  final Map<String, Future<Uint8List>> _inFlight = {};
  double? _rtf;
  double _speed = 1.0;

  @override
  String get label => 'on-device';

  @override
  double? get realTimeFactor => _rtf;

  @override
  Future<void> init() async {
    _engine ??= await engineFactory();
    await _engine!.init();
  }

  Future<Uint8List> _wav(String text) {
    final key = audioCacheKey(text: text, voice: voice, version: packVersion);
    return _inFlight[key] ??= () async {
      try {
        final hit = await cache.get(key);
        if (hit != null) return hit;
        final run = _chain.then((_) async {
          final sw = Stopwatch()..start();
          final audio = await _engine!.synthesize(text, voice: voice);
          sw.stop();
          if (audio.seconds > 0) {
            final x = (sw.elapsedMicroseconds / 1e6) / audio.seconds;
            _rtf = _rtf == null ? x : 0.5 * _rtf! + 0.5 * x; // moving average over recent sentences
          }
          final padded = Float32List(audio.samples.length + (gapSeconds * audio.sampleRate).round())
            ..setRange(0, audio.samples.length, audio.samples);
          return TtsAudio(padded, audio.sampleRate).toWav();
        });
        _chain = run.then((_) {}, onError: (_) {});
        final wav = await run;
        await cache.put(key, wav);
        return wav;
      } finally {
        // keep only the cache, not the bytes, once finished
        // (a block body: returning the removed future from the callback would make this timer adopt its error)
        unawaited(Future<void>.delayed(Duration.zero, () {
          _inFlight.remove(key);
        }));
      }
    }();
  }

  @override
  Future<void> prepare(String text) async {
    await _wav(text);
  }

  @override
  Future<void> play(String text) async {
    final wav = await _wav(text);
    await player.play(wav, _speed);
  }

  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> resume() => player.resume();
  @override
  Future<void> stop() => player.stop();

  @override
  Future<void> setSpeed(double s) {
    _speed = s;
    return player.setSpeed(s);
  }

  @override
  Future<void> dispose() async {
    await player.dispose();
    await _engine?.dispose();
    _engine = null;
  }
}
