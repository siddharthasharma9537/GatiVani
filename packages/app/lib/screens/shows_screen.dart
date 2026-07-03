import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../design/components/gati_states.dart';
import '../design/components/gati_wordmark.dart';
import '../design/tokens.dart';
import '../l10n/strings.dart';
import '../services/news_feed_service.dart';
import '../services/settings_provider.dart';
import '../widgets/gati_shell.dart';
import '../widgets/podcasts_grid.dart';

/// Shows tab (§8.1): the podcast archive — Mann Ki Baat, AIR bulletins,
/// shows — with Stories to follow.
class ShowsScreen extends StatefulWidget {
  const ShowsScreen({super.key});

  @override
  State<ShowsScreen> createState() => _ShowsScreenState();
}

class _ShowsScreenState extends State<ShowsScreen> {
  Map<String, PodcastEpisode> _podcasts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    NewsFeedService().fetchPodcasts().then((eps) {
      if (!mounted) return;
      setState(() {
        _podcasts = {for (final e in eps) e.key: e};
        _loading = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final lang = context.watch<SettingsProvider>().lang;
    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gati.s5, Gati.s3, Gati.s4, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () {
                  final scope = GatiShellScope.maybeOf(context);
                  if (scope != null) {
                    scope.openMenu();
                  } else {
                    context.push('/menu');
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: p.chip,
                      borderRadius: BorderRadius.circular(Gati.rChip)),
                  child: Icon(Icons.menu, size: 20, color: p.ink),
                ),
              ),
              const SizedBox(width: Gati.s3),
              GatiWordmark(size: 20, color: p.ink, lang: lang),
              const Spacer(),
              Text(tr(lang, 'tab_shows'),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: p.muted)),
            ]),
          ),
          const SizedBox(height: Gati.s4),
          Expanded(
            child: ListView(children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(Gati.s6),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Gati.accent),
                    ),
                  ),
                )
              else
                PodcastsGrid(episodes: _podcasts, lang: lang),
              const SizedBox(height: Gati.s6),
              Padding(
                padding: const EdgeInsets.all(Gati.s6),
                child: GatiEmpty(
                    message: tr(lang, 'stories_soon'), onInk: false),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
