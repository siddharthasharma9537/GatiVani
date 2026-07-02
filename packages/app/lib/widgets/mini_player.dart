import 'package:flutter/material.dart';
import '../services/playback_service.dart';
// Re-export the design tokens so screens that `import 'mini_player.dart'`
// keep resolving kInk/kPaper/kAccent/kMuted from the single source of truth.
import '../design/tokens.dart';
export '../design/tokens.dart';

/// Persistent bottom now-playing bar. Audio keeps playing while the user
/// browses. Scrub the slider to seek; ±15s and prev/next mirror the full
/// player. Swipe up to expand, swipe down to stop and dismiss.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, this.onExpand});
  final VoidCallback? onExpand;

  static String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = PlaybackService.i;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final a = p.current;
        if (a == null) return const SizedBox.shrink();
        // A synth/playback failure (e.g. TTS quota 429) used to leave the bar
        // stuck silently at 0:00. Show a clear message + retry instead.
        if (p.error != null && !p.loading) {
          return _ErrorBar(title: a.title, error: p.error!, onRetry: p.retry);
        }
        final durMs = p.duration.inMilliseconds;
        final posMs =
            p.position.inMilliseconds.clamp(0, durMs == 0 ? 1 : durMs);
        return GestureDetector(
          onTap: onExpand,
          // Swipe up opens the full player; swipe down stops + dismisses.
          onVerticalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -100) {
              onExpand?.call();
            } else if (v > 100) {
              p.stop();
            }
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            decoration: BoxDecoration(
              color: kInk,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                  child: Text(a.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: kPaper,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ),
                const SizedBox(width: 8),
                Text('${_fmt(p.position)} / ${_fmt(p.duration)}',
                    style: const TextStyle(
                        color: Gati.onInkMuted, fontSize: 11)),
              ]),
              // Scrubbable progress.
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2.5,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: Gati.pasupu,
                  inactiveTrackColor: Gati.onInkTrack,
                  thumbColor: Gati.pasupu,
                ),
                child: Slider(
                  value: posMs.toDouble(),
                  max: durMs == 0 ? 1 : durMs.toDouble(),
                  onChanged: durMs == 0
                      ? null
                      : (v) => p.seek(Duration(milliseconds: v.round())),
                ),
              ),
              // Transport: prev · −15s · play/pause · +15s · next.
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36),
                  icon:
                      const Icon(Icons.skip_previous, color: kMuted, size: 24),
                  onPressed: p.previous,
                ),
                _seek(p, -15),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 44),
                  icon: p.loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Gati.pasupu))
                      : Icon(p.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: kPaper, size: 32),
                  onPressed: p.toggle,
                ),
                _seek(p, 15),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36),
                  icon: const Icon(Icons.skip_next, color: kMuted, size: 24),
                  onPressed: p.next,
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }

  // ±15s skip, with the seconds count overlaid on a circular-arrow icon.
  Widget _seek(PlaybackService p, int secs) {
    final durMs = p.duration.inMilliseconds;
    return GestureDetector(
      onTap: () => p.seek(Duration(
          milliseconds: (p.position.inMilliseconds + secs * 1000)
              .clamp(0, durMs == 0 ? 0 : durMs))),
      child: SizedBox(
        width: 42,
        height: 42,
        child: Stack(alignment: Alignment.center, children: [
          Icon(secs < 0 ? Icons.replay : Icons.refresh,
              color: kMuted, size: 26),
          Text('${secs.abs()}',
              style: const TextStyle(
                  color: kMuted, fontSize: 8, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// Shown in place of the transport bar when playback fails, so the user gets a
/// reason (and a retry) instead of a silent, stuck bar.
class _ErrorBar extends StatelessWidget {
  const _ErrorBar(
      {required this.title, required this.error, required this.onRetry});
  final String title;
  final String error;
  final VoidCallback onRetry;

  String get _message {
    final e = error.toLowerCase();
    if (e.contains('429') || e.contains('quota')) {
      return 'Audio limit reached — try again later';
    }
    if (e.contains('timeout') || e.contains('timed out')) {
      return 'Timed out — tap retry';
    }
    return "Couldn't play audio — tap retry";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: kInk,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, color: Gati.kumkuma, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: kPaper,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 1),
              Text(_message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Gati.onInkMuted, fontSize: 11.5)),
            ],
          ),
        ),
        TextButton(
          onPressed: onRetry,
          child: const Text('Retry',
              style: TextStyle(
                  color: Gati.pasupuGlow,
                  fontWeight: FontWeight.w500,
                  fontSize: 13)),
        ),
      ]),
    );
  }
}
