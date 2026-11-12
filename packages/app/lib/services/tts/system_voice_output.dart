import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'sentence_reader.dart';

/// The device's own speech engine (Android Google Speech Services / iOS AVSpeechSynthesizer / the browser's speechSynthesis),
/// used when the on-device model is not installed or fails. Telugu depends on the voices the device has; [init] throws when
/// there is no Telugu voice, so the reader can report it instead of speaking nothing.
///
/// Android's engine cannot pause: pause stops speaking and resume speaks the current sentence again from its start.
class SystemVoiceOutput implements SentenceOutput {
  SystemVoiceOutput({FlutterTts? tts, this.language = 'te-IN'}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  final String language;
  double _speed = 1.0;
  bool _paused = false;
  bool _stopped = false;
  Completer<void>? _resume;
  Completer<void>? _spoken;

  @override
  String get label => 'system';

  @override
  double? get realTimeFactor => null;

  @override
  Future<void> init() async {
    final ok = await _tts.isLanguageAvailable(language);
    if (ok != true && ok != 1) throw StateError('this device has no $language voice');
    await _tts.setLanguage(language);
    await _tts.awaitSpeakCompletion(true);
    _tts.setCompletionHandler(() => _spoken?.complete());
    _tts.setCancelHandler(() => _spoken?.complete());
    _tts.setErrorHandler((m) => _spoken?.completeError(StateError('system voice error: $m')));
    await _tts.setSpeechRate(_rate(_speed));
  }

  // flutter_tts rate is 0..1 with ~0.5 as normal speed on Android and iOS; map 0.5x..2x onto it.
  double _rate(double s) => (0.5 * s).clamp(0.1, 1.0);

  @override
  Future<void> prepare(String text) async {}

  @override
  Future<void> play(String text) async {
    _stopped = false;
    while (!_stopped) {
      _spoken = Completer<void>();
      await _tts.speak(text);
      await _spoken!.future.timeout(const Duration(seconds: 120), onTimeout: () {});
      if (_stopped) return;
      if (!_paused) return;
      // paused by stopping the engine: wait, then speak the sentence again
      _resume = Completer<void>();
      await _resume!.future;
    }
  }

  @override
  Future<void> pause() async {
    _paused = true;
    await _tts.stop();
  }

  @override
  Future<void> resume() async {
    _paused = false;
    _resume?.complete();
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    _paused = false;
    await _tts.stop();
    final r = _resume;
    if (r != null && !r.isCompleted) r.complete();
    final s = _spoken;
    if (s != null && !s.isCompleted) s.complete();
  }

  @override
  Future<void> setSpeed(double s) async {
    _speed = s;
    await _tts.setSpeechRate(_rate(s));
  }

  @override
  Future<void> dispose() => stop();
}
