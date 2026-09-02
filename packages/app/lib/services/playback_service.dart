import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/api_config.dart';
import '../models/newspaper_article.dart';
import '../router.dart';
import 'media_session_stub.dart'
    if (dart.library.html) 'media_session_web.dart';

/// How the queue behaves when a track finishes: play on, loop the whole
/// queue, or repeat the current track.
enum QueueRepeat { off, all, one }

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
            _autoAdvance().whenComplete(() => _advancing = false);
          }
        }
      }
      _updateMedia();
      notifyListeners();
    });
    player.positionStream.listen((_) {
      notifyListeners();
      // Persist progress every ~10s while actually playing, so a tile can show
      // "Resume" with the right spot. Cheap upsert; full saves also on pause /
      // completion / track start.
      if (!brief &&
          player.playing &&
          (position.inSeconds - _lastSaveSec).abs() >= 10) {
        _saveProgress();
      }
      _maybePrefetchNext();
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
  // Article id we've already kicked off a background prefetch-synthesis for,
  // so a burst of position-stream ticks near the end of a track doesn't fire
  // duplicate requests.
  String? _prefetchedArticleId;
  // How close to the end of the current ARTICLE to start synthesizing the
  // next queued one (see _maybePrefetchNext). Close enough that closing the
  // app / bailing out mid-article doesn't burn TTS quota on a track never
  // reached; 25s (not 20) for margin against real-world network/API jitter.
  static const _prefetchLookahead = Duration(seconds: 25);
  // When true, this session narrates the short briefing (headline + lede) and
  // caches it separately. The lyrics view reads this to show matching text.
  bool brief = false;
  // Resume support: where to start the next track, and a throttle marker for
  // how recently progress was persisted.
  Duration? _pendingSeek;
  int _lastSaveSec = -999;
  // Rate-limits progress writes: many events (position ticks, play/pause/seek,
  // track start) can fire in a burst — especially on web when a source errors
  // and the player cycles state — which used to flood recent_plays with writes.
  DateTime _lastSaveAt = DateTime.fromMillisecondsSinceEpoch(0);
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
  Duration get duration => player.processingState == ProcessingState.idle
      ? Duration.zero
      : (player.duration ?? Duration.zero);

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
                'Content-Type': 'application/json',
              },
              body: json.encode({
                'text': a.spokenText,
                'language': '${a.language}-IN',
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

  /// The queue position that will play next in the current (non-shuffle)
  /// order, or null if nothing predictable is next. Shuffle picks its next
  /// index randomly at the moment of advancing (see `_nextIndex`), so there's
  /// nothing to prefetch ahead of time there.
  int? _peekNextIndex() {
    if (shuffle || queue.isEmpty || index < 0) return null;
    if (index + 1 < queue.length) return index + 1;
    if (repeatMode == QueueRepeat.all && queue.length > 1) return 0;
    return null;
  }

  /// Once the current track is within [_prefetchLookahead] of ending, kick off
  /// synthesis for the next queued track in the background — so it's likely
  /// already cached by the time the user reaches it, without having spent that
  /// cost on tracks they never get to (closing the app, skipping around).
  void _maybePrefetchNext() {
    if (!player.playing) return;
    final dur = duration;
    if (dur == Duration.zero) return;
    if (dur - position > _prefetchLookahead) return;
    final ni = _peekNextIndex();
    if (ni == null) return;
    final next = queue[ni];
    if (next.id == _prefetchedArticleId) return;
    final alreadyReady = brief
        ? (next.summaryAudioUrl?.startsWith('http') ?? false)
        : (next.audioUrl?.startsWith('http') ?? false);
    if (alreadyReady) return;
    if (Supabase.instance.client.auth.currentUser == null) return;
    _prefetchedArticleId = next.id;
    unawaited(_prefetchSynthesis(next));
  }

  Future<void> _prefetchSynthesis(NewspaperArticle a) async {
    try {
      final r = await http
          .post(Uri.parse(ApiConfig.documentsSynthesizeUrl),
              headers: {
                ...ApiConfig.authHeaders,
                'Content-Type': 'application/json',
              },
              body: json.encode({
                'text':
                    brief ? (a.summaryText ?? a.briefingText) : a.spokenText,
                'language': '${a.language}-IN',
                'articleId': a.id,
                if (brief) 'target': 'summary_audio_url',
                if (a.suggestedSpeaker.isNotEmpty) 'speaker': a.suggestedSpeaker,
                if (a.readingStyle.isNotEmpty) 'readingStyle': a.readingStyle,
              }))
          .timeout(const Duration(seconds: 150));
      final data = json.decode(r.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        final url = data['audioUrl'] as String?;
        if (brief) {
          a.summaryAudioUrl = url;
        } else {
          a.audioUrl = url;
        }
      }
    } catch (_) {
      // Best-effort — if this fails, _playIndex still synthesizes normally
      // (with its own retry path) once the user actually reaches this track.
    }
  }

  /// Track change: allow the queue-level prefetch to consider articles
  /// afresh — a marker left from a FAILED prefetch otherwise blocked any
  /// retry for that article for the rest of the session.
  void _resetTrackState() {
    _prefetchedArticleId = null;
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

  /// Jump to a specific queue position (tapping a row in "Your Queue").
  Future<void> playAt(int i) async {
    if (i >= 0 && i < queue.length) await _playIndex(i);
  }

  Future<void> next() async {
    final ni = _nextIndex();
    if (ni == null) return;
    if (ni == index) {
      // Single-track queue looping — restart instead of re-synthesizing.
      _restartCurrentTrack();
      return;
    }
    await _playIndex(ni);
  }

  /// Restart the current track from the top (single-track repeat — see
  /// `next()` and `_autoAdvance()`).
  void _restartCurrentTrack() {
    player.seek(Duration.zero);
    player.play();
  }

  Future<void> previous() async {
    if (index > 0) await _playIndex(index - 1);
  }

  /// What plays when the current track ends, honoring repeat + shuffle.
  Future<void> _autoAdvance() async {
    if (repeatMode == QueueRepeat.one) {
      _restartCurrentTrack();
      return;
    }
    await next();
  }

  /// Next queue position, or null when playback should stop at the end.
  int? _nextIndex() {
    if (queue.isEmpty || index < 0) return null;
    if (shuffle && queue.length > 1) {
      var j = index;
      final r = math.Random();
      while (j == index) {
        j = r.nextInt(queue.length);
      }
      return j;
    }
    if (index + 1 < queue.length) return index + 1;
    return repeatMode == QueueRepeat.all ? (queue.length == 1 ? index : 0) : null;
  }

  // ── Playback modes: mute, repeat, shuffle ─────────────────────────────────
  bool muted = false;
  double _volumeBeforeMute = 1.0;
  QueueRepeat repeatMode = QueueRepeat.off;
  bool shuffle = false;

  void toggleMute() {
    if (muted) {
      player.setVolume(_volumeBeforeMute);
    } else {
      _volumeBeforeMute = player.volume;
      player.setVolume(0);
    }
    muted = !muted;
    notifyListeners();
  }

  void cycleRepeat() {
    repeatMode =
        QueueRepeat.values[(repeatMode.index + 1) % QueueRepeat.values.length];
    notifyListeners();
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
  }

  /// Stop playback and dismiss the now-playing bar entirely (queue cleared so
  /// `current` is null and the mini-player hides). Saves the spot first so the
  /// article can still be resumed from "Recently played".
  Future<void> stop() async {
    // Invalidate any in-flight _playIndex (mid-synthesis) — without this,
    // closing the mini-player during processing let the request finish and
    // start GHOST audio with no player visible to stop it.
    _playEpoch++;
    loading = false;
    error = null;
    _saveProgress();
    _clearSleep();
    queue.clear();
    index = -1;
    brief = false;
    _advancing = false;
    _pendingSeek = null;
    _resetTrackState();
    notifyListeners();
    await player.stop();
    updateMediaSession(title: '', artist: '', playing: false);
    notifyListeners();
  }

  void toggle() {
    // At the end of an article the button is a "replay" — restart from the top.
    if (ended) {
      _restartCurrentTrack();
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

  void seek(Duration d) => player.seek(d < Duration.zero ? Duration.zero : d);

  void setSpeed(double s) => player.setSpeed(s);

  /// Upsert the current article's playback progress into recent_plays (one row
  /// per article). DB-backed so web and the future native apps share it without
  /// any platform-specific storage. [atSeconds] overrides the live position
  /// (used at track start, before a resume-seek has applied). [includeContent]
  /// (re)writes a 24h content snapshot alongside the progress — set only at
  /// track start (see _finishStartingPlayback), not on every periodic tick,
  /// so a several-KB article body isn't re-uploaded every ~10s. This is what
  /// lets a Live article (which has no other persisted copy once it scrolls
  /// out of the in-memory feed pool) still be resumed/reopened for a day.
  void _saveProgress(
      {bool completed = false, int? atSeconds, bool includeContent = false}) {
    final a = current;
    if (a == null) return;
    // Throttle to at most one write per 5s, so a burst of player events can't
    // storm the DB. `completed` is terminal — always let it record the final
    // spot so a finished article correctly shows "Replay".
    final now = DateTime.now();
    if (!completed && now.difference(_lastSaveAt) < const Duration(seconds: 5)) {
      return;
    }
    _lastSaveAt = now;
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
            Uri.parse(
                '${ApiConfig.restUrl}/recent_plays?on_conflict=user_id,article_id'),
            headers: {
              // recent_plays is scoped per user (RLS checks auth.uid()) — the
              // anon-key authHeaders would write/read as nobody.
              ...ApiConfig.userAuthHeaders,
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
              if (includeContent && !brief) ...{
                'content': a.content,
                'preview': a.preview,
                'language': a.language,
                'content_expires_at': DateTime.now()
                    .toUtc()
                    .add(const Duration(hours: 24))
                    .toIso8601String(),
              },
            }))
        .catchError((_) => http.Response('', 204));
  }

  /// Re-attempt the current track after a failure (e.g. a transient TTS
  /// error), carrying the current position so a retry resumes where it
  /// stopped rather than restarting the article.
  Future<void> retry() async {
    if (index < 0 || index >= queue.length) return;
    error = null;
    final resumeAt = position;
    if (resumeAt > Duration.zero) _pendingSeek = resumeAt;
    notifyListeners();
    await _playIndex(index);
  }

  Future<void> _playIndex(int idx) async {
    // Playing is the account-tied action (browsing itself stays free): sign
    // in required, narration runs on GatiVāni's own shared key (no BYOK).
    // This is the single funnel every play path goes through
    // (playOne/playAll/playAt/next/previous/addToQueue), so it's the one
    // place that needs to check, before any state even changes.
    if (Supabase.instance.client.auth.currentUser == null) {
      appRouter.push('/auth');
      return;
    }
    final epoch = ++_playEpoch; // any earlier in-flight _playIndex is now stale
    index = idx;
    loading = true;
    error = null;
    _resetTrackState();
    notifyListeners();
    try {
      final a = queue[idx];
      // Stop whatever's currently loaded BEFORE loading the next source —
      // setUrl() alone isn't a hard enough cut for every case (a slow-loading
      // or flaky external MP3 host can leave the previous track audibly
      // playing while the UI has already switched to the new one, e.g. two
      // podcast tiles tapped back-to-back). This used to only run before a
      // fresh TTS synthesis (which can take many seconds); now it always runs.
      await player.stop();
      if (epoch != _playEpoch) return;
      // Briefing sessions narrate + cache the short version separately.
      final url = brief ? a.summaryAudioUrl : a.audioUrl;
      if (url != null && url.startsWith('http')) {
        // Already fully synthesized (download, an earlier full play, or a
        // prefetch) — play it directly.
        await player.setUrl(url);
        if (epoch != _playEpoch) return;
        _finishStartingPlayback();
        return;
      }
      // Not yet synthesized: one request, one complete file. Briefs narrate
      // the headline + lede into their own cache column; full articles
      // narrate the whole body.
      final r = await http
          .post(Uri.parse(ApiConfig.documentsSynthesizeUrl),
              headers: {
                ...ApiConfig.authHeaders,
                'Content-Type': 'application/json',
              },
              body: json.encode({
                'text':
                    brief ? (a.summaryText ?? a.briefingText) : a.spokenText,
                'language': '${a.language}-IN',
                'articleId': a.id,
                if (brief) 'target': 'summary_audio_url',
                if (a.suggestedSpeaker.isNotEmpty) 'speaker': a.suggestedSpeaker,
                if (a.readingStyle.isNotEmpty) 'readingStyle': a.readingStyle,
              }))
          .timeout(const Duration(seconds: 150));
      if (epoch != _playEpoch) return; // superseded while synthesizing
      final data = json.decode(r.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['message'] ?? 'TTS failed');
      }
      final fresh = data['audioUrl'] as String;
      if (brief) {
        a.summaryAudioUrl = fresh;
      } else {
        a.audioUrl = fresh;
      }
      await player.setUrl(fresh);
      if (epoch != _playEpoch) return;
      _finishStartingPlayback();
    } catch (e) {
      if (epoch != _playEpoch) return;
      error = e.toString();
      loading = false;
      notifyListeners();
    }
  }

  /// Shared tail once a source is loaded and about to play: resume-seek,
  /// bump recently-played, clear loading, start playback.
  void _finishStartingPlayback() {
    // Resume partway through if requested (e.g. "Resume" on a tile).
    final startPos = _pendingSeek?.inSeconds ?? 0;
    if (_pendingSeek != null) player.seek(_pendingSeek!);
    _pendingSeek = null;
    // bumps recently-played + records spot + (re)writes the 24h content
    // snapshot so this article can still be resumed/reopened later even if
    // it's a Live one that's since scrolled out of the in-memory feed pool.
    _saveProgress(atSeconds: startPos, includeContent: true);
    loading = false;
    notifyListeners();
    unawaited(player.play());
    _updateMedia(); // push now-playing to the lock screen
  }
}
