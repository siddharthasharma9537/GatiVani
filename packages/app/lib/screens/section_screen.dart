import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../l10n/strings.dart';
import '../models/newspaper_article.dart';
import '../services/playback_service.dart';
import '../services/settings_provider.dart';
import '../widgets/article_card.dart';
import '../design/components/gati_article_sheet.dart';
import '../services/news_feed_service.dart';
import '../widgets/mini_player.dart';

/// A single section's article list, reached by tapping a section tile on the
/// home grid. Same split tap as the home list: tap the text → full player,
/// tap the row ▶ → play in the mini-player. The app bar plays the whole
/// section as a playlist.
class SectionScreen extends StatelessWidget {
  const SectionScreen(
      {super.key, required this.section, required this.articles});
  final String section;
  final List<NewspaperArticle> articles;

  void _openPlayer(BuildContext context) => context.push('/player');

  // Tap opens the article TEXT (same reader as everywhere); ▶ plays in the
  // mini-player.
  void _openArticle(BuildContext context, NewspaperArticle a) {
    final lang = context.read<SettingsProvider>().lang;
    ReaderStore.i.current = WebArticle(
      id: a.id,
      title: a.title,
      link: '',
      source: sectionLabel(a.category, lang),
      pubDate: '',
      summary: a.preview,
      body: a.content,
    );
    context.push('/reader');
  }

  void _play(BuildContext context, NewspaperArticle a) {
    _openPlayer(context);
    PlaybackService.i.playOne(a);
  }

  void _playAll() {
    if (articles.isEmpty) return;
    PlaybackService.i.playAll(articles);
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().lang;
    final p = GatiPalette.of(context);
    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        backgroundColor: p.paper,
        surfaceTintColor: p.paper,
        elevation: 0,
        foregroundColor: p.ink,
        title: Text('${sectionLabel(section, lang)} · ${articles.length}',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w500, color: p.ink)),
        actions: [
          TextButton.icon(
            onPressed: _playAll,
            icon: const Icon(Icons.play_circle_fill, color: kAccent, size: 20),
            label: Text(tr(lang, 'play_all'),
                style: const TextStyle(
                    color: kAccent, fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              children: [
                for (final a in articles)
                  ArticleCard(
                    article: a,
                    onOpen: () => _openArticle(context, a),
                    onPlay: () => PlaybackService.i.playOne(a),
                    onLongPressAt: (pos) => showGatiArticleMenu(
                        context, pos, a,
                        onRead: () => _openArticle(context, a)),
                  ),
              ],
            ),
          ),
          MiniPlayer(onExpand: () => _openPlayer(context)),
        ]),
      ),
    );
  }
}
