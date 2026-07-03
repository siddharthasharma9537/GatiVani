import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/live_feed_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/section_screen.dart';
import 'screens/shows_screen.dart';
import 'screens/today_screen.dart';
import 'services/news_feed_service.dart';
import 'screens/lyrics_player_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/search_screen.dart';
import 'services/edition_store.dart';
import 'widgets/gati_shell.dart';

/// App navigation via go_router so each screen is a real browser history entry.
/// This is what makes the browser Back button pop the player/section/menu
/// instead of leaving the Flutter app entirely (which it did with bare
/// Navigator.push, since those create no history entries on web).
final GoRouter appRouter = GoRouter(
  routes: [
    // The tab shell (§8): Live · Paper · Shows inside GatiShell, which adds
    // the persistent mini-player dock + tab bar and the Claude-iOS-style
    // left menu drawer. IndexedStack keeps each tab's state (and per-tab
    // browser history) alive across switches.
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          GatiShell(shell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/', builder: (_, __) => const LiveFeedScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/paper', builder: (_, __) => const TodayScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/shows', builder: (_, __) => const ShowsScreen()),
        ]),
      ],
    ),
    // Old URL for the newspaper — keep bookmarks/history working.
    GoRoute(path: '/newspaper', redirect: (_, __) => '/paper'),
    // The player rises up from the bottom (where the mini-player sits) so it
    // reads as expanding out of it — like YouTube Music — instead of the
    // default slide-in-from-the-right page transition.
    GoRoute(
      path: '/player',
      pageBuilder: (context, state) => CustomTransitionPage<void>(
        key: state.pageKey,
        child: const LyricsPlayerScreen(),
        // Non-opaque so the screen beneath stays painted — the player's
        // pull-down-to-dismiss slides it away over live content, not black.
        opaque: false,
        transitionDuration: const Duration(milliseconds: 340),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondary, child) {
          final curved =
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                .animate(curved),
            child: child,
          );
        },
      ),
    ),
    // Full-story reader for a web article. The article lives in ReaderStore
    // (go_router extra is lost on Back); cold deep-link with none → home.
    GoRoute(
      path: '/reader',
      redirect: (_, __) => ReaderStore.i.current == null ? '/' : null,
      builder: (_, __) => const ReaderScreen(),
    ),
    // Standalone menu page — headers open the shell drawer instead, but the
    // URL keeps working for deep links and as the no-shell fallback.
    GoRoute(
      path: '/menu',
      pageBuilder: (context, state) => CustomTransitionPage<void>(
        key: state.pageKey,
        child: const MenuScreen(),
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        transitionsBuilder: (context, animation, secondary, child) {
          final curved =
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween(begin: const Offset(-1, 0), end: Offset.zero)
                .animate(curved),
            child: child,
          );
        },
      ),
    ),
    GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
    GoRoute(
      path: '/auth',
      builder: (_, state) =>
          AuthScreen(signUp: (state.extra as bool?) ?? false),
    ),
    // Section name is in the URL (survives back/forward); the articles come from
    // the EditionStore, NOT go_router `extra` (which is lost on Back). If the
    // store is empty (cold deep-link/refresh), fall back to the newspaper.
    GoRoute(
      path: '/section/:name',
      redirect: (_, __) => EditionStore.i.articles.isEmpty ? '/paper' : null,
      builder: (_, state) {
        final name = Uri.decodeComponent(state.pathParameters['name'] ?? '');
        return SectionScreen(
            section: name, articles: EditionStore.i.forSection(name));
      },
    ),
  ],
);
