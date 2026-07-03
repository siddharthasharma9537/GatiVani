import 'package:flutter/material.dart';

import '../tokens.dart';
import 'vani_line.dart';

/// Branded toast (§9): one short sentence, two seconds, no exclamation.
void gatiSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}

/// Empty state (§8.5) — a silent, flat voice line and one sentence.
class GatiEmpty extends StatelessWidget {
  const GatiEmpty({super.key, required this.message, this.onInk = true});

  final String message;
  final bool onInk;

  @override
  Widget build(BuildContext context) {
    final muted = onInk ? Gati.onInkMuted : Gati.muted;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 64,
          child: VaniLine(
              color: onInk ? Gati.onInkTrack : Gati.line,
              strokeWidth: 2,
              height: 8),
        ),
        const SizedBox(height: 12),
        Text(message, style: TextStyle(color: muted, fontSize: 13.5)),
      ]),
    );
  }
}
