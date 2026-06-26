import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import '../config/api_config.dart';
import '../models/newspaper_article.dart';

/// App-wide singleton: queue + audio, so playback survives navigation.
/// Bind UI with ListenableBuilder on PlaybackService.i.
class PlaybackService extends ChangeNotifier {
  PlaybackService._() {
    player.playerStateStream.listen((s) {
      // Auto-advance only on a GENUINE end-of-track. just_audio also emits
      // `completed` transiently while a new url loads and (on web) can emit it
      // with a zero position — those used to fire next() repeatedly and race a
      // whole playlist, leaving the audio stuck on one clip. So require: not
      // loading, not already advancing, and the clip actually played to its end.
      if (s.processingState == ProcessingState.completed &&
          !loading &&
          !_advancing) {
        final dur = player.duration;
        final pos = player.position;
        final reachedEnd = dur != null &&
            dur.inMilliseconds > 500 &&
            pos.inMilliseconds >= dur.inMilliseconds - 800;
        if (reachedEnd) {
          _saveProgress(completed: true); // mark this one finished → "Replay"
          _advancing = true;
          next().whenComplete(() => _advancing = false);
        }
      }
      notifyListeners();
    });
    player.positionStream.listen((pos) {
      notifyListeners();
      // Persist progress every ~10s while actually playing, so a tile can show
      // "Resume" with the right spot. Cheap upsert; full saves also on pause /
      // completion / track start.
      if (!brief &&
          player.playing &&
          (pos.inSeconds - _lastSaveSec).abs() >= 10) {
        _saveProgress();
      }
    });
  }
  static final PlaybackService i = PlaybackService._();

  final AudioPlayer player = AudioPlayer();
  final List<NewspaperArticle> queue = [];
  int index = -1;
  bool loading = false;
  String? error;
  // Guards re-entrant auto-advance. _playEpoch invalidates any in-flight
  // _playIndex so only the most recent one ever touches the player.
  bool _advancing = false;
  int _playEpoch = 0;
  // When true, this session narrates the short briefing (headline + lede) and
  // caches it separately. The lyrics view reads this to show matching text.
  bool brief = false;
  // Resume support: where to start the next track, and a throttle marker for
  // how recently progress was persisted.
  Duration? _pendingSeek;
  int _lastSaveSec = -999;

  NewspaperArticle? get current =>
      (index >= 0 && index < queue.length) ? queue[index] : null;
  bool get isPlaying => player.playing;
  double get speed => player.speed;
  Duration get position => player.position;
  // Only report a duration once a real track is loaded (avoids a stale/zero
  // duration making the lyric highlight race).
  Duration get duration =>
      player.processingState == ProcessingState.idle ? Duration.zero : (player.duration ?? Duration.zero);

  Future<void> playAll(List<NewspaperArticle> articles,
      {int start = 0, bool brief = false}) async {
    this.brief = brief;
    _advancing = false;
    queue
      ..clear()
      ..addAll(articles);
    await _playIndex(start);
  }

  /// [resumeAt] starts the article partway through (used by "Resume" on a
  /// recently-played tile); omit it (or pass zero) to start from the top.
  Future<void> playOne(NewspaperArticle a,
      {bool brief = false, Duration? resumeAt}) async {
    this.brief = brief;
    _advancing = false;
    _pendingSeek =
        (resumeAt != null && resumeAt > Duration.zero) ? resumeAt : null;
    final at = queue.indexWhere((x) => x.id == a.id);
    if (at >= 0) return _playIndex(at);
    queue.add(a);
    await _playIndex(queue.length - 1);
  }

  Future<void> next() async {
    if (index + 1 < queue.length) await _playIndex(index + 1);
  }

  Future<void> previous() async {
    if (index > 0) await _playIndex(index - 1);
  }

  void toggle() {
    if (player.playing) {
      player.pause();
      _saveProgress(); // remember the spot when paused
    } else {
      player.play();
    }
  }

  void seek(Duration d) => player.seek(d);
  void setSpeed(double s) => player.setSpeed(s);

  /// Upsert the current article's playback progress into recent_plays (one row
  /// per article). DB-backed so web and the future native apps share it without
  /// any platform-specific storage. [atSeconds] overrides the live position
  /// (used at track start, before a resume-seek has applied).
  void _saveProgress({bool completed = false, int? atSeconds}) {
    final a = current;
    if (a == null) return;
    // Briefing plays the short clip; don't let it set full-article progress —
    // just record it as recently played.
    final dur = brief ? 0 : duration.inSeconds;
    var pos = brief ? 0 : (atSeconds ?? position.inSeconds);
    final done = !brief && (completed || (dur > 0 && pos >= dur - 2));
    if (done) pos = dur;
    if (dur > 0) pos = pos.clamp(0, dur);
    _lastSaveSec = pos;
    http
        .post(
            Uri.parse('${ApiConfig.restUrl}/recent_plays?on_conflict=article_id'),
            headers: {
              ...ApiConfig.authHeaders,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates',
            },
            body: json.encode({
              'article_id': a.id,
              'title': a.title,
              'category': a.category,
              'page': a.page,
              'position_seconds': pos,
              'duration_seconds': dur,
              'completed': done,
              'played_at': DateTime.now().toUtc().toIso8601String(),
            }))
        .catchError((_) => http.Response('', 204));
  }

  Future<void> _playIndex(int idx) async {
    final epoch = ++_playEpoch; // any earlier in-flight _playIndex is now stale
    index = idx;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final a = queue[idx];
      // Briefing sessions narrate + cache the short version separately.
      var url = brief ? a.summaryAudioUrl : a.audioUrl;
      if (url == null || !url.startsWith('http')) {
        final r = await http
            .post(Uri.parse(ApiConfig.documentsSynthesizeUrl),
                headers: {
                  ...ApiConfig.authHeaders,
                  'Content-Type': 'application/json'
                },
                body: json.encode({
                  'text': brief ? a.briefingText : a.spokenText,
                  'language': 'te-IN',
                  'articleId': a.id,
                  if (brief) 'target': 'summary_audio_url',
                  if (a.suggestedSpeaker.isNotEmpty) 'speaker': a.suggestedSpeaker,
                  if (a.readingStyle.isNotEmpty) 'readingStyle': a.readingStyle,
                }))
            .timeout(const Duration(seconds: 150));
        if (epoch != _playEpoch) return; // superseded while synthesizing
        final data = json.decode(r.body) as Map<String, dynamic>;
        if (data['ok'] != true) throw Exception(data['message'] ?? 'TTS failed');
        url = data['audioUrl'] as String;
        if (brief) {
          a.summaryAudioUrl = url;
        } else {
          a.audioUrl = url;
        }
      }
      if (epoch != _playEpoch) return; // a newer track took over — don't fight it
      // setUrl completes when the clip is loaded (duration available). Clear the
      // loading state THEN start playback — play()'s future only completes at
      // end-of-track, so it must NOT be awaited.
      await player.setUrl(url);
      if (epoch != _playEpoch) return;
      // Resume partway through if requested (e.g. "Resume" on a tile).
      final startPos = _pendingSeek?.inSeconds ?? 0;
      if (_pendingSeek != null) player.seek(_pendingSeek!);
      _pendingSeek = null;
      _saveProgress(atSeconds: startPos); // bumps recently-played + records spot
      loading = false;
      notifyListeners();
      unawaited(player.play());
    } catch (e) {
      if (epoch != _playEpoch) return;
      error = e.toString();
      loading = false;
      notifyListeners();
    }
  }
}
