import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/home_drawer_shell.dart';
import 'screens/live_feed_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/section_screen.dart';
import 'services/news_feed_service.dart';
import 'screens/lyrics_player_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/search_screen.dart';
import 'services/edition_store.dart';

/// App navigation via go_router so each screen is a real browser history entry.
/// This is what makes the browser Back button pop the player/section/menu
/// instead of leaving the Flutter app entirely (which it did with bare
/// Navigator.push, since those create no history entries on web).
final GoRouter appRouter = GoRouter(
  routes: [
    // v2 landing: the Live/Discovery feed sits in front of the newspaper.
    GoRoute(path: '/', builder: (_, __) => const LiveFeedScreen()),
    // The untouched Today experience (newspaper + reveal drawer), now reached
    // by tapping the Newspaper tile on the Live feed.
    GoRoute(path: '/newspaper', builder: (_, __) => const HomeDrawerShell()),
    // The player rises up from the bottom (where the mini-player sits) so it
    // reads as expanding out of it — like YouTube Music — instead of the
    // default slide-in-from-the-right page transition.
    GoRoute(
      path: '/player',
      pageBuilder: (context, state) => CustomTransitionPage<void>(
        key: state.pageKey,
        child: const LyricsPlayerScreen(),
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
    // The menu button always sits at the top-left, so the screen slides in
    // from the left (like a drawer) instead of the default right-hand push —
    // otherwise it visually contradicts where the button that opened it is.
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
    // store is empty (cold deep-link/refresh), fall back to home.
    GoRoute(
      path: '/section/:name',
      redirect: (_, __) => EditionStore.i.articles.isEmpty ? '/newspaper' : null,
      builder: (_, state) {
        final name = Uri.decodeComponent(state.pathParameters['name'] ?? '');
        return SectionScreen(
            section: name, articles: EditionStore.i.forSection(name));
      },
    ),
  ],
);
