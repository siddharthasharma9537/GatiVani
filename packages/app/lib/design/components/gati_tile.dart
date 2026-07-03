import 'package:flutter/material.dart';

import '../tokens.dart';

/// Section-tinted show tile (§10) — waveform mark, title, play-meta row,
/// all colored from the section ramp so a grid of tiles reads as one set.
/// The Live screen's podcast grid is the canonical use.
class GatiTile extends StatelessWidget {
  const GatiTile({
    super.key,
    required this.title,
    required this.meta,
    required this.ramp,
    required this.onTap,
    this.onLongPress,
  });

  final String title;
  final String meta;

  /// `[background, title, subtitle]` from `sectionRamp`.
  final List<Color> ramp;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(Gati.s4),
        decoration: BoxDecoration(
            color: ramp[0], borderRadius: BorderRadius.circular(Gati.rCard)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.graphic_eq, color: ramp[1], size: 22),
            const Spacer(),
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: ramp[1])),
            const SizedBox(height: 2),
            Row(children: [
              Icon(Icons.play_arrow, size: 14, color: ramp[2]),
              const SizedBox(width: 2),
              Expanded(
                child: Text(meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: ramp[2])),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
