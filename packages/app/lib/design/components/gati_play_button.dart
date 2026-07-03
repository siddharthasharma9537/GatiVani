import 'package:flutter/material.dart';

import '../tokens.dart';

/// The circular play/pause affordance (§10) — bright pasupu fill with INK
/// glyphs, never white (§4.3). Hero size 64 in the player; smaller inline
/// sizes on cards and tiles.
class GatiPlayButton extends StatelessWidget {
  const GatiPlayButton({
    super.key,
    required this.onTap,
    this.playing = false,
    this.loading = false,
    this.size = 64,
  });

  final VoidCallback onTap;
  final bool playing;
  final bool loading;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration:
            const BoxDecoration(color: Gati.pasupu, shape: BoxShape.circle),
        child: loading
            ? SizedBox(
                width: size * 0.44,
                height: size * 0.44,
                child: const CircularProgressIndicator(
                    strokeWidth: 2, color: Gati.inkDeep),
              )
            : Icon(playing ? Icons.pause : Icons.play_arrow,
                color: Gati.inkDeep, size: size * 0.5),
      ),
    );
  }
}
