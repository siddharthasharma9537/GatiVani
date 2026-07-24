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
          !_advancing &&
          _activeSeeks == 0) {
        final dur = player.duration;
        final pos = player.position;
        final reachedEnd = dur != null &&
            dur.inMilliseconds > 500 &&
            pos.inMilliseconds >= dur.inMilliseconds - 800;
        // In chunked mode, additionally require the completed source to BE
        // the chunk the bookkeeping says is loaded. Each chunk's duration is
        // measured server-side from the same file the player loads, so they
        // match to rounding; a mismatch means this event is a stale emission
        // from a previous chunk (web re-emits completed around source swaps),
        // and advancing on it would cut the real current chunk short.
        final isCurrentChunk = _totalChunks == null ||
            _loadedChunkIndex >= _chunkDurations.length ||
            (dur != null &&
                (dur - _chunkDurations[_loadedChunkIndex]).abs() <
                    const Duration(seconds: 3));
        if (reachedEnd && isCurrentChunk) {
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
      // Compare article-level positions: _lastSaveSec stores the article
      // position, so measuring against the chunk-level `pos` made every tick
      // past chunk 0 look ≥10s away and fire a save attempt each time.
      if (!brief &&
          player.playing &&
          (position.inSeconds - _lastSaveSec).abs() >= 10) {
        _saveProgress();
      }
      _maybePrefetchNext();
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
  // Serializes chunk-swap operations (_advanceChunk / _seekChunked): each op
  // takes a fresh id and abandons itself the moment another op has started,
  // so two overlapping swaps can never both commit position bookkeeping —
  // previously a seek dragged during a slow chunk transition interleaved
  // with the in-flight advance and corrupted _priorChunksElapsed.
  int _chunkOpId = 0;
  // Non-zero while a chunked seek is resolving/loading its target chunk;
  // blocks the completed-listener from auto-advancing over the user's seek.
  int _activeSeeks = 0;
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
  // Set right before a chunk swap's setUrl() and cleared right after
  // _priorChunksElapsed/_loadedChunkIndex commit for it. just_audio's
  // position resets to zero the moment the new source loads — BEFORE our own
  // bookkeeping has caught up — and position's stream listener can observe
  // that transient zero in between (article-level `position` would briefly
  // read as 0 instead of "just finished the previous chunk"). That's a real,
  // confirmed bug: it wrote position_seconds=0 to recent_plays mid-article
  // (traced against a real play — the row's content_expires_at proved it
  // wasn't a genuine restart, just this transient reflected into a periodic
  // save) and, for the same reason, could show the seek bar/highlight
  // snapping back to the start for a frame. Holding `position` at its
  // last-known-correct value for this narrow window closes both.
  Duration? _frozenPosition;
  // The background prefetch's own in-flight request, keyed by which chunk
  // it's for — so _advanceChunk can AWAIT this instead of firing a second,
  // redundant fetch for the same chunk when playback catches up before the
  // prefetch resolves. Two concurrent requests for one chunk each burn a
  // full call against a rate-limited key for no benefit (same target,
  // same cache row) — that duplication was silently doubling Gemini usage
  // on exactly the transitions that were already running late.
  Future<({String audioUrl, Duration duration, int totalChunks})?>?
      _inFlightChunkFuture;
  int? _inFlightChunkIndex;
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
  // In chunked mode a MIDDLE chunk completing is not the article ending —
  // it's the (possibly long) stall while the next chunk synthesizes. Without
  // the last-chunk check, the UI flipped to "replay" during every stalled
  // transition, and tapping it restarted the whole article from chunk 0.
  bool get ended =>
      player.processingState == ProcessingState.completed &&
      (player.duration?.inMilliseconds ?? 0) > 500 &&
      (_totalChunks == null || _loadedChunkIndex + 1 >= _totalChunks!);
  bool get isPlaying => player.playing && !ended;
  double get speed => player.speed;
  // In chunked mode, player.position/duration only cover the currently
  // loaded chunk (each chunk is its own setUrl()) — add back the elapsed
  // time of chunks already played through so the whole article reads as one
  // continuous track, matching how it behaved before chunking existed.
  Duration get position {
    if (_totalChunks == null) return player.position;
    final frozen = _frozenPosition;
    if (frozen != null) return frozen;
    return _priorChunksElapsed + player.position;
  }
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
    // Use the article-level duration/position (sums across all chunks), not
    // player.duration/player.position which only cover the currently loaded
    // chunk. Using chunk-level values here meant a short chunk 0 (e.g. ~19s)
    // was already inside the lookahead window the instant playback started,
    // firing a full background synthesis for the NEXT queued article within
    // seconds of starting the CURRENT one — burning Gemini's 3 RPM budget
    // against the current article's own in-flight chunk fetches and starving
    // them, not just wasting quota on a track the user might skip.
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

  void _resetChunkState() {
    // Track change: allow the queue-level prefetch to consider articles
    // afresh — a marker left from a FAILED prefetch otherwise blocked any
    // retry for that article for the rest of the session.
    _prefetchedArticleId = null;
    _totalChunks = null;
    _loadedChunkIndex = 0;
    _chunkDurations.clear();
    _priorChunksElapsed = Duration.zero;
    // Any Future already in flight for the previous article just gets
    // orphaned here (Futures can't be cancelled) — its .then() callback
    // still runs eventually, but the epoch check inside it discards the
    // result since _playEpoch will have moved on.
    _inFlightChunkFuture = null;
    _inFlightChunkIndex = null;
    _pendingChunkIndex = null;
    _pendingChunkUrl = null;
    _pendingChunkDuration = null;
    // Guaranteed cleared by try/finally in _advanceChunk/_seekChunked
    // already — this is just a clean-slate safety net on track change.
    _frozenPosition = null;
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
    // A swap is mid-flight — indices are about to shift, and firing a fetch
    // against the old _loadedChunkIndex here re-requests the very chunk the
    // swap is loading.
    if (_advancing || _activeSeeks > 0) return;
    final nextIndex = _loadedChunkIndex + 1;
    if (_pendingChunkIndex == nextIndex || _inFlightChunkIndex == nextIndex) {
      return;
    }
    final dur = player.duration;
    if (dur == null || dur == Duration.zero) return;
    if (dur - pos > _prefetchLookahead) return;
    final a = current;
    if (a == null) return;
    final epoch = _playEpoch;
    final future = _fetchChunk(a, nextIndex);
    _inFlightChunkIndex = nextIndex;
    _inFlightChunkFuture = future;
    unawaited(future.then((res) {
      if (identical(_inFlightChunkFuture, future)) {
        _inFlightChunkIndex = null;
        _inFlightChunkFuture = null;
      }
      if (epoch != _playEpoch || res == null) return; // stale, or retry next tick
      _pendingChunkIndex = nextIndex;
      _pendingChunkUrl = res.audioUrl;
      _pendingChunkDuration = res.duration;
    }));
  }

  /// Move from the chunk that just finished to the next one — either the
  /// already-prefetched clip (the common case), the background prefetch's
  /// own request if it's still running (waited on rather than duplicated),
  /// or — if nothing was prefetched at all — synthesize it now with a brief
  /// stall (same idea as today's cold-start wait, just scoped to one chunk).
  Future<void> _advanceChunk() async {
    final epoch = _playEpoch;
    final op = ++_chunkOpId;
    bool live() => epoch == _playEpoch && op == _chunkOpId;
    try {
      final nextIndex = _loadedChunkIndex + 1;
      String? url;
      Duration? dur;
      if (_pendingChunkIndex == nextIndex) {
        url = _pendingChunkUrl;
        dur = _pendingChunkDuration;
      } else if (_inFlightChunkIndex == nextIndex &&
          _inFlightChunkFuture != null) {
        loading = true;
        notifyListeners();
        final res = await _inFlightChunkFuture!;
        if (!live()) return;
        if (res != null) {
          url = res.audioUrl;
          dur = res.duration;
        }
        // res == null: the prefetch failed silently (it doesn't throw) —
        // fall through to a fresh, error-surfacing attempt below rather
        // than leaving the player stuck with no signal.
      }
      if (url == null) {
        final a = current;
        if (a == null) return;
        loading = true;
        notifyListeners();
        final res = (await _fetchChunk(a, nextIndex, throwOnError: true))!;
        if (!live()) return;
        url = res.audioUrl;
        dur = res.duration;
      }
      _pendingChunkIndex = null;
      _pendingChunkUrl = null;
      _pendingChunkDuration = null;
      // Load — and VERIFY — the new source before committing "we've
      // advanced" bookkeeping. Committing first left the article-level
      // position claiming the next chunk was playing while the player was
      // still on (and could replay) the old one whenever the swap failed,
      // which is exactly the "seek bar far ahead of the audio" symptom.
      // Freeze the reported position across the swap: player.position
      // resets to 0 the instant the new source loads, before the
      // _priorChunksElapsed commit below catches up, and a positionStream
      // tick landing in that gap would read (and could even persist) the
      // article as being back at 0 — see _frozenPosition's own doc comment.
      _frozenPosition = position;
      try {
        await _loadChunkUrl(url, dur!, epoch);
        if (!live()) return;
        _priorChunksElapsed += _chunkDurations[_loadedChunkIndex];
        _chunkDurations.add(dur);
        _loadedChunkIndex = nextIndex;
      } finally {
        _frozenPosition = null;
      }
      loading = false;
      notifyListeners();
      // Respect a pause made during the stall: `playing` stays true through
      // a natural chunk completion, so false here means the user explicitly
      // paused while waiting — don't yank playback back on.
      if (player.playing) await _resumePlayback(epoch);
      _updateMedia();
    } catch (e) {
      if (!live()) return;
      error = e.toString();
      loading = false;
      notifyListeners();
    }
  }

  /// Load [url] and verify the player actually swapped to it. On iOS Safari
  /// a setUrl over an ended source can fail SILENTLY — the call returns but
  /// the old audio stays loaded, so the old chunk replays while the
  /// bookkeeping says the next one is playing. The loaded duration is the
  /// tell: [expected] was measured server-side from the very same file, so
  /// they match to rounding; a real mismatch means the swap didn't take.
  /// Retries once (covers plain transient network failures too), then throws
  /// so the caller surfaces a retryable error instead of desyncing.
  Future<void> _loadChunkUrl(String url, Duration expected, int epoch) async {
    Future<bool> swapped() async {
      final d = await player.setUrl(url);
      return d == null || (d - expected).abs() < const Duration(seconds: 3);
    }
    try {
      if (await swapped()) return;
    } catch (_) {
      // fall through to the single retry below
    }
    if (epoch != _playEpoch) return;
    await Future.delayed(const Duration(milliseconds: 500));
    if (epoch != _playEpoch) return;
    if (!await swapped()) {
      throw Exception('Audio failed to load — tap retry.');
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
    // Take the chunk-op token: any in-flight _advanceChunk abandons itself
    // at its next checkpoint, so a seek dragged during a slow transition
    // can't interleave with it and corrupt the position bookkeeping.
    final op = ++_chunkOpId;
    bool live() => epoch == _playEpoch && op == _chunkOpId;
    final total = _totalChunks!;
    final target = d < Duration.zero ? Duration.zero : d;
    _activeSeeks++;
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
          loading = true;
          notifyListeners();
          final res = (await _fetchChunk(a, idx, throwOnError: true))!;
          if (!live()) return;
          _chunkDurations.add(res.duration);
        }
        if (idx + 1 >= total || remaining < _chunkDurations[idx]) break;
        remaining -= _chunkDurations[idx];
        idx++;
      }
      final chunkDur = _chunkDurations[idx];
      final offset = remaining < chunkDur ? remaining : chunkDur;

      if (idx == _loadedChunkIndex) {
        // Already the loaded chunk — no reload needed. (Also clears a
        // `loading` left behind by an advance this seek superseded.)
        loading = false;
        player.seek(offset);
        notifyListeners();
        return;
      }
      // Jumping to a different chunk — (re)fetch its URL, almost always a
      // cache hit, since we only keep durations (not URLs) for past chunks.
      final targetChunk = (await _fetchChunk(a, idx, throwOnError: true))!;
      if (!live()) return;
      final wasPlaying = player.playing;
      // Same verified-load as _advanceChunk, and same ordering rule: only
      // commit the position bookkeeping once the player really holds the
      // target chunk. Freeze position at the seek TARGET (not the pre-seek
      // spot — the user is deliberately leaving that) across the swap, same
      // reasoning as _advanceChunk: player.position resets to 0 the instant
      // the new chunk loads, before _priorChunksElapsed/the actual seek()
      // below catch up, and a positionStream tick in that gap would
      // otherwise report the article as sitting at 0.
      _frozenPosition = target;
      try {
        await _loadChunkUrl(targetChunk.audioUrl, targetChunk.duration, epoch);
        if (!live()) return;
        _priorChunksElapsed = _chunkDurations
            .sublist(0, idx)
            .fold(Duration.zero, (x, y) => x + y);
        _loadedChunkIndex = idx;
      } finally {
        _frozenPosition = null;
      }
      loading = false;
      if (offset > Duration.zero) player.seek(offset);
      if (wasPlaying) unawaited(player.play());
      notifyListeners();
    } catch (e) {
      if (!live()) return;
      error = e.toString();
      loading = false;
      notifyListeners();
    } finally {
      _activeSeeks--;
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

  /// Re-attempt the current track after a failure (e.g. a transient TTS error).
  /// A chunk-mode failure typically happens mid-article (chunk 0 played fine,
  /// chunk N's fetch threw) — restarting via a bare _playIndex would replay
  /// chunk 0 in full before hitting the same failure again. Carrying the
  /// current article-level position into _pendingSeek makes _playIndex reuse
  /// its existing resume-walk (built for "Continue listening") to skip
  /// straight back to re-fetching the chunk that actually failed.
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

      // Verified load — same reasoning as _advanceChunk/_seekChunked: a
      // resume can land several chunks in, and a silent setUrl failure here
      // would leave the bookkeeping claiming that position while nothing
      // actually plays.
      await _loadChunkUrl(chunk.audioUrl, chunk.duration, epoch);
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
