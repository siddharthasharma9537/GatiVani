import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/library/alerts_screen.dart';
import 'features/library/downloads_screen.dart';
import 'features/library/library_screen.dart';
import 'features/auth/gemini_key_gate_screen.dart';
import 'features/library/history_screen.dart';
import 'features/live/live_feed_screen.dart';
import 'features/library/playlist_detail_screen.dart';
import 'features/library/playlists_screen.dart';
import 'features/reader/reader_screen.dart';
import 'features/paper/section_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shows/shows_screen.dart';
import 'features/paper/paper_screen.dart';
import 'services/news_feed_service.dart';
import 'features/player/player_screen.dart';
import 'features/menu/menu_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/search/search_screen.dart';
import 'services/edition_store.dart';
import 'widgets/gati_shell.dart';

/// Notifies go_router whenever Supabase's auth state changes, so the /auth
/// bounce-home redirect below re-evaluates the instant a sign-in completes
/// (OAuth redirect or email/password) — no manual navigation or reload
/// needed. Deliberately independent of the Provider-managed AuthService:
/// this file has no widget-tree access to reach it, and
/// Supabase.instance.client.auth is already a live global by the time
/// anything here actually gets used (main() awaits Supabase.initialize()
/// before runApp).
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    Supabase.instance.client.auth.onAuthStateChange
        .listen((_) => notifyListeners());
  }
}

final _authRefresh = _AuthRefresh();

/// App navigation via go_router so each screen is a real browser history entry.
/// This is what makes the browser Back button pop the player/section/menu
/// instead of leaving the Flutter app entirely (which it did with bare
/// Navigator.push, since those create no history entries on web).
final GoRouter appRouter = GoRouter(
  refreshListenable: _authRefresh,
  // Browsing is free — no blanket login wall. Only account-tied actions
  // (playing audio, uploading a Paper edition — see PlaybackService and
  // paper_screen.dart) push /auth themselves, at the moment they're taken.
  // Here we just bounce an already-signed-in user OFF /auth if they land on
  // it (e.g. browser Back right after finishing sign-in).
  redirect: (context, state) {
    final signedIn = Supabase.instance.client.auth.currentUser != null;
    if (signedIn && state.matchedLocation == '/auth') return '/';
    return null;
  },
  routes: [
    GoRoute(
      path: '/gemini-key',
      builder: (_, __) => const GeminiKeyGateScreen(),
    ),
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
          GoRoute(path: '/paper', builder: (_, __) => const PaperScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/shows', builder: (_, __) => const ShowsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/library', builder: (_, __) => const LibraryScreen()),
        ]),
      ],
    ),
    // Old URLs — keep bookmarks/history working.
    GoRoute(path: '/newspaper', redirect: (_, __) => '/paper'),
    GoRoute(path: '/foryou', redirect: (_, __) => '/library'),
    // The player rises up from the bottom (where the mini-player sits) so it
    // reads as expanding out of it — like YouTube Music — instead of the
    // default slide-in-from-the-right page transition.
    GoRoute(
      path: '/player',
      pageBuilder: (context, state) => CustomTransitionPage<void>(
        key: state.pageKey,
        child: const PlayerScreen(),
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
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    GoRoute(path: '/history', builder: (_, __) => const HistoryScreen()),
    GoRoute(path: '/downloads', builder: (_, __) => const DownloadsScreen()),
    GoRoute(path: '/alerts', builder: (_, __) => const AlertsScreen()),
    GoRoute(path: '/playlists', builder: (_, __) => const PlaylistsScreen()),
    GoRoute(
      path: '/playlists/:id',
      builder: (_, state) => PlaylistDetailScreen(
          playlistId: state.pathParameters['id'] ?? ''),
    ),
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
