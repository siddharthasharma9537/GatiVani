import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../config/api_config.dart' show ApiConfig;
import '../design/app_theme.dart';
import '../models/newspaper_article.dart';

class AudioQueuePlayerScreen extends StatefulWidget {
  final List<NewspaperArticle> articles;
  final String tier;

  const AudioQueuePlayerScreen({
    Key? key,
    required this.articles,
    required this.tier,
  }) : super(key: key);

  @override
  State<AudioQueuePlayerScreen> createState() => _AudioQueuePlayerScreenState();
}

class _AudioQueuePlayerScreenState extends State<AudioQueuePlayerScreen> {
  late final AudioPlayer _player;
  late final List<NewspaperArticle> _articles;

  int _currentIndex = 0;
  bool _showTranscript = false;
  bool _prefetchTriggered = false;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _articles = List<NewspaperArticle>.from(
      widget.articles.map((a) => a.copyWith()),
    );
    _loadArticle(0);
    _positionSub = _player.positionStream.listen(_onPosition);
    _stateSub = _player.playerStateStream.listen(_onPlayerState);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  // ── TTS generation ──────────────────────────────────────────────────────────

  Future<void> _loadArticle(int index) async {
    if (index >= _articles.length) return;
    if (_articles[index].audioStatus == ArticleAudioStatus.ready ||
        _articles[index].audioStatus == ArticleAudioStatus.loading) return;

    setState(() {
      _articles[index] = _articles[index].copyWith(audioStatus: ArticleAudioStatus.loading);
    });

    try {
      final resp = await http.post(
        Uri.parse(ApiConfig.documentsSynthesizeUrl),
        headers: {
          ...ApiConfig.authHeaders,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'text': _articles[index].content}),
      ).timeout(const Duration(seconds: 120));

      if (resp.statusCode != 200) throw Exception('TTS HTTP ${resp.statusCode}');

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['message'] ?? 'TTS failed');

      final rawUrl = data['audioUrl'] as String?;
      if (rawUrl == null || rawUrl.isEmpty) throw Exception('No audioUrl in response');

      final playableUrl = await _resolveAudioUrl(rawUrl);

      setState(() {
        _articles[index] = _articles[index].copyWith(
          audioUrl: playableUrl,
          audioStatus: ArticleAudioStatus.ready,
        );
      });

      // If this is the current article, start playing immediately
      if (index == _currentIndex) {
        await _play(index);
      }
    } catch (e) {
      debugPrint('[TTS] Failed article $index: $e');
      setState(() {
        _articles[index] = _articles[index].copyWith(audioStatus: ArticleAudioStatus.failed);
      });
    }
  }

  /// Converts a data: URL to a file:// path on mobile, passes through on web.
  Future<String> _resolveAudioUrl(String url) async {
    if (kIsWeb) return url;
    if (!url.startsWith('data:')) return url;

    final comma = url.indexOf(',');
    if (comma < 0) throw Exception('Malformed data URL');
    final b64 = url.substring(comma + 1);
    final bytes = base64Decode(b64);

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/gativani_article_$_currentIndex.mp3');
    await file.writeAsBytes(bytes);
    return file.uri.toString();
  }

  Future<void> _play(int index) async {
    final url = _articles[index].audioUrl;
    if (url == null || url.isEmpty) return;
    try {
      _prefetchTriggered = false;
      await _player.setAudioSource(AudioSource.uri(Uri.parse(url)));
      await _player.play();
    } catch (e) {
      debugPrint('[Player] play error: $e');
    }
  }

  // ── Playback events ─────────────────────────────────────────────────────────

  void _onPosition(Duration position) {
    if (_prefetchTriggered) return;
    final duration = _player.duration;
    if (duration == null || duration.inMilliseconds == 0) return;
    final progress = position.inMilliseconds / duration.inMilliseconds;
    if (progress >= 0.8 && _currentIndex + 1 < _articles.length) {
      _prefetchTriggered = true;
      _loadArticle(_currentIndex + 1);
    }
  }

  void _onPlayerState(PlayerState state) {
    if (state.processingState == ProcessingState.completed) {
      _advance();
    }
  }

  void _advance() {
    if (_currentIndex + 1 >= _articles.length) return;
    setState(() {
      _currentIndex++;
      _prefetchTriggered = false;
    });
    final next = _articles[_currentIndex];
    if (next.audioStatus == ArticleAudioStatus.ready) {
      _play(_currentIndex);
    } else {
      _loadArticle(_currentIndex);
    }
  }

  // ── Controls ────────────────────────────────────────────────────────────────

  void _seekBack() {
    final target = _player.position - const Duration(seconds: 10);
    _player.seek(target < Duration.zero ? Duration.zero : target);
  }

  void _seekForward() {
    final dur = _player.duration ?? Duration.zero;
    final target = _player.position + const Duration(seconds: 30);
    _player.seek(target > dur ? dur : target);
  }

  void _previous() {
    if (_currentIndex == 0) return;
    setState(() {
      _currentIndex--;
      _prefetchTriggered = false;
    });
    final prev = _articles[_currentIndex];
    if (prev.audioStatus == ArticleAudioStatus.ready) {
      _play(_currentIndex);
    } else {
      _loadArticle(_currentIndex);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final current = _articles[_currentIndex];
    final catColor = GVCategory.color(current.category);
    final upNext = _articles.length > _currentIndex + 1
        ? _articles.sublist(_currentIndex + 1)
        : <NewspaperArticle>[];

    return Scaffold(
      backgroundColor: GVColors.bgSecondary(context),
      appBar: AppBar(
        backgroundColor: GVColors.bgPrimary(context),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          color: GVColors.textPrimary(context),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${_currentIndex + 1} of ${_articles.length}',
          style: GVTypography.small(context),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _showTranscript ? Icons.subtitles : Icons.subtitles_outlined,
              color: _showTranscript ? GVColors.accent(context) : GVColors.textSecondary(context),
            ),
            tooltip: 'Toggle transcript',
            onPressed: () => setState(() => _showTranscript = !_showTranscript),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: catColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(GVRadius.sm),
                    ),
                    child: Text(
                      current.category,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: catColor),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Article title
                  Text(current.title, style: GVTypography.title(context)),
                  const SizedBox(height: 6),
                  Text(
                    current.estimatedDurationFormatted,
                    style: GVTypography.small(context),
                  ),
                  const SizedBox(height: 24),

                  // ── Player card ───────────────────────────────────────────
                  _PlayerCard(
                    player: _player,
                    status: current.audioStatus,
                    fmt: _fmt,
                    onPrevious: _currentIndex > 0 ? _previous : null,
                    onSeekBack: _seekBack,
                    onSeekForward: _seekForward,
                    onNext: _currentIndex + 1 < _articles.length ? _advance : null,
                  ),

                  // ── Transcript ────────────────────────────────────────────
                  if (_showTranscript) ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: GVColors.bgPrimary(context),
                        border: Border.all(color: GVColors.borderTertiary(context), width: 0.5),
                        borderRadius: BorderRadius.circular(GVRadius.lg),
                      ),
                      child: Text(current.content, style: GVTypography.reader(context)),
                    ),
                  ],

                  // ── Up next ───────────────────────────────────────────────
                  if (upNext.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Up Next', style: GVTypography.heading(context)),
                    const SizedBox(height: 8),
                    ...upNext.take(5).map((a) => _UpNextTile(article: a)),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Player card ───────────────────────────────────────────────────────────────

class _PlayerCard extends StatelessWidget {
  final AudioPlayer player;
  final ArticleAudioStatus status;
  final String Function(Duration) fmt;
  final VoidCallback? onPrevious;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;
  final VoidCallback? onNext;

  const _PlayerCard({
    required this.player,
    required this.status,
    required this.fmt,
    required this.onPrevious,
    required this.onSeekBack,
    required this.onSeekForward,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: GVColors.bgPrimary(context),
        border: Border.all(color: GVColors.borderTertiary(context), width: 0.5),
        borderRadius: BorderRadius.circular(GVRadius.xl),
      ),
      child: Column(
        children: [
          // Loading / failed state
          if (status == ArticleAudioStatus.loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: GVColors.accent(context)),
                  ),
                  const SizedBox(width: 10),
                  Text('Generating audio...', style: GVTypography.small(context)),
                ],
              ),
            )
          else if (status == ArticleAudioStatus.failed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 16, color: GVColors.danger(context)),
                  const SizedBox(width: 8),
                  Text('Audio generation failed', style: GVTypography.small(context)),
                ],
              ),
            ),

          // Progress bar
          StreamBuilder<Duration>(
            stream: player.positionStream,
            builder: (_, posSnap) {
              final pos = posSnap.data ?? Duration.zero;
              return StreamBuilder<Duration?>(
                stream: player.durationStream,
                builder: (_, durSnap) {
                  final dur = durSnap.data ?? Duration.zero;
                  final progress = dur.inMilliseconds > 0
                      ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                      : 0.0;
                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderThemeData(
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          trackHeight: 3,
                          activeTrackColor: GVColors.accent(context),
                          inactiveTrackColor: GVColors.bgTertiary(context),
                          thumbColor: GVColors.accent(context),
                          overlayColor: GVColors.accent(context).withOpacity(0.2),
                        ),
                        child: Slider(
                          value: progress,
                          onChanged: (v) => player.seek(
                            Duration(milliseconds: (v * dur.inMilliseconds).round()),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(fmt(pos), style: GVTypography.label(context)),
                            Text(fmt(dur), style: GVTypography.label(context)),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),

          const SizedBox(height: 16),

          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(Icons.skip_previous_rounded,
                    color: onPrevious != null
                        ? GVColors.textPrimary(context)
                        : GVColors.textTertiary(context)),
                iconSize: 28,
                onPressed: onPrevious,
              ),
              IconButton(
                icon: Icon(Icons.replay_10_rounded, color: GVColors.textPrimary(context)),
                iconSize: 28,
                onPressed: onSeekBack,
              ),
              StreamBuilder<PlayerState>(
                stream: player.playerStateStream,
                builder: (_, snap) {
                  final playing = snap.data?.playing ?? false;
                  final loading = snap.data?.processingState == ProcessingState.loading ||
                      snap.data?.processingState == ProcessingState.buffering ||
                      status == ArticleAudioStatus.loading;
                  return Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: GVColors.accent(context),
                      shape: BoxShape.circle,
                    ),
                    child: loading
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : IconButton(
                            icon: Icon(
                              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                            ),
                            iconSize: 28,
                            onPressed: () =>
                                playing ? player.pause() : player.play(),
                          ),
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.forward_30_rounded, color: GVColors.textPrimary(context)),
                iconSize: 28,
                onPressed: onSeekForward,
              ),
              IconButton(
                icon: Icon(Icons.skip_next_rounded,
                    color: onNext != null
                        ? GVColors.textPrimary(context)
                        : GVColors.textTertiary(context)),
                iconSize: 28,
                onPressed: onNext,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Up Next tile ──────────────────────────────────────────────────────────────

class _UpNextTile extends StatelessWidget {
  final NewspaperArticle article;
  const _UpNextTile({required this.article});

  @override
  Widget build(BuildContext context) {
    final catColor = GVCategory.color(article.category);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GVColors.bgPrimary(context),
        border: Border.all(color: GVColors.borderTertiary(context), width: 0.5),
        borderRadius: BorderRadius.circular(GVRadius.md),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: catColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  article.title,
                  style: GVTypography.body(context).copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  article.estimatedDurationFormatted,
                  style: GVTypography.label(context),
                ),
              ],
            ),
          ),
          if (article.audioStatus == ArticleAudioStatus.loading)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: GVColors.accent(context)),
            ),
          if (article.audioStatus == ArticleAudioStatus.ready)
            Icon(Icons.check_circle_rounded, size: 14, color: GVColors.success(context)),
        ],
      ),
    );
  }
}
