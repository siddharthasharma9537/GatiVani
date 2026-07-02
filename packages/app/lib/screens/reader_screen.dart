import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../design/tokens.dart';
import '../models/newspaper_article.dart';
import '../services/news_feed_service.dart';
import '../services/playback_service.dart';
import '../services/settings_provider.dart';
import '../widgets/mini_player.dart';

/// In-app full-story reader for a web article (from feeds-articles). Renders the
/// title + full Telugu body already carried in the feed, and a Listen button
/// that narrates it via the shared player — the same synth path the newspaper
/// uses. Reached from the Live feed's Latest stories.
class ReaderScreen extends StatelessWidget {
  const ReaderScreen({super.key});

  void _listen(WebArticle a) {
    // Reuse the newspaper player: build an article from the web story so synth,
    // caching, mini-player and the lyrics view all work unchanged.
    final art = NewspaperArticle(
      id: a.id,
      title: a.title,
      content: a.body,
      preview: a.summary,
      category: a.source,
      estimatedDurationSeconds: NewspaperArticle.estimateDuration(a.body),
      readingStyle: 'news_anchor',
    );
    PlaybackService.i.playOne(art);
  }

  Future<void> _openOriginal(String link) async {
    final uri = Uri.tryParse(link);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final lang = context.watch<SettingsProvider>().lang;
    final a = ReaderStore.i.current;
    // Cold deep-link / refresh: no article in memory → bounce home.
    if (a == null) {
      return const _EmptyReader();
    }
    final age = relativeAge(a.pubDate, lang);
    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // Top bar: back + source.
          Padding(
            padding: const EdgeInsets.fromLTRB(Gati.s3, Gati.s2, Gati.s5, Gati.s2),
            child: Row(children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: p.ink),
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Text(a.source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: kAccent)),
              ),
              if (age.isNotEmpty)
                Text(age, style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Gati.s5, Gati.s2, Gati.s5, Gati.s6),
              children: [
                Text(a.title,
                    style: GatiType.headline(GatiType.scriptOf(a.title))
                        .copyWith(color: p.ink)),
                const SizedBox(height: Gati.s4),
                _ListenButton(onListen: () => _listen(a)),
                const SizedBox(height: Gati.s5),
                Text(a.body,
                    style: GatiType.bodyRead(GatiType.scriptOf(a.body))
                        .copyWith(color: p.ink)),
                const SizedBox(height: Gati.s5),
                // Attribution + source of truth.
                GestureDetector(
                  onTap: () => _openOriginal(a.link),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.open_in_new, size: 15, color: p.muted),
                    const SizedBox(width: Gati.s2),
                    Text(_t(lang, 'Read on ${a.source}', '${a.source}లో చదవండి'),
                        style: TextStyle(
                            fontSize: 13,
                            color: p.muted,
                            decoration: TextDecoration.underline)),
                  ]),
                ),
                _RelatedArticles(current: a, lang: lang),
              ],
            ),
          ),
          MiniPlayer(onExpand: () => context.push('/player')),
        ]),
      ),
    );
  }
}

/// Listen pill — reflects the shared player's state for THIS reader session:
/// idle → "Listen", synthesizing → spinner, playing → "Playing…".
class _ListenButton extends StatelessWidget {
  const _ListenButton({required this.onListen});
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlaybackService.i,
      builder: (context, _) {
        final ps = PlaybackService.i;
        final playing = ps.isPlaying;
        final lang = context.read<SettingsProvider>().lang;
        return GestureDetector(
          onTap: playing ? () => ps.player.pause() : onListen,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Gati.s5, vertical: Gati.s3),
            decoration: BoxDecoration(
                color: kAccent, borderRadius: BorderRadius.circular(Gati.rPill)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(playing ? Icons.pause : Icons.play_arrow,
                  color: kPaper, size: 22),
              const SizedBox(width: Gati.s2),
              Text(
                  playing
                      ? _t(lang, 'Playing…', 'వినిపిస్తోంది…')
                      : _t(lang, 'Listen to this story', 'ఈ కథనాన్ని వినండి'),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: kPaper)),
            ]),
          ),
        );
      },
    );
  }
}

/// Other Latest-stories articles from the same publisher as the one being
/// read — a lightweight, zero-extra-request notion of "related" using the
/// pool ReaderStore already carries (see LiveFeedScreen._load).
class _RelatedArticles extends StatelessWidget {
  const _RelatedArticles({required this.current, required this.lang});
  final WebArticle current;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final related = ReaderStore.i.all
        .where((w) => w.source == current.source && w.id != current.id)
        .take(8)
        .toList();
    if (related.isEmpty) return const SizedBox.shrink();
    final p = GatiPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Gati.s6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_t(lang, 'Related articles', 'సంబంధిత వార్తలు'),
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: p.muted)),
        const SizedBox(height: Gati.s3),
        ...related.map((w) => _RelatedRow(article: w)),
      ]),
    );
  }
}

class _RelatedRow extends StatelessWidget {
  const _RelatedRow({required this.article});
  final WebArticle article;

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    return GestureDetector(
      onTap: () {
        ReaderStore.i.current = article;
        context.push('/reader');
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gati.s2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14.5, height: 1.3, color: p.ink)),
                const SizedBox(height: 2),
                Text(article.source,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: kAccent)),
              ],
            ),
          ),
          const SizedBox(width: Gati.s3),
          Icon(Icons.chevron_right, color: p.muted, size: 20),
        ]),
      ),
    );
  }
}

class _EmptyReader extends StatelessWidget {
  const _EmptyReader();
  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    return Scaffold(
      backgroundColor: p.paper,
      body: Center(
        child: TextButton(
          onPressed: () => context.go('/'),
          child: const Text('Back to Live'),
        ),
      ),
    );
  }
}

String _t(String lang, String en, String te) => lang == 'te' ? te : en;
