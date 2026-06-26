import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/today_screen.dart';
import 'screens/section_screen.dart';
import 'screens/lyrics_player_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/auth_screen.dart';
import 'services/edition_store.dart';

/// App navigation via go_router so each screen is a real browser history entry.
/// This is what makes the browser Back button pop the player/section/menu
/// instead of leaving the Flutter app entirely (which it did with bare
/// Navigator.push, since those create no history entries on web).
final GoRouter appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const TodayScreen()),
    GoRoute(path: '/player', builder: (_, __) => const LyricsPlayerScreen()),
    GoRoute(path: '/menu', builder: (_, __) => const MenuScreen()),
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
      redirect: (_, __) => EditionStore.i.articles.isEmpty ? '/' : null,
      builder: (_, state) {
        final name = Uri.decodeComponent(state.pathParameters['name'] ?? '');
        return SectionScreen(
            section: name, articles: EditionStore.i.forSection(name));
      },
    ),
  ],
);
