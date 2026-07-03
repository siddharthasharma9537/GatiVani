import 'package:flutter/material.dart';

import '../tokens.dart';
import 'vani_line.dart';

/// The player's scrubber as the Vāni line (§3.3): remaining time is a flat
/// track, elapsed time is the gold voice line — waving while speaking,
/// flat when paused. Tap or drag anywhere to seek.
class GatiSeekBar extends StatelessWidget {
  const GatiSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.playing = false,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final durMs = duration.inMilliseconds;
    final frac = durMs == 0
        ? 0.0
        : (position.inMilliseconds / durMs).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      void seekTo(double dx) {
        if (durMs == 0) return;
        onSeek(Duration(
            milliseconds: (durMs * (dx / w).clamp(0.0, 1.0)).round()));
      }

      final px = w * frac;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => seekTo(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx),
        child: SizedBox(
          height: 28,
          child: Stack(children: [
            const Positioned.fill(
              child: Center(
                child: VaniLine(
                    color: Gati.onInkTrack, strokeWidth: 3, height: 28),
              ),
            ),
            // The elapsed portion: a full-width voice line clipped to the
            // playhead, so the wave's phase stays continuous while it grows.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: px,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: w,
                  maxWidth: w,
                  child: VaniLine(
                    mode: playing ? VaniLineMode.wave : VaniLineMode.flat,
                    color: Gati.pasupu,
                    strokeWidth: 3,
                    cycles: 4,
                    height: 28,
                  ),
                ),
              ),
            ),
            Positioned(
              left: (px - 5).clamp(0.0, w - 10),
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                      color: Gati.pasupuGlow, shape: BoxShape.circle),
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }
}
