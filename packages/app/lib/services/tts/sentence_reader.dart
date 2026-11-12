import 'dart:async';

import 'package:flutter/foundation.dart';

import 'narration_segmenter.dart';

/// Reads one sentence aloud. Implementations: the on-device model ([OnDeviceOutput]) and the device's own voice
/// ([SystemVoiceOutput]).
abstract class SentenceOutput {
  /// 'on-device' or 'system' (shown to the listener and in logs).
  String get label;

  /// Load whatever is needed. May throw: the reader then moves to the fallback output.
  Future<void> init();

  /// Get ready for [text] ahead of time (the on-device model synthesises it now). Failures are ignored here and surface in [play].
  Future<void> prepare(String text);

  /// Speak [text]; completes when it finished, or when [stop] was called. Throws if it cannot be spoken.
  Future<void> play(String text);

  Future<void> pause();
  Future<void> resume();

  /// Stop speaking right now; a pending [play] completes.
  Future<void> stop();

  Future<void> setSpeed(double speed);
  Future<void> dispose();

  /// Seconds of work per second of audio, measured on this device (null when not applicable or not yet measured).
  /// Above 1.0 the voice cannot keep up with real time.
  double? get realTimeFactor;
}

enum ReaderState { idle, playing, paused, ended, error }

/// Reads a story sentence by sentence through a [SentenceOutput], with look-ahead preparation, pause/resume/stop, speed, a
/// reading position (the sentence index, kept across stop and pause), and automatic fallback to a second output when the first
/// fails to start, fails on a sentence, or is slower than real time.
class SentenceReader extends ChangeNotifier {
  SentenceReader({
    required SentenceOutput primary,
    SentenceOutput? fallback,
    NarrationSegmenter segmenter = const NarrationSegmenter(),
    this.lookAhead = 2,
    this.maxRealTimeFactor = 1.0,
    this.minSamplesForSpeedCheck = 2,
  })  : _out = primary,
        _fallback = fallback,
        _segmenter = segmenter;

  SentenceOutput _out;
  SentenceOutput? _fallback;
  final NarrationSegmenter _segmenter;
  final int lookAhead;
  final double maxRealTimeFactor;
  final int minSamplesForSpeedCheck;

  List<String> sentences = const [];
  int index = 0;
  ReaderState state = ReaderState.idle;
  String? error;
  double speed = 1.0;

  /// Why the reader left its first output (null while it has not).
  String? fallbackReason;
  String get outputLabel => _out.label;

  /// Seconds of work per second of audio of the current output (null when unknown); above 1.0 it cannot keep up.
  double? get realTimeFactor => _out.realTimeFactor;

  int _epoch = 0;
  bool _initialised = false;
  int _played = 0;
  Future<void> _prepareChain = Future.value();
  final Set<int> _prepared = {};

  /// Load a story's narration text. Keeps nothing of the previous story.
  void load(String text, {int startIndex = 0}) {
    stop();
    sentences = _segmenter.split(text);
    index = startIndex.clamp(0, sentences.isEmpty ? 0 : sentences.length - 1);
    _prepared.clear();
    state = ReaderState.idle;
    error = null;
    _played = 0;
    notifyListeners();
  }

  bool get isPlaying => state == ReaderState.playing;

  /// Fraction of sentences finished, 0..1 (for a progress bar).
  double get progress => sentences.isEmpty ? 0 : (state == ReaderState.ended ? 1 : index / sentences.length);

  /// Start (or restart from [index]) reading.
  Future<void> play() async {
    if (sentences.isEmpty) return;
    if (state == ReaderState.paused) return resume();
    if (state == ReaderState.playing) return;
    if (state == ReaderState.ended) index = 0;
    final epoch = ++_epoch;
    state = ReaderState.playing;
    error = null;
    notifyListeners();
    await _run(epoch);
  }

  Future<void> pause() async {
    if (state != ReaderState.playing) return;
    state = ReaderState.paused;
    notifyListeners();
    await _out.pause();
  }

  Future<void> resume() async {
    if (state != ReaderState.paused) return;
    state = ReaderState.playing;
    notifyListeners();
    await _out.resume();
  }

  /// Stop; the position is kept so [play] continues from the same sentence.
  Future<void> stop() async {
    _epoch++;
    final wasActive = state == ReaderState.playing || state == ReaderState.paused;
    if (wasActive) state = ReaderState.idle;
    await _out.stop();
    notifyListeners();
  }

  Future<void> seekToSentence(int i) async {
    if (sentences.isEmpty) return;
    final wasPlaying = state == ReaderState.playing || state == ReaderState.paused;
    await stop();
    index = i.clamp(0, sentences.length - 1);
    notifyListeners();
    if (wasPlaying) unawaited(play());
  }

  Future<void> next() => seekToSentence(index + 1);
  Future<void> previous() => seekToSentence(index - 1);

  Future<void> setSpeed(double s) async {
    speed = s;
    await _out.setSpeed(s);
    notifyListeners();
  }

  @override
  void dispose() {
    _epoch++;
    unawaited(_out.dispose());
    unawaited(_fallback?.dispose());
    super.dispose();
  }

  Future<void> _useFallback(String reason) async {
    final f = _fallback;
    if (f == null) throw StateError(reason);
    fallbackReason = reason;
    await _out.stop();
    unawaited(_out.dispose());
    _out = f;
    _fallback = null;
    _initialised = false;
    _prepared.clear();
    await _out.setSpeed(speed).catchError((_) {});
    notifyListeners();
  }

  void _prefetch(int from, int epoch) {
    for (var i = from; i < sentences.length && i <= from + lookAhead - 1; i++) {
      if (!_prepared.add(i)) continue;
      final text = sentences[i];
      final out = _out;
      _prepareChain = _prepareChain.then((_) async {
        if (epoch != _epoch || !identical(out, _out)) return;
        try {
          await out.prepare(text);
        } catch (_) {}
      });
    }
  }

  Future<void> _run(int epoch) async {
    try {
      while (epoch == _epoch && index < sentences.length) {
        if (!_initialised) {
          try {
            await _out.init();
            await _out.setSpeed(speed);
            _initialised = true;
          } catch (e) {
            await _useFallback('${_out.label} failed to start: $e');
            continue;
          }
        }
        _prefetch(index + 1, epoch);
        try {
          await _out.play(sentences[index]);
        } catch (e) {
          if (epoch != _epoch) return;
          await _useFallback('${_out.label} failed on a sentence: $e');
          continue; // same sentence again on the fallback
        }
        if (epoch != _epoch) return; // stopped or restarted while speaking: keep the position
        index++;
        _played++;
        notifyListeners();
        final rtf = _out.realTimeFactor;
        if (_fallback != null && rtf != null && _played >= minSamplesForSpeedCheck && rtf > maxRealTimeFactor) {
          await _useFallback('${_out.label} is slower than real time (${rtf.toStringAsFixed(2)}x)');
        }
      }
      if (epoch == _epoch) {
        state = ReaderState.ended;
        notifyListeners();
      }
    } catch (e) {
      if (epoch == _epoch) {
        error = e.toString();
        state = ReaderState.error;
        notifyListeners();
      }
    }
  }
}
