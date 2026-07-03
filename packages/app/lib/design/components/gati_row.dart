import 'package:flutter/material.dart';

import '../tokens.dart';

/// On-ink list row (§10) — leading box, title/subtitle, optional trailing.
/// The playing row takes the pasupu wash and a glowing title. Queue rows
/// and Mann Ki Baat episode rows are the canonical uses.
class GatiRow extends StatelessWidget {
  const GatiRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.current = false,
    this.onTap,
    this.titleMaxLines = 1,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool current;
  final VoidCallback? onTap;
  final int titleMaxLines;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: current ? Gati.pasupuTint : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: titleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: current ? Gati.pasupuGlow : Gati.onInk,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        height: 1.3)),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Gati.onInkMuted, fontSize: 12)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ]),
      ),
    );
  }
}
