import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/tokens.dart';
import '../l10n/strings.dart';
import '../services/settings_provider.dart';
import 'today_screen.dart';
import 'menu_screen.dart';

/// Home shell with an iOS-style slide-over reveal drawer: the menu sits fixed
/// behind on the RIGHT, and the Today page is the front layer that slides LEFT
/// (with a slight scale, rounded corners and shadow) to reveal it. Open with the
/// top-right menu button or an edge-swipe from the right; close by tapping the
/// slid page, swiping it back, or picking a menu item. The menu never moves.
class HomeDrawerShell extends StatefulWidget {
  const HomeDrawerShell({super.key});
  @override
  State<HomeDrawerShell> createState() => _HomeDrawerShellState();
}

class _HomeDrawerShellState extends State<HomeDrawerShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  double _openX = 1; // revealed width in px (set in build)

  static const _revealFraction = 0.82; // menu takes 82%; the page peeks 18%

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _open() => _c.animateTo(1, curve: Curves.easeOutCubic);
  void _close() => _c.animateTo(0, curve: Curves.easeOutCubic);
  void _toggle() => _c.value > 0.5 ? _close() : _open();

  void _onDrag(DragUpdateDetails d) {
    // Dragging the page left (negative dx) opens; right closes.
    _c.value = (_c.value - d.primaryDelta! / _openX).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0; // px/s; flick-left is negative
    if (v < -350) {
      _open();
    } else if (v > 350) {
      _close();
    } else {
      _c.value > 0.45 ? _open() : _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final lang = context.watch<SettingsProvider>().lang;
    // A recessed "floor" behind the page so the Today card reads as lifted above
    // the menu (the Claude-iOS depth cue) instead of two same-colour panels.
    final recessed =
        p.dark ? const Color(0xFF0E0D0B) : const Color(0xFFE3DCCD);
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      _openX = w * _revealFraction;
      return Material(
        color: recessed,
        child: Stack(children: [
          // Back layer: the menu, pinned to the right, full-height + fixed, on
          // the recessed floor.
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: _openX,
            child: _menuPanel(p, lang, recessed),
          ),
          // Front layer: the Today page, sliding left to reveal the menu.
          AnimatedBuilder(
            animation: _c,
            child: TodayScreen(onMenu: _toggle),
            builder: (context, child) {
              final t = _c.value;
              final radius = 22.0 * t;
              return Transform.translate(
                offset: Offset(-t * _openX, 0),
                child: Transform.scale(
                  // Shrink only a little so it stays page-like, but enough to gain
                  // top/bottom margins that show the recessed floor behind it.
                  scale: 1 - 0.055 * t,
                  alignment: Alignment.centerRight,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      boxShadow: t > 0.01
                          ? [
                              BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: (p.dark ? 0.55 : 0.32) * t),
                                  blurRadius: 44,
                                  spreadRadius: 2,
                                  offset: const Offset(-10, 16)),
                            ]
                          : const [],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: Stack(children: [
                        child!,
                        // Dim + dismiss target once the page is mostly out.
                        if (t > 0.001)
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: t < 0.5,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _close,
                                onHorizontalDragUpdate: _onDrag,
                                onHorizontalDragEnd: _onDragEnd,
                                child: ColoredBox(
                                    color: Colors.black
                                        .withValues(alpha: 0.22 * t)),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
          // Edge-swipe-from-right opener (only meaningful while closed).
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              if (_c.value > 0.02) return const SizedBox.shrink();
              return Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: 26,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: _onDrag,
                  onHorizontalDragEnd: _onDragEnd,
                ),
              );
            },
          ),
        ]),
      );
    });
  }

  Widget _menuPanel(GatiPalette p, String lang, Color recessed) {
    // Tapping empty menu space closes the drawer and returns to Today. The
    // translucent behavior lets the actual option controls (choice rows,
    // buttons) win the gesture arena, so tapping an option does NOT close —
    // only taps that land on non-interactive areas reach this _close.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _close,
      child: Container(
      color: recessed,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
              child: Text(tr(lang, 'menu'),
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: p.ink)),
            ),
            const Expanded(
              child: MenuBody(padding: EdgeInsets.fromLTRB(16, 4, 16, 24)),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
