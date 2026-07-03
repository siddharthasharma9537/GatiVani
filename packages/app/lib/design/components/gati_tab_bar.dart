import 'package:flutter/material.dart';

import '../tokens.dart';

class GatiTabItem {
  const GatiTabItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// Bottom navigation (§8) — paper ground, hairline top rule, gold active
/// state (deep gold on paper, glow on dark).
class GatiTabBar extends StatelessWidget {
  const GatiTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<GatiTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final active = p.dark ? Gati.pasupuGlow : Gati.pasupuDeep;
    return Container(
      decoration: BoxDecoration(
        color: p.paper,
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
                      Icon(items[i].icon,
                          size: 22,
                          color: i == currentIndex ? active : p.muted),
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
    );
  }
}
