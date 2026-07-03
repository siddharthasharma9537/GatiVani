import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../l10n/strings.dart';
import '../services/playback_service.dart';
import '../services/settings_provider.dart';
import '../services/edition_store.dart';
import '../services/news_feed_service.dart';
import '../design/components/gati_chip.dart';
import '../design/components/gati_pill.dart';
import '../design/components/gati_play_button.dart';
import '../design/components/gati_row.dart';
import '../design/components/gati_seek_bar.dart';
import '../design/components/gati_states.dart';
import '../design/components/gati_wordmark.dart';
import '../design/tokens.dart';
import '../design/section_colors.dart';
import '../models/newspaper_article.dart';
import '../widgets/assistant_sheet.dart';

/// Full-screen player: the article text scrolls like lyrics with the current
/// WORD highlighted as the audio plays.
///
/// Timing model: Gemini/Sarvam TTS don't return word timestamps, and Sarvam's
/// batch STT alignment came back empty — so true forced alignment isn't
/// available. Instead each word is given a slice of the real audio duration
/// weighted by its length (longer words take proportionally longer). Not
/// frame-perfect, but a smooth, deterministic word-by-word sweep. Tap any line
/// to seek.
class LyricsPlayerScreen extends StatefulWidget {
  const LyricsPlayerScreen({super.key});
  @override
  State<LyricsPlayerScreen> createState() => _LyricsPlayerScreenState();
}

class _LyricsPlayerScreenState extends State<LyricsPlayerScreen>
    with TickerProviderStateMixin {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  int _lastScrolled = -1;
  bool _dismissing = false;
  bool _downloading = false;
  // Pull-down-to-dismiss: the whole page follows the finger (Claude-iOS-like
  // sheet feel), springs back under the threshold, pops past it — the route's
  // slide transition carries it the rest of the way down.
  double _slide = 0;
  double _settleFrom = 0;
  late final AnimationController _settle =
      AnimationController(vsync: this, duration: GatiMotion.madhyama)
        ..addListener(() => setState(() => _slide =
            _settleFrom * (1 - Curves.easeOutCubic.transform(_settle.value))));
  // 0 = album-art player; 1 = lyrics open (art collapsed into the top strip).
  // One value drives the whole coordinated transition (YouTube-Music style).
  late final AnimationController _lyrics = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 360));

  // Mann Ki Baat playlist mode: which year's chip is selected (null until
  // first built, then defaults to the newest episode's year) and which row
  // is mid-resolve (shows a small spinner in its place).
  int? _mkbYear;
  int? _mkbResolvingIndex;

  void _slideUpdate(DragUpdateDetails d) {
    _settle.stop();
    setState(
        () => _slide = (_slide + (d.primaryDelta ?? 0)).clamp(0.0, 1000.0));
  }

  void _slideEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if ((_slide > 130 || v > 350) && !_dismissing) {
      _dismissing = true;
      if (context.canPop()) context.pop();
      return;
    }
    _settleFrom = _slide;
    _settle.forward(from: 0);
  }

  @override
  void dispose() {
    _lyrics.dispose();
    _settle.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Per-article cache, recomputed when the playing article changes.
  String _forId = '';
  List<List<String>> _lines = []; // sentences → words
  List<int> _lineFirstWord = []; // global index of each line's first word
  List<double> _wordStart = []; // fractional start [0..1) per global word
  int _wordCount = 0;

  void _prepare(String body) {
    final sentences = body
        .replaceAll('\n', ' ')
        .split(RegExp(r'(?<=[.?!।॥…])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (sentences.isEmpty) sentences.add(body);

    _lines = sentences
        .map((s) => s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList())
        .toList();

    // Per-word weight ≈ how long it's spoken. Char count + a pause budget after
    // punctuation (TTS pauses at "." and "," — pauses belong to no word, so
    // uncounted they make the highlight run ahead). Line 0 is the headline,
    // which TTS reads slowly and follows with a long pause before the body — so
    // it gets a speed multiplier and a big trailing pause (without this the
    // highlight jumps a whole line ahead during the title).
    final sentenceEnd = RegExp(r'[.?!।॥…]$');
    final clauseEnd = RegExp(r'[,;:]$');
    final weights = <double>[];
    _lineFirstWord = [];
    for (var li = 0; li < _lines.length; li++) {
      final line = _lines[li];
      final isHeadline = li == 0;
      _lineFirstWord.add(weights.length);
      for (var wi = 0; wi < line.length; wi++) {
        final w = line[wi];
        var wt = w.runes.length.clamp(1, 30).toDouble();
        if (isHeadline) wt *= 1.7; // titles are spoken slower & emphasized
        if (sentenceEnd.hasMatch(w)) {
          wt += 10; // ~a long pause
        } else if (clauseEnd.hasMatch(w)) {
          wt += 4; // ~a short pause
        }
        if (isHeadline && wi == line.length - 1) {
          wt += 20; // the pause between the headline and the body
        }
        weights.add(wt);
      }
    }
    _wordCount = weights.length;
    final total = weights.fold<double>(0, (a, b) => a + b);
    _wordStart = List.filled(_wordCount, 0);
    var acc = 0.0;
    for (var i = 0; i < _wordCount; i++) {
      _wordStart[i] = total == 0 ? 0 : acc / total;
      acc += weights[i];
    }
    _keys.clear();
    _lastScrolled = -1;
  }

  int _activeWord(double frac) {
    // last word whose start <= frac
    var lo = 0, hi = _wordCount - 1, ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_wordStart[mid] <= frac) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  int _lineOf(int word) {
    for (var i = _lineFirstWord.length - 1; i >= 0; i--) {
      if (word >= _lineFirstWord[i]) return i;
    }
    return 0;
  }

  void _autoScroll(int line) {
    if (line == _lastScrolled) return;
    _lastScrolled = line;
    final ctx = _keys[line]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 350),
          alignment: 0.35,
          curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = PlaybackService.i;
    return Scaffold(
      backgroundColor: Gati.ink,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: p,
          builder: (context, _) {
            final a = p.current;
            if (a == null) {
              return const Center(
                  child: Text('Nothing playing',
                      style: TextStyle(color: Gati.muted)));
            }
            // In a briefing session the audio is the short version, so the
            // lyrics must use briefingText too (key includes the mode).
            final key = '${a.id}:${p.brief}:${a.summaryText != null}';
            if (key != _forId) {
              _forId = key;
              _prepare(p.brief
                  ? (a.summaryText ?? a.briefingText)
                  : a.spokenText);
            }
            final dur = p.duration.inMilliseconds;
            // TTS clips usually open with ~0.4s of silence before the first word,
            // which otherwise makes the highlight lead from the very start.
            const leadMs = 400;
            final adjPos = (p.position.inMilliseconds - leadMs).clamp(0, dur);
            final frac = dur == 0 ? 0.0 : (adjPos / dur).clamp(0.0, 1.0);
            final activeWord = _wordCount == 0 ? 0 : _activeWord(frac);
            final activeLine = _lineOf(activeWord);
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _autoScroll(activeLine));

            return LayoutBuilder(builder: (context, c) {
              // Color-sync: tint the player background with the playing
              // section's hue (the album-art cover's colour), like YouTube
              // Music deriving the player colour from the art.
              final hue = sectionRamp(a.category, dark: false)[1];
              final bgTint = Color.lerp(Gati.inkDeep, hue, 0.22)!;

              // No more separate draggable "Your Queue" sheet — the queue
              // (or the Mann Ki Baat year-chip archive) is always visible
              // below the transport, as part of the normal layout; see
              // _stage. Only a plain pull-down-to-dismiss on the header
              // remains from what used to be a combined drag gesture.
              // Whole-body pull-down: the page translates with the finger.
              // Lists inside (queue, lyrics) still win their own vertical
              // drags in the gesture arena, so scrolling is unaffected.
              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: _slideUpdate,
                onVerticalDragEnd: _slideEnd,
                child: Transform.translate(
                  offset: Offset(0, _slide),
                  child: ClipRRect(
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(_slide > 0 ? 20 : 0)),
                    child: Stack(fit: StackFit.expand, children: [
                      Positioned.fill(child: ColoredBox(color: bgTint)),
                      Column(children: [
                        _header(context, a),
                        Expanded(
                          child: _stage(
                              context, p, a, activeLine, activeWord, dur),
                        ),
                      ]),
                    ]),
                  ),
                ),
              );
            });
          },
        ),
      ),
    );
  }

  // ── Coordinated player ⇄ lyrics stage (YouTube-Music style) ──────────────────
  // One value (_lyrics 0→1) drives it: the cover art morphs from the big centred
  // square into a small top-left thumbnail while the read-along rises from below.
  Widget _stage(BuildContext context, PlaybackService p, NewspaperArticle a,
      int activeLine, int activeWord, int dur) {
    final lang = context.read<SettingsProvider>().lang;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      // Width-based cap (not height-based) — the art used to grow with whatever
      // height Expanded happened to leave, pushing the meta+pills row down
      // and leaving dead space below it. A fixed, compact size keeps the
      // whole art+meta+pills block hugging the top regardless of screen
      // height, so there's real room left for the Next Up list below it.
      final side = (w - 64).clamp(0.0, 220.0);
      final big = Rect.fromLTWH((w - side) / 2, 6, side, side);
      const small = Rect.fromLTWH(2, 8, 46, 46);
      return AnimatedBuilder(
        animation: _lyrics,
        builder: (context, _) {
          final t = Curves.easeInOutCubic.transform(_lyrics.value);
          final rect = Rect.lerp(big, small, t)!;
          return Stack(clipBehavior: Clip.none, children: [
            // Read-along — fades + rises from below, clearing the top strip.
            if (t > 0.01)
              Positioned.fill(
                child: Opacity(
                  opacity: ((t - 0.25) / 0.75).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 48),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 62),
                      child:
                          _lyricsList(context, p, activeLine, activeWord, dur),
                    ),
                  ),
                ),
              ),
            // Meta (title + subtitle + pills), transport controls, and the
            // queue/archive list all flow together in one Column instead of
            // being separately-positioned pieces — Expanded on the list
            // gives it whatever's left below the pills and controls with no
            // pixel-estimated gaps. The whole block fades out as lyrics opens
            // (title/pills fade a touch faster so they clear the top strip).
            Positioned(
              top: big.bottom + 18,
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: t > 0.2,
                child: Column(children: [
                  Opacity(
                    opacity: (1 - t * 1.8).clamp(0.0, 1.0),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _playerMeta(context, a, lang),
                    ),
                  ),
                  Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0),
                    child: _controls(p),
                  ),
                  Expanded(
                    child: Opacity(
                      opacity: (1 - t).clamp(0.0, 1.0),
                      child: _inlineQueueSection(context, p, lang),
                    ),
                  ),
                ]),
              ),
            ),
            // Top strip (the collapsed mini-player): title + a play/pause button,
            // beside the small thumbnail. No full transport below in lyrics mode.
            Positioned(
              top: 8,
              height: 46,
              left: small.right + 12,
              right: 6,
              child: IgnorePointer(
                ignoring: t < 0.5,
                child: Opacity(
                  opacity: ((t - 0.4) / 0.6).clamp(0.0, 1.0),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(a.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Gati.onInk,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                          Text(sectionLabel(a.category, lang),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Gati.onInkMuted, fontSize: 11)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                          p.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Gati.onInk,
                          size: 28),
                      onPressed: p.toggle,
                    ),
                  ]),
                ),
              ),
            ),
            // Shared cover art — morphs big-centre → small top-left thumbnail.
            // (Not tappable: only the Read chip opens the lyrics.)
            Positioned.fromRect(
              rect: rect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18 - 10 * t),
                child: _coverWidget(a, lang),
              ),
            ),
            // Lyrics mode: swiping down on the top strip brings the player back
            // down (closes the lyrics). Translucent so the play button still taps.
            if (t > 0.5)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 60,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) > 180) _lyrics.reverse();
                  },
                ),
              ),
          ]);
        },
      );
    });
  }

  Widget _playerMeta(BuildContext context, NewspaperArticle a, String lang) {
    final mins = (a.estimatedDurationSeconds / 60).ceil();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(a.title,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Gati.onInk,
              fontSize: 19,
              fontWeight: FontWeight.w500,
              height: 1.3)),
      const SizedBox(height: 6),
      Text(
          '${sectionLabel(a.category, lang)} · p${a.page} · $mins ${tr(lang, 'min')}',
          style: const TextStyle(color: Gati.onInkMuted, fontSize: 12.5)),
      const SizedBox(height: 18),
      // Uniform pill row — identical pills, icon + label, single scrolling row.
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          GatiPill(
              icon: Icons.format_quote_rounded,
              label: tr(lang, 'read'),
              onTap: () => _lyrics.forward()),
          const SizedBox(width: 8),
          GatiPill(
              icon: Icons.shuffle_rounded,
              label: tr(lang, 'mix'),
              onTap: () => _mix(context, a)),
          const SizedBox(width: 8),
          GatiPill(
              icon: Icons.bookmark_border_rounded,
              label: tr(lang, 'save'),
              onTap: () => gatiSnack(context, tr(lang, 'save_soon'))),
          const SizedBox(width: 8),
          GatiPill(
              icon: Icons.download_outlined,
              label: tr(lang, 'download'),
              onTap: () => _download(context, a),
              busy: _downloading),
        ]),
      ),
    ]);
  }

  // Cover content sized to fill its rect (scales as one unit during the morph):
  // the real clipping when present, else the section-tinted cover.
  Widget _coverWidget(NewspaperArticle a, String lang) {
    if (a.hasImage) {
      return Image.network(a.imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _coverArt(a, lang));
    }
    return _coverArt(a, lang);
  }

  Widget _coverArt(NewspaperArticle a, String lang) {
    final r = sectionRamp(a.category, dark: true);
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: 300,
        height: 300,
        child: Container(
          color: r[0],
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GatiWordmark(
                  size: 14, color: r[2], lang: lang, animated: false),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.article_rounded,
                      color: Gati.accent, size: 46),
                  const SizedBox(height: 12),
                  Text(sectionLabel(a.category, lang),
                      style: TextStyle(
                          color: r[1],
                          fontSize: 30,
                          fontWeight: FontWeight.w600,
                          height: 1.1)),
                ],
              ),
              Text('p${a.page}', style: TextStyle(color: r[2], fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  // Read-along list (word-sync, tap-to-seek). Over-pulling the top closes lyrics.
  Widget _lyricsList(BuildContext context, PlaybackService p, int activeLine,
      int activeWord, int dur) {
    // Size by the CONTENT's script (Telugu articles under an English UI still
    // need the taller Telugu line-height), not the settings language.
    final script = GatiType.scriptOf(p.current?.title ?? '');
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels < -90 && _lyrics.value == 1.0) _lyrics.reverse();
        return false;
      },
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
          stops: [0.0, 0.06, 0.9, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          controller: _scroll,
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          itemCount: _lines.length,
          itemBuilder: (context, li) {
            final k = _keys.putIfAbsent(li, () => GlobalKey());
            final firstWord = _lineFirstWord[li];
            final isActiveLine = li == activeLine;
            final spans = <TextSpan>[];
            for (var ww = 0; ww < _lines[li].length; ww++) {
              final gi = firstWord + ww;
              final isActive = gi == activeWord;
              final isPast = gi < activeWord;
              spans.add(TextSpan(
                text: _lines[li][ww] + (ww == _lines[li].length - 1 ? '' : ' '),
                style: TextStyle(
                  color: isActive
                      ? Gati.pasupuGlow
                      : isPast
                          ? Gati.onInkPast
                          : Gati.onInkFuture,
                  fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                ),
              ));
            }
            return GestureDetector(
              key: k,
              onTap: () => p.seek(
                  Duration(milliseconds: (_wordStart[firstWord] * dur).round())),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:
                      isActiveLine ? Gati.pasupuTint : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: RichText(
                  text: TextSpan(
                      style: GatiType.lyrics(script), children: spans),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _mix(BuildContext context, NewspaperArticle a) {
    final lang = context.read<SettingsProvider>().lang;
    var related =
        EditionStore.i.forSection(a.category).where((x) => x.id != a.id).toList();
    if (related.isEmpty) {
      related =
          EditionStore.i.articles.where((x) => x.id != a.id).take(12).toList();
    }
    if (related.isEmpty) return;
    PlaybackService.i.addToQueue(related.take(12));
    gatiSnack(context, tr(lang, 'mix_added'));
  }

  Future<void> _download(BuildContext context, NewspaperArticle a) async {
    final lang = context.read<SettingsProvider>().lang;
    if (_downloading) return;
    setState(() => _downloading = true);
    final ok = await PlaybackService.i.preload(a);
    if (!mounted) return;
    setState(() => _downloading = false);
    gatiSnack(context, tr(lang, ok ? 'downloaded' : 'download_failed'));
  }

  // ── Queue / Mann Ki Baat archive — always visible, no more separate sheet ──
  // Two modes: the Mann Ki Baat archive (opened only from its Podcast tile)
  // shows year chips over the full episode list; everything else keeps the
  // normal up-next queue, with a "Related articles" strip above it.
  Widget _inlineQueueSection(BuildContext context, PlaybackService p, String lang) {
    final q = p.queue;
    final isMkb =
        q.isNotEmpty && q.every((a) => a.documentType == 'mkb_episode');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
        child: Text(
            tr(lang, isMkb ? 'mkb_playlist_title' : 'your_queue'),
            style: const TextStyle(
                color: Gati.onInk, fontSize: 15, fontWeight: FontWeight.w500)),
      ),
      if (isMkb)
        _mkbYearChips(q)
      else
        _relatedArticlesStrip(context, p, lang),
      Expanded(
        child: q.isEmpty
            ? GatiEmpty(message: tr(lang, 'queue_empty'))
            : isMkb
                ? _mkbEpisodeList(context, p, q)
                : _queueList(context, p, q, lang),
      ),
    ]);
  }

  // Normal "Your Queue" list — unchanged behavior, tap to jump to that track.
  Widget _queueList(BuildContext context, PlaybackService p,
      List<NewspaperArticle> q, String lang) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: q.length,
      itemBuilder: (context, i) {
        final art = q[i];
        final isCurrent = i == p.index;
        final r = sectionRamp(art.category, dark: true);
        final mins = (art.estimatedDurationSeconds / 60).ceil();
        return GatiRow(
          onTap: () => p.playAt(i),
          current: isCurrent,
          title: art.title,
          subtitle:
              '${sectionLabel(art.category, lang)} · $mins ${tr(lang, 'min')}',
          leading: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: r[0], borderRadius: BorderRadius.circular(8)),
            child: Icon(
                isCurrent ? Icons.equalizer_rounded : Icons.article_rounded,
                color: isCurrent ? Gati.accent : Gati.onInkMuted,
                size: isCurrent ? 20 : 18),
          ),
          trailing: const Icon(Icons.drag_handle_rounded,
              color: Gati.onInkTrack, size: 22),
        );
      },
    );
  }

  // "Related articles" — other Latest-stories articles from the same
  // publisher as whatever's currently playing (only when the current track
  // actually came from a web article; cricket/podcasts/GatiVani Take don't
  // have a comparison pool). Tapping one queues it as Play Next rather than
  // interrupting playback, per the "user selected articles to play next in
  // Your Queue" behavior.
  List<WebArticle> _relatedFor(NewspaperArticle current) {
    final pool = ReaderStore.i.all;
    if (pool.isEmpty) return const [];
    final match = pool.where((w) => w.id == current.id);
    if (match.isEmpty) return const [];
    final source = match.first.source;
    return pool
        .where((w) => w.source == source && w.id != current.id)
        .take(8)
        .toList();
  }

  Widget _relatedArticlesStrip(
      BuildContext context, PlaybackService p, String lang) {
    final current = p.current;
    if (current == null) return const SizedBox.shrink();
    final related = _relatedFor(current);
    if (related.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(tr(lang, 'related_articles'),
            style: const TextStyle(
                color: Gati.onInkMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ),
      SizedBox(
        height: 92,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: related.length,
          itemBuilder: (context, i) {
            final w = related[i];
            final r = sectionRamp(w.source, dark: true);
            return GestureDetector(
              onTap: () {
                final art = NewspaperArticle(
                  id: w.id,
                  title: w.title,
                  content: w.body,
                  preview: w.summary,
                  category: w.source,
                  estimatedDurationSeconds:
                      NewspaperArticle.estimateDuration(w.body),
                  readingStyle: 'news_anchor',
                );
                PlaybackService.i.playNext([art]);
                gatiSnack(context, tr(lang, 'added_queue'));
              },
              child: Container(
                width: 200,
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: r[0], borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(w.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: r[1],
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            height: 1.25)),
                    Text(w.source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: r[2], fontSize: 11)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 4),
    ]);
  }

  // ── Mann Ki Baat playlist mode ───────────────────────────────────────────
  // Scrollable year chips, present year on the left extending right to the
  // past. Selecting one filters the (already recent→oldest) episode list
  // below to just that year.
  Widget _mkbYearChips(List<NewspaperArticle> q) {
    final years = <int>[];
    for (final a in q) {
      final y = _yearOf(a.title);
      if (y != null && !years.contains(y)) years.add(y);
    }
    if (years.isEmpty) return const SizedBox.shrink();
    _mkbYear ??= years.first;
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: years.length,
        itemBuilder: (context, i) {
          final y = years[i];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GatiChip(
              label: '$y',
              selected: y == _mkbYear,
              onTap: () => setState(() => _mkbYear = y),
            ),
          );
        },
      ),
    );
  }

  // Title is always "Mann Ki Baat — Part-N, Dth Month YYYY" — the year is
  // the last 4-digit run, cheaper than threading a separate date field
  // through NewspaperArticle just for this one screen.
  int? _yearOf(String title) {
    final m = RegExp(r'(\d{4})\s*$').firstMatch(title.trim());
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  Widget _mkbEpisodeList(
      BuildContext context, PlaybackService p, List<NewspaperArticle> q) {
    final year = _mkbYear;
    final indices = [
      for (var i = 0; i < q.length; i++)
        if (year == null || _yearOf(q[i].title) == year) i,
    ];
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: indices.length,
      itemBuilder: (context, row) {
        final i = indices[row];
        final art = q[i];
        final isCurrent = i == p.index;
        final resolving = i == _mkbResolvingIndex;
        return GatiRow(
          onTap: resolving
              ? null
              : () async {
                  setState(() => _mkbResolvingIndex = i);
                  await playMkbQueueEntry(i);
                  if (mounted) setState(() => _mkbResolvingIndex = null);
                },
          current: isCurrent,
          title: art.title,
          titleMaxLines: 2,
          leading: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: Gati.accentSoft, shape: BoxShape.circle),
            child: resolving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Gati.accent))
                : Icon(
                    isCurrent ? Icons.equalizer_rounded : Icons.mic_rounded,
                    color: isCurrent ? Gati.accent : Gati.accentText,
                    size: 18),
          ),
        );
      },
    );
  }

  void _openSleepSheet(BuildContext context) {
    final lang = context.read<SettingsProvider>().lang;
    final p = PlaybackService.i;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Gati.ink,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        Widget row(String label, VoidCallback onTap, {bool selected = false}) =>
            ListTile(
              title: Text(label,
                  style: TextStyle(
                      color: selected ? Gati.pasupuGlow : Gati.onInk,
                      fontSize: 15)),
              trailing: selected
                  ? const Icon(Icons.check_rounded, color: Gati.pasupu, size: 20)
                  : null,
              onTap: () {
                onTap();
                Navigator.pop(ctx);
              },
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(tr(lang, 'sleep_timer'),
                    style: const TextStyle(
                        color: Gati.onInkMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ),
            ),
            row(tr(lang, 'sleep_off'), p.cancelSleep, selected: !p.sleepActive),
            for (final m in [15, 30, 45, 60])
              row('$m ${tr(lang, 'min')}',
                  () => p.setSleepTimer(Duration(minutes: m))),
            row(tr(lang, 'sleep_end'), p.setSleepAtTrackEnd,
                selected: p.sleepAtTrackEnd),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
  }

  Widget _header(BuildContext context, dynamic a) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, color: Gati.onInkMuted),
          onPressed: () => context.pop(),
        ),
        Expanded(
          child: Text('${a.category} · p${a.page}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Gati.onInkMuted, fontSize: 12)),
        ),
        IconButton(
          icon: Icon(
              PlaybackService.i.sleepActive
                  ? Icons.bedtime
                  : Icons.bedtime_outlined,
              color: PlaybackService.i.sleepActive
                  ? Gati.pasupu
                  : Gati.onInkMuted,
              size: 20),
          tooltip: 'Sleep timer',
          onPressed: () => _openSleepSheet(context),
        ),
        IconButton(
          icon: const Icon(Icons.graphic_eq, color: Gati.pasupu, size: 20),
          tooltip: 'Ask Vāni',
          onPressed: () => AssistantSheet.open(context, a.id, a.title,
              articleText: a.content),
        ),
      ]),
    );
  }

  Widget _controls(PlaybackService p) {
    final dur = p.duration;
    final pos = p.position;
    String fmt(Duration d) =>
        '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(children: [
        GatiSeekBar(position: pos, duration: dur, onSeek: p.seek),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(fmt(pos), style: const TextStyle(color: Gati.onInkPast, fontSize: 11)),
          Text(fmt(dur), style: const TextStyle(color: Gati.onInkPast, fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        // Transport stays centered (prev · −15s · play · +15s · next); the speed
        // chip rides the right edge so it's not stacked above the play button.
        Stack(alignment: Alignment.center, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              icon: const Icon(Icons.skip_previous, color: Gati.onInkFuture, size: 26),
              onPressed: p.previous,
            ),
            const SizedBox(width: 4),
            _seekBtn(p, -15),
            const SizedBox(width: 8),
            GatiPlayButton(
              onTap: p.toggle,
              playing: p.isPlaying,
              loading: p.loading,
            ),
            const SizedBox(width: 8),
            _seekBtn(p, 15),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.skip_next, color: Gati.onInkFuture, size: 26),
              onPressed: p.next,
            ),
          ]),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {
                const steps = [1.0, 1.25, 1.5, 2.0, 0.75];
                p.setSpeed(steps[(steps.indexOf(p.speed) + 1) % steps.length]);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    border: Border.all(color: Gati.onInkTrack),
                    borderRadius: BorderRadius.circular(12)),
                child: Text('${_fmtSpeed(p.speed)}×',
                    style: const TextStyle(
                        color: Gati.onInkFuture,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 2),
        // Playback modes: shuffle · repeat (off → all → one) · mute.
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _modeBtn(Icons.shuffle_rounded, p.shuffle, p.toggleShuffle),
          const SizedBox(width: 22),
          _modeBtn(
              p.repeatMode == QueueRepeat.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              p.repeatMode != QueueRepeat.off,
              p.cycleRepeat),
          const SizedBox(width: 22),
          _modeBtn(
              p.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              p.muted,
              p.toggleMute),
        ]),
      ]),
    );
  }

  Widget _modeBtn(IconData icon, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.translucent,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon,
              size: 20, color: active ? Gati.pasupu : Gati.onInkFuture),
        ),
      );

  Widget _seekBtn(PlaybackService p, int secs) {
    final dur = p.duration.inMilliseconds;
    return GestureDetector(
      onTap: () => p.seek(Duration(
          milliseconds: (p.position.inMilliseconds + secs * 1000).clamp(0, dur))),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(alignment: Alignment.center, children: [
          Icon(secs < 0 ? Icons.replay : Icons.refresh,
              color: Gati.onInkFuture, size: 30),
          Text('${secs.abs()}',
              style: const TextStyle(
                  color: Gati.onInkFuture, fontSize: 9, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  String _fmtSpeed(double s) {
    final r = (s * 100).round() / 100;
    return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString();
  }
}
