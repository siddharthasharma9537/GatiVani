import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/districts.dart';
import '../design/components/gati_states.dart';
import '../design/components/gati_tab_bar.dart';
import '../design/components/vani_line.dart';
import '../design/tokens.dart';
import '../l10n/strings.dart';
import '../screens/history_screen.dart';
import '../screens/menu_screen.dart';
import '../models/newspaper_article.dart';
import '../services/document_service.dart';
import '../services/edition_store.dart';
import '../services/news_feed_service.dart';
import '../services/playback_service.dart';
import '../services/settings_provider.dart';
import '../services/speech_stub.dart'
    if (dart.library.html) '../services/speech_web.dart' as speech;
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

  void _goTab(int i) {
    if (i < 0 || i > 2 || i == widget.shell.currentIndex) return;
    widget.shell.goBranch(i, initialLocation: false);
  }

  // ONE horizontal-drag handler for the whole front layer, routed by where
  // the drag STARTED: left edge → menu, right edge → Recent, anywhere else →
  // tab slide. (Separate edge-zone + body recognizers used to fight in the
  // gesture arena — the drawer moved a few px, then the other recognizer
  // won and it stuck.)
  String? _dragMode; // 'menu' | 'recent' | 'tab'
  double _dragTotal = 0;

  void _hDragStart(DragStartDetails d) {
    final w = context.size?.width ?? 400;
    final x = d.globalPosition.dx;
    if (_menu.value > 0.5) {
      _dragMode = 'menu';
    } else if (_recent.value > 0.5) {
      _dragMode = 'recent';
    } else if (x < 44) {
      _dragMode = 'menu';
    } else if (x > w - 44) {
      _dragMode = 'recent';
    } else {
      _dragMode = 'tab';
    }
    _dragTotal = 0;
  }

  void _hDragUpdate(DragUpdateDetails d) {
    final dx = d.primaryDelta ?? 0;
    switch (_dragMode) {
      case 'menu':
        _menu.value = (_menu.value + dx / _openX).clamp(0.0, 1.0);
      case 'recent':
        _recent.value = (_recent.value - dx / _openX).clamp(0.0, 1.0);
      case 'tab':
        _dragTotal += dx;
    }
  }

  void _hDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    switch (_dragMode) {
      case 'menu':
        if (v > 350) {
          _openMenu();
        } else if (v < -350) {
          _closeAll();
        } else {
          _menu.value > 0.45 ? _openMenu() : _closeAll();
        }
      case 'recent':
        if (v < -350) {
          _openRecent();
        } else if (v > 350) {
          _closeAll();
        } else {
          _recent.value > 0.45 ? _openRecent() : _closeAll();
        }
      case 'tab':
        if (v < -350 || _dragTotal < -90) {
          _goTab(widget.shell.currentIndex + 1);
        } else if (v > 350 || _dragTotal > 90) {
          _goTab(widget.shell.currentIndex - 1);
        }
    }
    _dragMode = null;
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
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: _hDragStart,
                onHorizontalDragUpdate: _hDragUpdate,
                onHorizontalDragEnd: _hDragEnd,
                child: Scaffold(
                backgroundColor: p.paper,
                body: AnimatedBuilder(
                    animation: _tabAnim,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(_tabDir * 36 * (1 - _tabAnim.value), 0),
                      child: Opacity(
                          opacity: 0.5 + 0.5 * _tabAnim.value, child: child),
                    ),
                    child: widget.shell,
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
                      onSwipe: (dir) =>
                          _goTab(widget.shell.currentIndex + dir),
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
                                onHorizontalDragStart: _hDragStart,
                                onHorizontalDragUpdate: _hDragUpdate,
                                onHorizontalDragEnd: _hDragEnd,
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

/// The floating Vāni button — the assistant's home on every tab.
///
/// Tap → the chat sheet. LONG-PRESS → push-to-talk: the button waves while
/// it listens; on release Vāni acts on the words — a district shows that
/// place's news, "open paper/shows/history" navigates there, and any other
/// question is answered OUT LOUD (the reply is synthesized and played in
/// the mini-player, where it can be stopped like anything else).
class _VaniFab extends StatefulWidget {
  const _VaniFab();

  @override
  State<_VaniFab> createState() => _VaniFabState();
}

class _VaniFabState extends State<_VaniFab> {
  bool _listening = false;
  bool _thinking = false;

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

  void _startListening() {
    if (_listening || _thinking) return;
    final lang = context.read<SettingsProvider>().lang;
    setState(() => _listening = true);
    speech.startSpeech(
      lang: lang,
      onResult: (t) {
        if (mounted) _handleVoice(t);
      },
      onEnd: () {
        if (mounted) setState(() => _listening = false);
      },
    );
  }

  void _stopListening() => speech.stopSpeech();

  Future<void> _handleVoice(String q) async {
    final s = context.read<SettingsProvider>();
    final lang = s.lang;
    // 1) A district name = show that place's news (Live + Paper lists).
    for (final d in kDistricts) {
      if (q.contains(d.te) || q.toLowerCase().contains(d.en.toLowerCase())) {
        s.setDistrict(d.en);
        s.setFeedSort('location');
        s.setDistrictOnly(true);
        _speak(lang == 'te'
            ? '${d.te} వార్తలను చూపిస్తున్నాను.'
            : 'Showing ${d.en} news.');
        return;
      }
    }
    // 2) In-app navigation intents.
    final ql = q.toLowerCase();
    if (!mounted) return;
    if (ql.contains('paper') || ql.contains('newspaper') || q.contains('పేపర్')) {
      context.go('/paper');
      return;
    }
    if (ql.contains('shows') || ql.contains('podcast') || q.contains('షోలు') || q.contains('పాడ్‌కాస్ట్')) {
      context.go('/shows');
      return;
    }
    if (ql.contains('history') || ql.contains('recent') || q.contains('చరిత్ర')) {
      context.push('/history');
      return;
    }
    if (ql.contains('live') || q.contains('లైవ్')) {
      context.go('/');
      return;
    }
    // 3) Anything else: ask Vāni and speak the answer.
    setState(() => _thinking = true);
    try {
      final ans = await DocumentService().ask('', q,
          articleText: _contentIndex(),
          articleTitle: 'GatiVani today',
          general: true);
      _speak(ans);
    } catch (_) {
      if (mounted) gatiSnack(context, 'Vāni could not answer that.');
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }

  // Speak a reply out loud — through the normal playback path, so the
  // mini-player appears and the user can always see and stop what plays.
  void _speak(String text) {
    final art = NewspaperArticle(
      id: 'a0000000-0000-4000-8000-0000000000f1', // stable → one cache file
      title: 'Vāni',
      content: text,
      preview: text,
      category: 'Vāni',
      estimatedDurationSeconds: NewspaperArticle.estimateDuration(text),
    );
    PlaybackService.i.playSummary(art, text);
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    return GestureDetector(
      onTap: () => AssistantSheet.open(context, '', 'GatiVani',
          articleText: _contentIndex(), general: true),
      onLongPressStart: (_) => _startListening(),
      onLongPressEnd: (_) => _stopListening(),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _listening ? Gati.kumkuma : Gati.inkDeep,
            shape: BoxShape.circle,
            boxShadow: Gati.shadow,
          ),
          child: _thinking
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Gati.pasupu))
              : _listening
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: VaniLine(
                          mode: VaniLineMode.wave,
                          color: Gati.onInk,
                          strokeWidth: 2.5,
                          height: 24),
                    )
                  : const Icon(Icons.graphic_eq,
                      color: Gati.pasupu, size: 24),
        ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
              color: p.paper.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8)),
          child: Text(_listening ? '…' : 'Vāni',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: p.ink)),
        ),
      ]),
    );
  }
}
