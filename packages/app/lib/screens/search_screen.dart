import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../design/tokens.dart';
import '../l10n/strings.dart';
import '../models/newspaper_article.dart';
import '../services/edition_store.dart';
import '../services/playback_service.dart';
import '../services/settings_provider.dart';
import '../widgets/article_card.dart';
import '../widgets/mini_player.dart';

/// Search across the loaded edition's articles (title + body), client-side so
/// it's instant. Tap a result's text → full player; tap ▶ → mini-player.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _open(NewspaperArticle a) {
    context.push('/player');
    PlaybackService.i.playOne(a);
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().lang;
    final p = GatiPalette.of(context);
    final q = _q.trim().toLowerCase();
    final results = q.isEmpty
        ? const <NewspaperArticle>[]
        : EditionStore.i.articles
            .where((a) =>
                a.title.toLowerCase().contains(q) ||
                a.content.toLowerCase().contains(q))
            .toList();

    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        backgroundColor: p.paper,
        surfaceTintColor: p.paper,
        elevation: 0,
        foregroundColor: p.ink,
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          style: TextStyle(color: p.ink, fontSize: 16),
          cursorColor: kAccent,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: tr(lang, 'search_hint'),
            hintStyle: TextStyle(color: p.muted),
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _q = v),
        ),
        actions: [
          if (_q.isNotEmpty)
            IconButton(
              icon: Icon(Icons.close_rounded, color: p.muted),
              onPressed: () {
                _ctrl.clear();
                setState(() => _q = '');
              },
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: q.isEmpty
                ? _hint(p, tr(lang, 'search_prompt'))
                : results.isEmpty
                    ? _hint(p, tr(lang, 'search_empty'))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 2, bottom: 8),
                            child: Text(
                                '${results.length} ${tr(lang, 'results')}',
                                style:
                                    TextStyle(fontSize: 12.5, color: p.muted)),
                          ),
                          for (final a in results)
                            ArticleCard(
                              article: a,
                              onOpen: () => _open(a),
                              onPlay: () => PlaybackService.i.playOne(a),
                            ),
                        ],
                      ),
          ),
          MiniPlayer(onExpand: () => context.push('/player')),
        ]),
      ),
    );
  }

  Widget _hint(GatiPalette p, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_rounded, size: 34, color: p.muted),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: p.muted)),
            ],
          ),
        ),
      );
}
