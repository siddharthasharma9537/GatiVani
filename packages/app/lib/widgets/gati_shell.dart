import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../design/components/gati_tab_bar.dart';
import '../design/tokens.dart';
import '../l10n/strings.dart';
import '../screens/history_screen.dart';
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
/// and tab bar at the bottom, a Claude-iOS-style menu drawer on the LEFT,
/// and its mirror on the RIGHT — "Recent", the listening history. The whole
/// front page slides aside with a slight scale, rounded corners and shadow.
/// Open with the header menu button / edge swipes; swiping the page body
/// (away from the edges) slides between the tabs themselves.
class GatiShell extends StatefulWidget {
  const GatiShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  State<GatiShell> createState() => _GatiShellState();
}

class _GatiShellState extends State<GatiShell> with TickerProviderStateMixin {
  late final AnimationController _menu = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));
  late final AnimationController _recent = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));
  // Quick directional slide-in when the active tab changes.
  late final AnimationController _tabAnim = AnimationController(
      vsync: this, duration: GatiMotion.madhyama, value: 1);
  double _openX = 1; // revealed width in px (set in build)
  int _prevIndex = 0;
  double _tabDir = 1;

  static const _revealFraction = 0.82; // panel takes 82%; the page peeks 18%

  @override
  void dispose() {
    _menu.dispose();
    _recent.dispose();
    _tabAnim.dispose();
    super.dispose();
  }

  void _openMenu() {
    _recent.animateTo(0, curve: Curves.easeOutCubic);
    _menu.animateTo(1, curve: Curves.easeOutCubic);
  }

  void _openRecent() {
    _menu.animateTo(0, curve: Curves.easeOutCubic);
    _recent.animateTo(1, curve: Curves.easeOutCubic);
  }

  void _closeAll() {
    _menu.animateTo(0, curve: Curves.easeOutCubic);
    _recent.animateTo(0, curve: Curves.easeOutCubic);
  }

  // Edge/scrim drags: positive dx drives the menu, negative drives Recent
  // (whichever is already open wins the gesture).
  void _onDrag(DragUpdateDetails d) {
    final dx = d.primaryDelta ?? 0;
    if (_recent.value > 0.01 || (dx < 0 && _menu.value < 0.01)) {
      _recent.value = (_recent.value - dx / _openX).clamp(0.0, 1.0);
    } else {
      _menu.value = (_menu.value + dx / _openX).clamp(0.0, 1.0);
    }
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_recent.value > 0.01) {
      if (v < -350) {
        _openRecent();
      } else if (v > 350) {
        _closeAll();
      } else {
        _recent.value > 0.45 ? _openRecent() : _closeAll();
      }
    } else {
      if (v > 350) {
        _openMenu();
      } else if (v < -350) {
        _closeAll();
      } else {
        _menu.value > 0.45 ? _openMenu() : _closeAll();
      }
    }
  }

  void _goTab(int i) {
    if (i < 0 || i > 2 || i == widget.shell.currentIndex) return;
    widget.shell.goBranch(i, initialLocation: false);
  }

  // Body swipe (away from the edge zones) slides between tabs.
  void _onBodySwipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v < -350) _goTab(widget.shell.currentIndex + 1);
    if (v > 350) _goTab(widget.shell.currentIndex - 1);
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final lang = context.watch<SettingsProvider>().lang;
    // Directional slide-in whenever the branch changed (tap or swipe).
    if (_prevIndex != widget.shell.currentIndex) {
      _tabDir = widget.shell.currentIndex > _prevIndex ? 1 : -1;
      _prevIndex = widget.shell.currentIndex;
      _tabAnim.forward(from: 0);
    }
    // Recessed "floor" behind the page so it reads as lifted above the
    // panels (the Claude-iOS depth cue) instead of two same-colour planes.
    final recessed = p.dark ? const Color(0xFF0E0D0B) : const Color(0xFFE3DCCD);
    return LayoutBuilder(builder: (context, cons) {
      _openX = cons.maxWidth * _revealFraction;
      return Material(
        color: recessed,
        child: Stack(children: [
          // Back layers: menu pinned LEFT, Recent pinned RIGHT.
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: _openX,
            child: _panel(p, recessed, tr(lang, 'menu'),
                const MenuBody(padding: EdgeInsets.fromLTRB(16, 4, 16, 24))),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: _openX,
            child: AnimatedBuilder(
              animation: _recent,
              builder: (context, child) =>
                  _recent.value > 0.01 ? child! : const SizedBox.shrink(),
              child: _panel(
                  p,
                  recessed,
                  tr(lang, 'recent'),
                  const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: HistoryBody())),
            ),
          ),
          // Front layer: tabs + docks, sliding aside to reveal a panel.
          AnimatedBuilder(
            animation: Listenable.merge([_menu, _recent]),
            child: GatiShellScope(
              openMenu: _openMenu,
              child: Scaffold(
                backgroundColor: p.paper,
                body: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: _onBodySwipe,
                  child: AnimatedBuilder(
                    animation: _tabAnim,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(_tabDir * 36 * (1 - _tabAnim.value), 0),
                      child: Opacity(
                          opacity: 0.5 + 0.5 * _tabAnim.value, child: child),
                    ),
                    child: widget.shell,
                  ),
                ),
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
              final t = _menu.value;
              final r = _recent.value;
              final e = t > r ? t : r; // combined "how far out" factor
              final radius = 22.0 * e;
              return Transform.translate(
                offset: Offset(t * _openX - r * _openX, 0),
                child: Transform.scale(
                  scale: 1 - 0.055 * e,
                  alignment:
                      t >= r ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      boxShadow: e > 0.01
                          ? [
                              BoxShadow(
                                  color: Colors.black.withValues(
                                      alpha: (p.dark ? 0.55 : 0.32) * e),
                                  blurRadius: 44,
                                  spreadRadius: 2,
                                  offset: Offset(t >= r ? 10 : -10, 16)),
                            ]
                          : const [],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: Stack(children: [
                        child!,
                        // Dim + dismiss target once the page is mostly out.
                        if (e > 0.001)
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: e < 0.5,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _closeAll,
                                onHorizontalDragUpdate: _onDrag,
                                onHorizontalDragEnd: _onDragEnd,
                                child: ColoredBox(
                                    color: Colors.black
                                        .withValues(alpha: 0.22 * e)),
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
          // Edge-swipe openers (only while closed): left → menu, right →
          // Recent.
          AnimatedBuilder(
            animation: Listenable.merge([_menu, _recent]),
            builder: (context, _) {
              if (_menu.value > 0.02 || _recent.value > 0.02) {
                return const SizedBox.shrink();
              }
              return Stack(children: [
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 0,
                  width: 26,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: _onDrag,
                    onHorizontalDragEnd: _onDragEnd,
                  ),
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: 26,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: _onDrag,
                    onHorizontalDragEnd: _onDragEnd,
                  ),
                ),
              ]);
            },
          ),
        ]),
      );
    });
  }

  Widget _panel(GatiPalette p, Color recessed, String title, Widget body) {
    // Translucent so option rows win the arena — only taps on empty space
    // close the panel.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _closeAll,
      child: Container(
        color: recessed,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
                child: Text(title,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: p.ink)),
              ),
              Expanded(child: body),
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
