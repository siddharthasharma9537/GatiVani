import 'package:flutter/material.dart';

import '../tokens.dart';

/// On-ink selectable chip (§10) — selected takes a bright pasupu fill with
/// ink glyphs (gold fills never carry white, §4.3). The player's year-chip
/// archive is the canonical use.
class GatiChip extends StatelessWidget {
  const GatiChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Gati.pasupu : Gati.inkChip,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Gati.inkDeep : Gati.onInkMuted,
                fontSize: 13.5,
                fontWeight: FontWeight.w500)),
      ),
    );
  }
}
