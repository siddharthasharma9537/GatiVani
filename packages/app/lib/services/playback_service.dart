import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import '../config/api_config.dart';
import '../models/newspaper_article.dart';
import 'media_session_stub.dart'
    if (dart.library.html) 'media_session_web.dart';

/// App-wide singleton: queue + audio, so playback survives navigation.
/// Bind UI with ListenableBuilder on PlaybackService.i.
class PlaybackService extends ChangeNotifier {
  PlaybackService._() {
    // OS lock-screen / headphone media controls (web Media Session API).
    initMediaSession(
      onPlay: () => player.play(),
      onPause: () {
        player.pause();
        _saveProgress();
      },
      onNext: next,
      onPrev: previous,
      onSeekForward: () => seek(position + const Duration(seconds: 15)),
      onSeekBackward: () => seek(position - const Duration(seconds: 15)),
    );
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
          if (_sleepAtTrackEnd) {
            _clearSleep(); // stop here per the sleep timer
          } else {
            _advancing = true;
            next().whenComplete(() => _advancing = false);
          }
        }
      }
      _updateMedia();
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
  // Sleep timer: pause after a duration, or at the end of the current article.
  Timer? _sleepTimer;
  DateTime? _sleepAt;
  bool _sleepAtTrackEnd = false;

  NewspaperArticle? get current =>
      (index >= 0 && index < queue.length) ? queue[index] : null;
  // The track played to its end and there's nothing auto-advancing. just_audio
  // leaves `playing == true` at completion, so guard the play/pause UI on this
  // (require a real duration so the transient zero-length completes web emits
  // while loading a new url don't count).
  bool get ended =>
      player.processingState == ProcessingState.completed &&
      (player.duration?.inMilliseconds ?? 0) > 500;
  bool get isPlaying => player.playing && !ended;
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

  /// Play an AI summary of [a] in the mini-player: store the summary text, force
  /// a fresh short synthesis of it (clearing any stale lede-briefing audio), and
  /// narrate it in brief mode so the read-along matches if expanded.
  Future<void> playSummary(NewspaperArticle a, String summary) async {
    a.summaryText = summary.trim();
    a.summaryAudioUrl = null; // regenerate audio from the summary, not the lede
    await playOne(a, brief: true);
  }

  /// Pre-synthesize the full audio without playing, so it's cached and instant
  /// later (the Download chip). Returns true if audio is ready.
  Future<bool> preload(NewspaperArticle a) async {
    if (a.audioUrl != null && a.audioUrl!.startsWith('http')) return true;
    try {
      final r = await http
          .post(Uri.parse(ApiConfig.documentsSynthesizeUrl),
              headers: {
                ...ApiConfig.authHeaders,
                'Content-Type': 'application/json'
              },
              body: json.encode({
                'text': a.spokenText,
                'language': 'te-IN',
                'articleId': a.id,
                if (a.suggestedSpeaker.isNotEmpty) 'speaker': a.suggestedSpeaker,
                if (a.readingStyle.isNotEmpty) 'readingStyle': a.readingStyle,
              }))
          .timeout(const Duration(seconds: 150));
      final data = json.decode(r.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        a.audioUrl = data['audioUrl'] as String?;
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// How many tracks are queued after the current one.
  int get upNextCount => index < 0 ? 0 : (queue.length - index - 1);

  /// Append to the Up Next queue without interrupting playback. Starts the
  /// first one only if nothing is currently playing. Skips dups already queued.
  void addToQueue(Iterable<NewspaperArticle> arts) {
    final ids = queue.map((a) => a.id).toSet();
    final toAdd = arts.where((a) => !ids.contains(a.id)).toList();
    if (toAdd.isEmpty) return;
    final startNow = index < 0 || queue.isEmpty;
    queue.addAll(toAdd);
    notifyListeners();
    if (startNow) {
      brief = false;
      _playIndex(0);
    }
  }

  /// Insert right after the current track (jump the queue).
  void playNext(Iterable<NewspaperArticle> arts) {
    if (index < 0 || queue.isEmpty) {
      addToQueue(arts);
      return;
    }
    final ids = queue.map((a) => a.id).toSet();
    final toAdd = arts.where((a) => !ids.contains(a.id)).toList();
    if (toAdd.isEmpty) return;
    queue.insertAll(index + 1, toAdd);
    notifyListeners();
  }

  Future<void> next() async {
    if (index + 1 < queue.length) await _playIndex(index + 1);
  }

  Future<void> previous() async {
    if (index > 0) await _playIndex(index - 1);
  }

  /// Stop playback and dismiss the now-playing bar entirely (queue cleared so
  /// `current` is null and the mini-player hides). Saves the spot first so the
  /// article can still be resumed from "Recently played".
  Future<void> stop() async {
    _saveProgress();
    _clearSleep();
    queue.clear();
    index = -1;
    brief = false;
    _advancing = false;
    _pendingSeek = null;
    notifyListeners();
    await player.stop();
    updateMediaSession(title: '', artist: '', playing: false);
    notifyListeners();
  }

  void toggle() {
    // At the end of an article the button is a "replay" — restart from the top.
    if (ended) {
      player.seek(Duration.zero);
      player.play();
      return;
    }
    if (player.playing) {
      player.pause();
      _saveProgress(); // remember the spot when paused
    } else {
      player.play();
    }
  }

  // ── Sleep timer ─────────────────────────────────────────────────────────────
  bool get sleepActive => _sleepTimer != null || _sleepAtTrackEnd;
  bool get sleepAtTrackEnd => _sleepAtTrackEnd;
  Duration? get sleepRemaining =>
      _sleepAt == null ? null : _sleepAt!.difference(DateTime.now());

  /// Pause after [d]. Pass null to cancel.
  void setSleepTimer(Duration? d) {
    _clearSleep();
    if (d != null) {
      _sleepAt = DateTime.now().add(d);
      _sleepTimer = Timer(d, () {
        player.pause();
        _saveProgress();
        _clearSleep();
      });
    }
    notifyListeners();
  }

  /// Stop at the end of the current article instead of after a fixed time.
  void setSleepAtTrackEnd() {
    _clearSleep();
    _sleepAtTrackEnd = true;
    notifyListeners();
  }

  void cancelSleep() {
    _clearSleep();
    notifyListeners();
  }

  void _clearSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAt = null;
    _sleepAtTrackEnd = false;
  }

  // Push current track + state to the OS media controls.
  void _updateMedia() {
    final a = current;
    if (a == null) return;
    updateMediaSession(
      title: a.title,
      artist: '${a.category} · Gativani',
      playing: player.playing,
    );
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
                  'text': brief
                      ? (a.summaryText ?? a.briefingText)
                      : a.spokenText,
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
      _updateMedia(); // push now-playing to the lock screen
    } catch (e) {
      if (epoch != _playEpoch) return;
      error = e.toString();
      loading = false;
      notifyListeners();
    }
  }
}
