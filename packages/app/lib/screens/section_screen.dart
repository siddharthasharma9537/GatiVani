import 'package:flutter/material.dart';
import '../models/newspaper_article.dart';
import '../services/playback_service.dart';
import '../widgets/article_card.dart';
import '../widgets/mini_player.dart';
import 'lyrics_player_screen.dart';

/// A single section's article list, reached by tapping a section tile on the
/// home grid. Same split tap as the home list: tap the text → full player,
/// tap the row ▶ → play in the mini-player. The app bar plays the whole
/// section as a playlist.
class SectionScreen extends StatelessWidget {
  const SectionScreen(
      {super.key, required this.section, required this.articles});
  final String section;
  final List<NewspaperArticle> articles;

  void _openPlayer(BuildContext context) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const LyricsPlayerScreen()));
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
    return Scaffold(
      backgroundColor: kPaper,
      appBar: AppBar(
        backgroundColor: kPaper,
        surfaceTintColor: kPaper,
        elevation: 0,
        foregroundColor: kInk,
        title: Text('$section · ${articles.length}',
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w500, color: kInk)),
        actions: [
          TextButton.icon(
            onPressed: _playAll,
            icon: const Icon(Icons.play_circle_fill, color: kAccent, size: 20),
            label: const Text('Play all',
                style: TextStyle(
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
                    onOpen: () => _play(context, a),
                    onPlay: () => PlaybackService.i.playOne(a),
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
