import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../design/components/gati_tab_bar.dart';
import '../design/tokens.dart';
import '../l10n/strings.dart';
import '../screens/menu_screen.dart';
import '../services/edition_store.dart';
import '../services/news_feed_service.dart';
import '../services/settings_provider.dart';
import 'assistant_sheet.dart';
import 'mini_player.dart';

/// Lets any screen inside the shell open the menu drawer (header buttons).
class GatiShellScope extends InheritedWidget {
  const GatiShellScope(
      {super.key, required this.openMenu, required super.child});
  final VoidCallback openMenu;

  static GatiShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GatiShellScope>();

  @override
  bool updateShouldNotify(GatiShellScope oldWidget) => false;
}

/// App chrome around the tab branches (§8): the persistent mini-player dock
/// and tab bar at the bottom, and a Claude-iOS-style menu drawer on the
/// LEFT — the whole front page (tabs included) slides right with a slight
/// scale, rounded corners and shadow to reveal the menu on a recessed
/// floor. Open with a header menu button or a left-edge swipe; close by
/// tapping the slid page, swiping back, or picking a menu item.
class GatiShell extends StatefulWidget {
  const GatiShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  State<GatiShell> createState() => _GatiShellState();
}

class _GatiShellState extends State<GatiShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));
  double _openX = 1; // revealed width in px (set in build)

  static const _revealFraction = 0.82; // menu takes 82%; the page peeks 18%

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _open() => _c.animateTo(1, curve: Curves.easeOutCubic);
  void _close() => _c.animateTo(0, curve: Curves.easeOutCubic);

  void _onDrag(DragUpdateDetails d) {
    // Dragging the page right (positive dx) opens; left closes.
    _c.value = (_c.value + d.primaryDelta! / _openX).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0; // px/s; flick-right is positive
    if (v > 350) {
      _open();
    } else if (v < -350) {
      _close();
    } else {
      _c.value > 0.45 ? _open() : _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final lang = context.watch<SettingsProvider>().lang;
    // Recessed "floor" behind the page so it reads as lifted above the menu
    // (the Claude-iOS depth cue) instead of two same-colour panels.
    final recessed = p.dark ? const Color(0xFF0E0D0B) : const Color(0xFFE3DCCD);
    return LayoutBuilder(builder: (context, cons) {
      _openX = cons.maxWidth * _revealFraction;
      return Material(
        color: recessed,
        child: Stack(children: [
          // Back layer: the menu, pinned to the LEFT, full-height + fixed.
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: _openX,
            child: _menuPanel(p, lang, recessed),
          ),
          // Front layer: tabs + docks, sliding right to reveal the menu.
          AnimatedBuilder(
            animation: _c,
            child: GatiShellScope(
              openMenu: _open,
              child: Scaffold(
                backgroundColor: p.paper,
                body: widget.shell,
                floatingActionButton: const _VaniFab(),
                bottomNavigationBar: SafeArea(
                  top: false,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    MiniPlayer(onExpand: () => context.push('/player')),
                    GatiTabBar(
                      currentIndex: widget.shell.currentIndex,
                      onTap: (i) => widget.shell.goBranch(i,
                          initialLocation: i == widget.shell.currentIndex),
                      items: [
                        GatiTabItem(Icons.sensors, tr(lang, 'tab_live')),
                        GatiTabItem(Icons.newspaper, tr(lang, 'tab_paper')),
                        GatiTabItem(Icons.mic_rounded, tr(lang, 'tab_shows')),
                      ],
                    ),
                  ]),
                ),
              ),
            ),
            builder: (context, child) {
              final t = _c.value;
              final radius = 22.0 * t;
              return Transform.translate(
                offset: Offset(t * _openX, 0),
                child: Transform.scale(
                  scale: 1 - 0.055 * t,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      boxShadow: t > 0.01
                          ? [
                              BoxShadow(
                                  color: Colors.black.withValues(
                                      alpha: (p.dark ? 0.55 : 0.32) * t),
                                  blurRadius: 44,
                                  spreadRadius: 2,
                                  offset: const Offset(10, 16)),
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
          // Edge-swipe-from-left opener (only meaningful while closed).
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              if (_c.value > 0.02) return const SizedBox.shrink();
              return Positioned(
                top: 0,
                bottom: 0,
                left: 0,
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
    // Translucent so option rows win the arena — only taps on empty space
    // close the drawer.
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

/// The floating Vāni button — the assistant's home on every tab. Opens the
/// global chat grounded on an index of today's content (Live stories +
/// the loaded print edition), where Vāni can also ACT on the app (location
/// questions drive the district filter).
class _VaniFab extends StatelessWidget {
  const _VaniFab();

  String _contentIndex() {
    final live = ReaderStore.i.all
        .take(20)
        .map((a) => '• ${a.title} (${a.source})')
        .join('\n');
    final paper = EditionStore.i.articles
        .take(40)
        .map((a) => '• [${a.category}] ${a.title}')
        .join('\n');
    return 'LIVE STORIES RIGHT NOW:\n$live\n\n'
        "TODAY'S PRINT EDITION:\n$paper";
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    return GestureDetector(
      onTap: () => AssistantSheet.open(context, '', 'GatiVani',
          articleText: _contentIndex(), general: true),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Gati.inkDeep,
            shape: BoxShape.circle,
            boxShadow: Gati.shadow,
          ),
          child: const Icon(Icons.graphic_eq, color: Gati.pasupu, size: 24),
        ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
              color: p.paper.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8)),
          child: Text('Vāni',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: p.ink)),
        ),
      ]),
    );
  }
}
