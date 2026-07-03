import 'package:flutter/material.dart';

import '../tokens.dart';

/// On-ink action pill (§10) — icon + label on an ink-chip ground, with an
/// optional busy spinner replacing the icon. The player's Read / Mix /
/// Save / Download row is the canonical use.
class GatiPill extends StatelessWidget {
  const GatiPill({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
            color: Gati.inkChip, borderRadius: BorderRadius.circular(22)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Gati.pasupu))
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
}
