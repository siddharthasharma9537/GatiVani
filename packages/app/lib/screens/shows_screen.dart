import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../design/components/gati_masthead.dart';
import '../design/components/gati_states.dart';
import '../design/tokens.dart';
import '../l10n/strings.dart';
import '../services/news_feed_service.dart';
import '../services/settings_provider.dart';
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
          GatiMasthead(lang: lang, actions: [
            GatiHeaderButton(
                icon: Icons.search, onTap: () => context.push('/search')),
          ]),
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
