import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../l10n/strings.dart';
import '../services/playback_service.dart';
import '../services/settings_provider.dart';
import '../services/edition_store.dart';
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
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  int _lastScrolled = -1;
  bool _dismissing = false;
  double _dragDy = 0; // accumulated pull on the header → minimize
  bool _downloading = false;
  // 0 = album-art player; 1 = lyrics open (art collapsed into the top strip).
  // One value drives the whole coordinated transition (YouTube-Music style).
  late final AnimationController _lyrics = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 360));

  @override
  void dispose() {
    _lyrics.dispose();
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

            return Column(children: [
              // Pull the header down to minimize back to the mini-player (audio
              // keeps playing) — on a drag of ≳70px or a downward flick.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => _dragDy = 0,
                onVerticalDragUpdate: (d) => _dragDy += d.primaryDelta ?? 0,
                onVerticalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if ((_dragDy > 70 || v > 250) && !_dismissing) {
                    _dismissing = true;
                    if (context.canPop()) context.pop();
                  }
                },
                child: _header(context, a),
              ),
              Expanded(
                child: _stage(context, p, a, activeLine, activeWord, dur),
              ),
              _controls(p),
            ]);
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
      final w = c.maxWidth, h = c.maxHeight;
      final side = (w - 48).clamp(0.0, h * 0.46);
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
            // Player meta (title + meta + pills) under the big art — fades out.
            Positioned(
              top: big.bottom + 18,
              left: 24,
              right: 24,
              child: IgnorePointer(
                ignoring: t > 0.2,
                child: Opacity(
                  opacity: (1 - t * 1.8).clamp(0.0, 1.0),
                  child: _playerMeta(context, a, lang),
                ),
              ),
            ),
            // Top strip title + close — fades in beside the small thumbnail.
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
                      icon: const Icon(Icons.close_rounded,
                          color: Gati.onInkMuted, size: 20),
                      onPressed: () => _lyrics.reverse(),
                    ),
                  ]),
                ),
              ),
            ),
            // Shared cover art — morphs big-centre → small top-left thumbnail.
            // Tapping it toggles: collapse the lyrics when open, expand when not.
            Positioned.fromRect(
              rect: rect,
              child: GestureDetector(
                onTap: () =>
                    _lyrics.value > 0.5 ? _lyrics.reverse() : _lyrics.forward(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18 - 10 * t),
                  child: _coverWidget(a, lang),
                ),
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
          _pill(Icons.format_quote_rounded, tr(lang, 'read'),
              () => _lyrics.forward()),
          const SizedBox(width: 8),
          _pill(Icons.shuffle_rounded, tr(lang, 'mix'), () => _mix(context, a)),
          const SizedBox(width: 8),
          _pill(Icons.bookmark_border_rounded, tr(lang, 'save'),
              () => _snack(context, tr(lang, 'save_soon'))),
          const SizedBox(width: 8),
          _pill(Icons.download_outlined, tr(lang, 'download'),
              () => _download(context, a),
              busy: _downloading),
        ]),
      ),
    ]);
  }

  Widget _pill(IconData icon, String label, VoidCallback onTap,
      {bool busy = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
            color: const Color(0xFF35322B),
            borderRadius: BorderRadius.circular(22)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Gati.accent))
              : Icon(icon, size: 16, color: Gati.onInk),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Gati.onInk,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
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
              Text('Gativani',
                  style:
                      TextStyle(color: r[2], fontSize: 14, letterSpacing: 0.5)),
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
                      ? Gati.accent
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
                      isActiveLine ? const Color(0x1AD85A30) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: RichText(
                  text: TextSpan(
                      style: const TextStyle(fontSize: 18, height: 1.6),
                      children: spans),
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
    _snack(context, tr(lang, 'mix_added'));
  }

  Future<void> _download(BuildContext context, NewspaperArticle a) async {
    final lang = context.read<SettingsProvider>().lang;
    if (_downloading) return;
    setState(() => _downloading = true);
    final ok = await PlaybackService.i.preload(a);
    if (!mounted) return;
    setState(() => _downloading = false);
    _snack(context, tr(lang, ok ? 'downloaded' : 'download_failed'));
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
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
                      color: selected ? Gati.accent : Gati.onInk,
                      fontSize: 15)),
              trailing: selected
                  ? const Icon(Icons.check_rounded, color: Gati.accent, size: 20)
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
                  ? Gati.accent
                  : Gati.onInkMuted,
              size: 20),
          tooltip: 'Sleep timer',
          onPressed: () => _openSleepSheet(context),
        ),
        IconButton(
          icon: const Icon(Icons.auto_awesome, color: Gati.accent, size: 20),
          tooltip: 'Ask about this',
          onPressed: () => AssistantSheet.open(context, a.id, a.title),
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
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            activeTrackColor: Gati.accent,
            inactiveTrackColor: Gati.onInkTrack,
            thumbColor: Gati.accent,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: dur.inMilliseconds == 0
                ? 0
                : pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble(),
            max: dur.inMilliseconds == 0 ? 1 : dur.inMilliseconds.toDouble(),
            onChanged: (v) => p.seek(Duration(milliseconds: v.round())),
          ),
        ),
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
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: Gati.accent, shape: BoxShape.circle),
              child: IconButton(
                icon: p.loading
                    ? const Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Gati.onInk))
                    : Icon(p.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Gati.onInk, size: 32),
                onPressed: p.toggle,
              ),
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
      ]),
    );
  }

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
