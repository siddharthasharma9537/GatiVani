import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'paper_audio_models.dart';
import 'paper_audio_repository.dart';

enum PaperAudioState { idle, loading, playing, paused, ended, error }

/// What the panel needs from a player; tests supply a fake.
abstract class PaperAudioPlayer extends ChangeNotifier {
  PaperAudioState get state;
  Duration get position;
  Duration get duration;
  double get speed;
  Future<void> load(PaperAudioStory story, {bool autoplay = true});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration to);
  Future<void> setSpeed(double speed);
}

/// just_audio over the Worker. Native: the bearer header goes with the request. Web: an audio
/// element cannot send headers, so the bytes are fetched with the token and played from a data URI.
class JustAudioPaperPlayer extends PaperAudioPlayer {
  JustAudioPaperPlayer(this._repo, {AudioPlayer? player})
      : _p = player ?? AudioPlayer() {
    _subs = [
      _p.playerStateStream.listen(_onState),
      _p.positionStream.listen((d) {
        _position = d;
        notifyListeners();
      }),
      _p.durationStream.listen((d) {
        _duration = d ?? Duration.zero;
        notifyListeners();
      }),
    ];
  }

  final PaperAudioRepository _repo;
  final AudioPlayer _p;
  late final List<StreamSubscription<Object?>> _subs;
  PaperAudioState _state = PaperAudioState.idle;
  Duration _position = Duration.zero, _duration = Duration.zero;
  double _speed = 1.0;
  int _generation = 0;

  @override
  PaperAudioState get state => _state;
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  double get speed => _speed;

  void _set(PaperAudioState s) {
    _state = s;
    notifyListeners();
  }

  void _onState(PlayerState s) {
    if (_state == PaperAudioState.error || _state == PaperAudioState.loading) {
      return;
    }
    if (s.processingState == ProcessingState.completed) {
      _set(PaperAudioState.ended);
    } else if (s.processingState == ProcessingState.ready) {
      _set(s.playing ? PaperAudioState.playing : PaperAudioState.paused);
    }
  }

  @override
  Future<void> load(PaperAudioStory story, {bool autoplay = true}) async {
    final mine = ++_generation;
    _position = Duration.zero;
    _set(PaperAudioState.loading);
    try {
      if (kIsWeb) {
        final bytes = await _repo.fetchBytes(story);
        if (mine != _generation) return;
        await _p.setUrl('data:audio/mp4;base64,${base64Encode(bytes)}');
      } else {
        await _p.setUrl(_repo.uriFor(story).toString(), headers: _repo.headers);
      }
      if (mine != _generation) return;
      await _p.setSpeed(_speed);
      _set(PaperAudioState.paused);
      if (autoplay) await play();
    } catch (_) {
      if (mine == _generation) _set(PaperAudioState.error);
    }
  }

  @override
  Future<void> play() async {
    if (_state == PaperAudioState.ended) await _p.seek(Duration.zero);
    _set(PaperAudioState.playing);
    unawaited(_p.play());
  }

  @override
  Future<void> pause() async {
    await _p.pause();
    _set(PaperAudioState.paused);
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _p.stop();
    _position = Duration.zero;
    _set(PaperAudioState.idle);
  }

  @override
  Future<void> seek(Duration to) => _p.seek(to);

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _p.setSpeed(speed);
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    for (final s in _subs) {
      s.cancel();
    }
    _p.dispose();
    super.dispose();
  }
}
