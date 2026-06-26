import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../l10n/strings.dart';
import '../services/playback_service.dart';
import '../services/settings_provider.dart';
import '../design/tokens.dart';
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

class _LyricsPlayerScreenState extends State<LyricsPlayerScreen> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  int _lastScrolled = -1;
  bool _dismissing = false;

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
            final key = '${a.id}:${p.brief}';
            if (key != _forId) {
              _forId = key;
              _prepare(p.brief ? a.briefingText : a.spokenText);
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
              _header(context, a),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(a.title,
                    style: const TextStyle(
                        color: Gati.onInk, fontSize: 20, fontWeight: FontWeight.w500)),
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  // Pull the lyrics down past the top to minimize the player —
                  // the iOS now-playing gesture, without fighting normal scroll.
                  onNotification: (n) {
                    if (n.metrics.pixels < -90 && !_dismissing) {
                      _dismissing = true;
                      if (context.canPop()) context.pop();
                    }
                    return false;
                  },
                  child: ShaderMask(
                  // Soft fade at top and bottom so lines glide under the title
                  // and controls — premium, Apple-Music-like.
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
                      for (var w = 0; w < _lines[li].length; w++) {
                        final gi = firstWord + w;
                        final isActive = gi == activeWord;
                        final isPast = gi < activeWord;
                        spans.add(TextSpan(
                          text: _lines[li][w] + (w == _lines[li].length - 1 ? '' : ' '),
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
                        onTap: () => p.seek(Duration(
                            milliseconds: (_wordStart[firstWord] * dur).round())),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isActiveLine
                                ? const Color(0x1AD85A30) // accent @ ~10%
                                : Colors.transparent,
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
              ),
              ),
              _controls(p),
            ]);
          },
        ),
      ),
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
          // speed cycle — small, where the eye already is (the time row)
          GestureDetector(
            onTap: () {
              const steps = [1.0, 1.25, 1.5, 2.0, 0.75];
              p.setSpeed(steps[(steps.indexOf(p.speed) + 1) % steps.length]);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                  border: Border.all(color: Gati.onInkTrack),
                  borderRadius: BorderRadius.circular(12)),
              child: Text('${_fmtSpeed(p.speed)}×',
                  style: const TextStyle(
                      color: Gati.onInkFuture, fontSize: 11.5, fontWeight: FontWeight.w500)),
            ),
          ),
          Text(fmt(dur), style: const TextStyle(color: Gati.onInkPast, fontSize: 11)),
        ]),
        const SizedBox(height: 10),
        // Transport: prev article · −15s · play · +15s · next article
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
