import 'package:flutter/material.dart';
import '../services/playback_service.dart';
// Re-export the design tokens so screens that `import 'mini_player.dart'`
// keep resolving kInk/kPaper/kAccent/kMuted from the single source of truth.
import '../design/tokens.dart';
export '../design/tokens.dart';

/// Persistent bottom bar. Audio keeps playing while the user browses.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, this.onExpand});
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    final p = PlaybackService.i;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final a = p.current;
        if (a == null) return const SizedBox.shrink();
        final prog = p.duration.inMilliseconds == 0
            ? 0.0
            : p.position.inMilliseconds / p.duration.inMilliseconds;
        return GestureDetector(
          onTap: onExpand,
          // Swipe up opens the full player; swipe down dismisses the bar and
          // stops the audio.
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: kInk,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kPaper, fontSize: 13)),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                          value: prog.clamp(0.0, 1.0),
                          minHeight: 2,
                          backgroundColor: const Color(0xFF5F5E5A),
                          color: kAccent),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32),
                icon: const Icon(Icons.skip_previous, color: kMuted, size: 22),
                onPressed: p.previous,
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36),
                icon: p.loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: kAccent))
                    : Icon(p.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: kPaper, size: 28),
                onPressed: p.toggle,
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32),
                icon: const Icon(Icons.skip_next, color: kMuted, size: 22),
                onPressed: p.next,
              ),
            ]),
          ),
        );
      },
    );
  }
}
