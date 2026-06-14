import 'package:flutter/material.dart';
import '../services/playback_service.dart';
import '../widgets/mini_player.dart';

/// Full-screen player: the article text scrolls like lyrics, with the current
/// sentence highlighted as the audio plays. Tap a sentence to seek to it.
class LyricsPlayerScreen extends StatefulWidget {
  const LyricsPlayerScreen({super.key});
  @override
  State<LyricsPlayerScreen> createState() => _LyricsPlayerScreenState();
}

class _LyricsPlayerScreenState extends State<LyricsPlayerScreen> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  int _lastActive = -1;
  String _forId = '';

  List<String> _sentences(String body) {
    final parts = body
        .replaceAll('\n', ' ')
        .split(RegExp(r'(?<=[.?!।॥…])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? [body] : parts;
  }

  void _autoScroll(int active) {
    if (active == _lastActive) return;
    _lastActive = active;
    final k = _keys[active];
    final ctx = k?.currentContext;
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
      backgroundColor: kInk,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: p,
          builder: (context, _) {
            final a = p.current;
            if (a == null) {
              return const Center(
                  child: Text('Nothing playing',
                      style: TextStyle(color: kMuted)));
            }
            if (a.id != _forId) {
              _forId = a.id;
              _lastActive = -1;
              _keys.clear();
            }
            final sentences = _sentences(a.content.isNotEmpty ? a.content : a.preview);
            final dur = p.duration.inMilliseconds;
            final frac = dur == 0 ? 0.0 : p.position.inMilliseconds / dur;
            final active = (frac * sentences.length).floor().clamp(0, sentences.length - 1);
            WidgetsBinding.instance.addPostFrameCallback((_) => _autoScroll(active));

            return Column(children: [
              // header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down,
                        color: Color(0xFFB4B2A9)),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  Expanded(
                    child: Text('${a.category} · p${a.page}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFFB4B2A9), fontSize: 12)),
                  ),
                  const SizedBox(width: 40),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(a.title,
                    style: const TextStyle(
                        color: kPaper, fontSize: 20, fontWeight: FontWeight.w500)),
              ),
              // lyrics
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: sentences.length,
                  itemBuilder: (context, i) {
                    final k = _keys.putIfAbsent(i, () => GlobalKey());
                    final isActive = i == active;
                    final isPast = i < active;
                    return GestureDetector(
                      key: k,
                      onTap: () => p.seek(Duration(
                          milliseconds: ((i / sentences.length) * dur).round())),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Text(
                          sentences[i],
                          style: TextStyle(
                            fontSize: 18,
                            height: 1.6,
                            fontWeight:
                                isActive ? FontWeight.w500 : FontWeight.w400,
                            color: isActive
                                ? kAccent
                                : isPast
                                    ? const Color(0xFF8A8884)
                                    : const Color(0xFFCFCDC5),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // controls
              _controls(p),
            ]);
          },
        ),
      ),
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
            activeTrackColor: kAccent,
            inactiveTrackColor: const Color(0xFF5F5E5A),
            thumbColor: kAccent,
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
          Text(fmt(pos),
              style: const TextStyle(color: Color(0xFF8A8884), fontSize: 11)),
          Text(fmt(dur),
              style: const TextStyle(color: Color(0xFF8A8884), fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            icon: const Icon(Icons.skip_previous, color: Color(0xFFCFCDC5), size: 30),
            onPressed: p.previous,
          ),
          const SizedBox(width: 16),
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
            child: IconButton(
              icon: p.loading
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kPaper))
                  : Icon(p.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: kPaper, size: 32),
              onPressed: p.toggle,
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.skip_next, color: Color(0xFFCFCDC5), size: 30),
            onPressed: p.next,
          ),
        ]),
      ]),
    );
  }
}
