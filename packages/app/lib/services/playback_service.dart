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
import 'gemini_key_store.dart';
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
          final total = _totalChunks;
          if (total != null && _loadedChunkIndex + 1 < total) {
            // More chunks left in THIS article — advance within it, not the
            // queue. _advancing still guards against this same completed
            // state re-firing while the next chunk's setUrl() loads.
            _advancing = true;
            _advanceChunk().whenComplete(() => _advancing = false);
          } else {
            _saveProgress(completed: true); // mark this one finished → "Replay"
            if (_sleepAtTrackEnd) {
              _clearSleep(); // stop here per the sleep timer
            } else {
              _advancing = true;
              _autoAdvance().whenComplete(() => _advancing = false);
            }
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
      _maybePrefetchNext(pos);
      _maybeFetchNextChunk(pos);
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
  // How close to the end of the current track/chunk to start synthesizing the
  // next one. Close enough that closing the app / bailing out mid-article
  // doesn't burn the user's Gemini quota on content never reached; early
  // enough that a single chunk-mode chunk (sized server-side to fit this
  // window — see CHUNK_MODE_LIMIT in documents-synthesize) usually finishes
  // synthesizing before it's actually needed. 25s (not 20) for margin against
  // real-world network/API jitter, while staying inside the "20-30s ahead"
  // quota budget this was scoped to.
  static const _prefetchLookahead = Duration(seconds: 25);
  // Progressive chunk playback for the CURRENT article: instead of waiting
  // for the whole article to synthesize, chunk 0 plays as soon as it's
  // ready and later chunks synthesize in the background, paced by the same
  // lookahead — so quota is only spent on audio actually listened to (plus
  // a small buffer), not the whole article up front. Null when the current
  // track isn't in chunked mode (briefs, or an already-fully-cached URL).
  int? _totalChunks;
  int _loadedChunkIndex = 0;
  final List<Duration> _chunkDurations = [];
  Duration _priorChunksElapsed = Duration.zero;
  bool _chunkFetchInFlight = false;
  int? _pendingChunkIndex;
  String? _pendingChunkUrl;
  Duration? _pendingChunkDuration;
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
  // In chunked mode, player.position/duration only cover the currently
  // loaded chunk (each chunk is its own setUrl()) — add back the elapsed
  // time of chunks already played through so the whole article reads as one
  // continuous track, matching how it behaved before chunking existed.
  Duration get position =>
      _totalChunks == null ? player.position : _priorChunksElapsed + player.position;
  // Only report a duration once a real track is loaded (avoids a stale/zero
  // duration making the lyric highlight race).
  Duration get duration {
    if (player.processingState == ProcessingState.idle) return Duration.zero;
    final total = _totalChunks;
    if (total == null) return player.duration ?? Duration.zero;
    if (_chunkDurations.length >= total) {
      // Every chunk has been synthesized — exact total.
      return _chunkDurations.fold(Duration.zero, (a, b) => a + b);
    }
    // Chunks are still being synthesized in the background — fall back to
    // the article's text-length estimate so the progress bar reads
    // sensibly until the real total is known.
    final estSec = current?.estimatedDurationSeconds ?? 0;
    return estSec > 0
        ? Duration(seconds: estSec)
        : _priorChunksElapsed + (player.duration ?? Duration.zero);
  }

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
                ...GeminiKeyStore.headers,
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
  void _maybePrefetchNext(Duration pos) {
    if (!player.playing) return;
    final dur = player.duration;
    if (dur == null || dur == Duration.zero) return;
    if (dur - pos > _prefetchLookahead) return;
    final ni = _peekNextIndex();
    if (ni == null) return;
    final next = queue[ni];
    if (next.id == _prefetchedArticleId) return;
    final alreadyReady = brief
        ? (next.summaryAudioUrl?.startsWith('http') ?? false)
        : (next.audioUrl?.startsWith('http') ?? false);
    if (alreadyReady) return;
    if (Supabase.instance.client.auth.currentUser == null) return;
    if (!GeminiKeyStore.hasKey) return;
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
                ...GeminiKeyStore.headers,
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

  void _resetChunkState() {
    _totalChunks = null;
    _loadedChunkIndex = 0;
    _chunkDurations.clear();
    _priorChunksElapsed = Duration.zero;
    _chunkFetchInFlight = false;
    _pendingChunkIndex = null;
    _pendingChunkUrl = null;
    _pendingChunkDuration = null;
  }

  /// Fetch (or cache-hit) chunk [i] of article [a]. Chunking is deterministic
  /// server-side (same text + limit always splits the same way), so a chunk
  /// index is directly addressable — no job/session state needed. Set
  /// [throwOnError] for the initial blocking chunk-0 fetch (so _playIndex can
  /// surface a real error, same as today's full-synthesis failure); the
  /// background prefetch call leaves it false and just retries next tick.
  Future<({String audioUrl, Duration duration, int totalChunks})?> _fetchChunk(
    NewspaperArticle a,
    int i, {
    bool throwOnError = false,
  }) async {
    try {
      final r = await http
          .post(Uri.parse(ApiConfig.documentsSynthesizeUrl),
              headers: {
                ...ApiConfig.authHeaders,
                'Content-Type': 'application/json',
                ...GeminiKeyStore.headers,
              },
              body: json.encode({
                'text': a.spokenText,
                'language': '${a.language}-IN',
                'articleId': a.id,
                'chunkIndex': i,
                if (a.suggestedSpeaker.isNotEmpty) 'speaker': a.suggestedSpeaker,
                if (a.readingStyle.isNotEmpty) 'readingStyle': a.readingStyle,
              }))
          .timeout(const Duration(seconds: 150));
      final data = json.decode(r.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        if (throwOnError) {
          final msg = data['error'] == 'gemini_key_required'
              ? 'Add your Gemini API key to narrate this.'
              : (data['message'] ?? 'TTS failed');
          throw Exception(msg);
        }
        return null;
      }
      final durSec = (data['durationSeconds'] as num?)?.toDouble() ?? 0;
      return (
        audioUrl: data['audioUrl'] as String,
        duration: Duration(milliseconds: (durSec * 1000).round()),
        totalChunks: (data['totalChunks'] as num?)?.toInt() ?? 1,
      );
    } catch (e) {
      if (throwOnError) rethrow;
      return null;
    }
  }

  /// Within the CURRENT article's chunks: once the buffered time left in the
  /// loaded chunk drops under [_prefetchLookahead], fetch the next chunk in
  /// the background so _advanceChunk() finds it already waiting — same
  /// pacing idea as _maybePrefetchNext, just scoped to one article's chunks
  /// instead of queued tracks.
  void _maybeFetchNextChunk(Duration pos) {
    final total = _totalChunks;
    if (total == null || _loadedChunkIndex + 1 >= total) return;
    if (!player.playing) return;
    if (_chunkFetchInFlight || _pendingChunkIndex == _loadedChunkIndex + 1) {
      return;
    }
    final dur = player.duration;
    if (dur == null || dur == Duration.zero) return;
    if (dur - pos > _prefetchLookahead) return;
    final a = current;
    if (a == null) return;
    final nextIndex = _loadedChunkIndex + 1;
    final epoch = _playEpoch;
    _chunkFetchInFlight = true;
    unawaited(_fetchChunk(a, nextIndex).then((res) {
      _chunkFetchInFlight = false;
      if (epoch != _playEpoch || res == null) return; // stale, or retry next tick
      _pendingChunkIndex = nextIndex;
      _pendingChunkUrl = res.audioUrl;
      _pendingChunkDuration = res.duration;
    }));
  }

  /// Move from the chunk that just finished to the next one — either the
  /// already-prefetched clip (the common case) or, if playback caught up
  /// before it finished fetching, synthesize it now with a brief stall (same
  /// idea as today's cold-start wait, just scoped to one chunk).
  Future<void> _advanceChunk() async {
    final epoch = _playEpoch;
    try {
      final nextIndex = _loadedChunkIndex + 1;
      String? url;
      Duration? dur;
      if (_pendingChunkIndex == nextIndex) {
        url = _pendingChunkUrl;
        dur = _pendingChunkDuration;
      }
      if (url == null) {
        final a = current;
        if (a == null) return;
        loading = true;
        notifyListeners();
        final res = (await _fetchChunk(a, nextIndex, throwOnError: true))!;
        if (epoch != _playEpoch) return;
        url = res.audioUrl;
        dur = res.duration;
      }
      _pendingChunkIndex = null;
      _pendingChunkUrl = null;
      _pendingChunkDuration = null;
      _priorChunksElapsed += _chunkDurations[_loadedChunkIndex];
      _chunkDurations.add(dur!);
      _loadedChunkIndex = nextIndex;
      await player.setUrl(url);
      if (epoch != _playEpoch) return;
      loading = false;
      notifyListeners();
      await _resumePlayback(epoch);
      _updateMedia();
    } catch (e) {
      if (epoch != _playEpoch) return;
      error = e.toString();
      loading = false;
      notifyListeners();
    }
  }

  /// Some browsers — notably iOS Safari, especially a PWA opened via "Add to
  /// Home Screen" — can silently fail to actually resume playback after the
  /// player has sat idle through a long wait (e.g. a slow chunk synthesis),
  /// rather than throwing where the caller would notice: the new source
  /// loads but audio never advances, and whatever was last buffered can
  /// keep sounding like it's replaying. A bare `unawaited(player.play())`
  /// swallowed that silently; this awaits it and retries once.
  Future<void> _resumePlayback(int epoch) async {
    try {
      await player.play();
    } catch (_) {
      if (epoch != _playEpoch) return;
      await Future.delayed(const Duration(milliseconds: 300));
      if (epoch != _playEpoch) return;
      try {
        await player.play();
      } catch (e) {
        if (epoch != _playEpoch) return;
        error = e.toString();
        notifyListeners();
      }
    }
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
  /// `next()` and `_autoAdvance()`). A chunked article needs a real restart
  /// through `_playIndex` (chunk 0 is an instant cache hit moments after
  /// finishing it) since a bare seek-to-zero would only rewind within
  /// whichever chunk happened to be loaded last, not the whole article.
  void _restartCurrentTrack() {
    if (_totalChunks != null && _totalChunks! > 1) {
      unawaited(_playIndex(index));
    } else {
      player.seek(Duration.zero);
      player.play();
    }
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
    _resetChunkState();
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

  /// Seek to an article-relative position. Plain player.seek() only works
  /// within whichever chunk happens to be loaded, so in chunked mode this
  /// resolves the target to a (possibly different) chunk first — the seek
  /// bar spans the whole article, and the OS media-session ±15s controls
  /// use the same public position/duration the seek bar does, so both need
  /// this to actually land at the right spot instead of erroring or
  /// silently clamping. Kept synchronous (fire-and-forget internally) since
  /// callers (GatiSeekBar's ValueChanged<Duration>, the media-session
  /// void-Function() closures) expect a plain void call.
  void seek(Duration d) {
    if (_totalChunks == null) {
      player.seek(d);
      return;
    }
    unawaited(_seekChunked(d));
  }

  Future<void> _seekChunked(Duration d) async {
    final a = current;
    if (a == null) return;
    final epoch = _playEpoch;
    final total = _totalChunks!;
    final target = d < Duration.zero ? Duration.zero : d;
    try {
      // Resolve which chunk the target falls in, fetching forward as needed.
      // Anything already synthesized earlier this session (or in a past
      // session, since the server caches per chunk) is a fast cache hit;
      // only genuinely new territory past everything fetched so far pays a
      // real synthesis cost.
      var idx = 0;
      var remaining = target;
      while (true) {
        if (idx >= _chunkDurations.length) {
          final res = (await _fetchChunk(a, idx, throwOnError: true))!;
          if (epoch != _playEpoch) return;
          _chunkDurations.add(res.duration);
        }
        if (idx + 1 >= total || remaining < _chunkDurations[idx]) break;
        remaining -= _chunkDurations[idx];
        idx++;
      }
      final chunkDur = _chunkDurations[idx];
      final offset = remaining < chunkDur ? remaining : chunkDur;

      if (idx == _loadedChunkIndex) {
        player.seek(offset); // already the loaded chunk — no reload needed
        return;
      }
      // Jumping to a different chunk — (re)fetch its URL, almost always a
      // cache hit, since we only keep durations (not URLs) for past chunks.
      final targetChunk = (await _fetchChunk(a, idx, throwOnError: true))!;
      if (epoch != _playEpoch) return;
      _priorChunksElapsed = _chunkDurations
          .sublist(0, idx)
          .fold(Duration.zero, (x, y) => x + y);
      _loadedChunkIndex = idx;
      final wasPlaying = player.playing;
      await player.setUrl(targetChunk.audioUrl);
      if (epoch != _playEpoch) return;
      if (offset > Duration.zero) player.seek(offset);
      if (wasPlaying) unawaited(player.play());
      notifyListeners();
    } catch (e) {
      if (epoch != _playEpoch) return;
      error = e.toString();
      notifyListeners();
    }
  }

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

  /// Re-attempt the current track after a failure (e.g. a transient TTS error).
  Future<void> retry() async {
    if (index < 0 || index >= queue.length) return;
    error = null;
    notifyListeners();
    await _playIndex(index);
  }

  Future<void> _playIndex(int idx) async {
    // Playing is the account-tied action (browsing itself stays free): sign
    // in first, then BYOK. This is the single funnel every play path goes
    // through (playOne/playAll/playAt/next/previous/addToQueue), so it's the
    // one place that needs to check, before any state even changes. Each
    // check pushes its own screen and aborts this attempt — tapping play
    // again afterward continues normally once both pass.
    if (Supabase.instance.client.auth.currentUser == null) {
      appRouter.push('/auth');
      return;
    }
    if (!GeminiKeyStore.hasKey) {
      appRouter.push('/gemini-key');
      return;
    }
    final epoch = ++_playEpoch; // any earlier in-flight _playIndex is now stale
    index = idx;
    loading = true;
    error = null;
    _resetChunkState();
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
        // prefetch) — one complete file, exactly like before chunking.
        await player.setUrl(url);
        if (epoch != _playEpoch) return;
        _finishStartingPlayback();
        return;
      }
      if (brief) {
        // Briefs are short (headline + lede) — always one Gemini call, so
        // there's no benefit to chunking; stays on the simple single-shot path.
        final r = await http
            .post(Uri.parse(ApiConfig.documentsSynthesizeUrl),
                headers: {
                  ...ApiConfig.authHeaders,
                  'Content-Type': 'application/json',
                  ...GeminiKeyStore.headers,
                },
                body: json.encode({
                  'text': a.summaryText ?? a.briefingText,
                  'language': '${a.language}-IN',
                  'articleId': a.id,
                  'target': 'summary_audio_url',
                  if (a.suggestedSpeaker.isNotEmpty) 'speaker': a.suggestedSpeaker,
                  if (a.readingStyle.isNotEmpty) 'readingStyle': a.readingStyle,
                }))
            .timeout(const Duration(seconds: 150));
        if (epoch != _playEpoch) return; // superseded while synthesizing
        final data = json.decode(r.body) as Map<String, dynamic>;
        if (data['ok'] != true) {
          final msg = data['error'] == 'gemini_key_required'
              ? 'Add your Gemini API key to narrate this.'
              : (data['message'] ?? 'TTS failed');
          throw Exception(msg);
        }
        a.summaryAudioUrl = data['audioUrl'] as String;
        await player.setUrl(a.summaryAudioUrl!);
        if (epoch != _playEpoch) return;
        _finishStartingPlayback();
        return;
      }
      // Full article, not yet synthesized: play chunk 0 the instant it's
      // ready, then fetch the rest in the background (_maybeFetchNextChunk /
      // _advanceChunk), paced by how far the listener actually gets — so
      // closing the app or skipping around doesn't burn quota synthesizing
      // audio nobody heard.
      var chunk = (await _fetchChunk(a, 0, throwOnError: true))!;
      if (epoch != _playEpoch) return; // superseded while synthesizing
      _totalChunks = chunk.totalChunks;
      _chunkDurations.add(chunk.duration);
      _loadedChunkIndex = 0;

      // Resuming partway through (e.g. "Continue listening")? Walk forward
      // through chunks — sequentially, since each one's duration is only
      // known once fetched — until the target position falls within one.
      // These are almost always cache hits in practice: a resume target
      // only exists because the article was already played up to roughly
      // that point, so the leading chunks were already synthesized (and
      // cached) during that earlier listen.
      final resumeTarget = _pendingSeek;
      var offsetInChunk = Duration.zero;
      if (resumeTarget != null && resumeTarget > Duration.zero) {
        var remaining = resumeTarget;
        while (remaining >= _chunkDurations[_loadedChunkIndex] &&
            _loadedChunkIndex + 1 < _totalChunks!) {
          remaining -= _chunkDurations[_loadedChunkIndex];
          _priorChunksElapsed += _chunkDurations[_loadedChunkIndex];
          _loadedChunkIndex++;
          final next = (await _fetchChunk(a, _loadedChunkIndex, throwOnError: true))!;
          if (epoch != _playEpoch) return;
          _chunkDurations.add(next.duration);
          chunk = next;
        }
        final currentChunkDur = _chunkDurations[_loadedChunkIndex];
        offsetInChunk = remaining < currentChunkDur ? remaining : currentChunkDur;
      }

      await player.setUrl(chunk.audioUrl);
      if (epoch != _playEpoch) return;
      if (offsetInChunk > Duration.zero) player.seek(offsetInChunk);
      _finishStartingPlayback(seek: false);
    } catch (e) {
      if (epoch != _playEpoch) return;
      error = e.toString();
      loading = false;
      notifyListeners();
    }
  }

  /// Shared tail once a source is loaded and about to play: resume-seek,
  /// bump recently-played, clear loading, start playback. Pass [seek]=false
  /// when the caller already positioned the player itself (chunked mode maps
  /// a global resume position to a specific chunk + offset, which a plain
  /// `player.seek(_pendingSeek!)` against the whole-article duration can't do).
  void _finishStartingPlayback({bool seek = true}) {
    // Resume partway through if requested (e.g. "Resume" on a tile).
    final startPos = _pendingSeek?.inSeconds ?? 0;
    if (seek && _pendingSeek != null) player.seek(_pendingSeek!);
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
