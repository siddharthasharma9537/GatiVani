import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/api_config.dart';
import '../../design/tokens.dart';
import '../../models/newspaper_article.dart';
import '../../services/news_feed_service.dart';
import '../../services/playback_service.dart';
import '../../services/share_stub.dart'
    if (dart.library.html) '../../services/share_web.dart' as export_;
import '../../services/settings_provider.dart';
import '../../widgets/gati_puck.dart';

/// In-app full-story reader for a web article (from feeds-articles). Renders the
/// title + full Telugu body already carried in the feed, and a Listen button
/// that narrates it via the shared player — the same synth path the newspaper
/// uses. Reached from the Live feed's Latest stories.
class ReaderScreen extends StatelessWidget {
  const ReaderScreen({super.key});

  void _listen(WebArticle a, {Duration? resumeAt}) {
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
      language: a.language,
    );
    PlaybackService.i.playOne(art, resumeAt: resumeAt);
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
      body: Stack(children: [
        SafeArea(
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
              if (age.isNotEmpty) ...[
                Text(age, style: TextStyle(fontSize: 12, color: p.muted)),
                const SizedBox(width: Gati.s2),
              ],
              if (export_.canShare || export_.canExportArticle)
                IconButton(
                  icon: Icon(Icons.share_outlined, color: p.ink, size: 21),
                  tooltip: 'Share',
                  onPressed: () {
                    if (export_.canShare) {
                      // The OS/browser's own share sheet — WhatsApp, Facebook,
                      // Mail, Save to Files, and on many platforms Print
                      // itself, all show up automatically with no extra work
                      // here; it's populated by whatever's installed.
                      export_.shareContent(
                        title: a.title,
                        // Source is mandatory in what's shared, not just an
                        // optional flourish — attribution shouldn't get lost
                        // once the text leaves the app.
                        text: '${a.summary.isNotEmpty ? a.summary : a.body}'
                            '\n\n— ${a.source}, via GatiVāni',
                        url: a.link,
                      );
                    } else {
                      _showExportSheet(context, a);
                    }
                  },
                ),
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
                _ListenButton(
                    article: a,
                    onListen: (resumeAt) => _listen(a, resumeAt: resumeAt),
                    isArticle: a.link.isEmpty),
                const SizedBox(height: Gati.s5),
                Text(a.body,
                    style: GatiType.bodyRead(GatiType.scriptOf(a.body))
                        .copyWith(color: p.ink)),
                const SizedBox(height: Gati.s5),
                // Attribution + source of truth (web stories only — print
                // edition articles have no external link).
                if (a.link.isNotEmpty)
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
        ]),
        ),
        const GatiPuck(),
      ]),
    );
  }
}

/// Listen pill — reflects the shared player's state for THIS reader session
/// (idle → "Listen", playing → "Playing…") AND, once loaded, this article's
/// saved progress from a past listen: partway through → "Resume" (from that
/// spot); fully finished → "Replay" (from the top).
class _ListenButton extends StatefulWidget {
  const _ListenButton(
      {required this.article, required this.onListen, this.isArticle = false});
  final WebArticle article;
  final void Function(Duration? resumeAt) onListen;
  final bool isArticle;

  @override
  State<_ListenButton> createState() => _ListenButtonState();
}

class _ListenButtonState extends State<_ListenButton> {
  int? _posSec;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    try {
      final r = await http.get(
        Uri.parse('${ApiConfig.restUrl}/recent_plays'
            '?article_id=eq.${widget.article.id}'
            '&select=position_seconds,completed&limit=1'),
        // recent_plays is scoped per user (RLS checks auth.uid()).
        headers: ApiConfig.userAuthHeaders,
      );
      final rows = json.decode(r.body) as List;
      if (rows.isEmpty || !mounted) return;
      final m = rows.first as Map<String, dynamic>;
      setState(() {
        _posSec = (m['position_seconds'] as num?)?.toInt();
        _completed = m['completed'] == true;
      });
    } catch (_) {
      // Best-effort — falls back to the plain "Listen" state.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlaybackService.i,
      builder: (context, _) {
        final ps = PlaybackService.i;
        final playing = ps.isPlaying;
        final lang = context.read<SettingsProvider>().lang;
        final hasProgress = !_completed && (_posSec ?? 0) > 0;
        return GestureDetector(
          onTap: playing
              ? () => ps.player.pause()
              : () => widget.onListen(
                  hasProgress ? Duration(seconds: _posSec!) : null),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Gati.s5, vertical: Gati.s3),
            decoration: BoxDecoration(
                color: kAccent, borderRadius: BorderRadius.circular(Gati.rPill)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  playing
                      ? Icons.pause
                      : (_completed
                          ? Icons.replay_rounded
                          : Icons.play_arrow),
                  color: kPaper,
                  size: 22),
              const SizedBox(width: Gati.s2),
              Text(
                  playing
                      ? _t(lang, 'Playing…', 'వినిపిస్తోంది…')
                      : _completed
                          ? _t(lang, 'Replay', 'మళ్లీ వినండి')
                          : hasProgress
                              ? _t(lang, 'Resume', 'కొనసాగించండి')
                              : widget.isArticle
                                  ? _t(lang, 'Listen to the article',
                                      'వ్యాసాన్ని వినండి')
                                  : _t(lang, 'Listen to this story',
                                      'ఈ కథనాన్ని వినండి'),
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

/// Fallback for browsers without Web Share support (older desktop mainly):
/// the same print/download options a share sheet would otherwise offer.
void _showExportSheet(BuildContext context, WebArticle a) {
  final lang = context.read<SettingsProvider>().lang;
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Wrap(children: [
        ListTile(
          leading: const Icon(Icons.print_outlined),
          title: Text(
              _t(lang, 'Print / Save as PDF', 'ప్రింట్ / PDFగా సేవ్ చేయండి')),
          onTap: () {
            Navigator.pop(ctx);
            export_.printArticle(a.title, a.source, a.body);
          },
        ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title:
              Text(_t(lang, 'Download as text', 'టెక్స్ట్‌గా డౌన్‌లోడ్')),
          onTap: () {
            Navigator.pop(ctx);
            export_.downloadArticleText(a.title, a.source, a.body);
          },
        ),
      ]),
    ),
  );
}
