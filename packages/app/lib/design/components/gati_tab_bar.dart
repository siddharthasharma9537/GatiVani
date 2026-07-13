import 'package:flutter/material.dart';

import '../tokens.dart';

class GatiTabItem {
  const GatiTabItem(this.icon, this.label, {this.badge = false});
  final IconData icon;
  final String label;

  /// Show the unread dot (For You uses it for fresh alerts).
  final bool badge;
}

/// Bottom navigation (§8) — paper ground, hairline top rule, gold active
/// state (deep gold on paper, glow on dark).
class GatiTabBar extends StatelessWidget {
  const GatiTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.onSwipe,
  });

  final List<GatiTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Swiping the bar itself also changes tabs (+1 left, -1 right).
  final ValueChanged<int>? onSwipe;

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final active = p.dark ? Gati.pasupuGlow : Gati.pasupuDeep;
    return GestureDetector(
      onHorizontalDragEnd: onSwipe == null
          ? null
          : (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -250) onSwipe!(1);
              if (v > 250) onSwipe!(-1);
            },
      child: Container(
      decoration: BoxDecoration(
        color: p.dark ? GatiDark.band : Gati.band,
        border: Border(top: BorderSide(color: p.line, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Stack(clipBehavior: Clip.none, children: [
                        Icon(items[i].icon,
                            size: 22,
                            color: i == currentIndex ? active : p.muted),
                        if (items[i].badge)
                          Positioned(
                            top: -1,
                            right: -3,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                  color: Gati.kumkuma,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: p.dark
                                          ? GatiDark.band
                                          : Gati.band,
                                      width: 1)),
                            ),
                          ),
                      ]),
                      const SizedBox(height: 2),
                      Text(items[i].label,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: i == currentIndex
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                              color: i == currentIndex ? active : p.muted)),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}
