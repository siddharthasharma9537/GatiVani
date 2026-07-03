import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../design/components/gati_filter_button.dart';
import '../design/components/gati_masthead.dart';
import '../design/components/gati_section_label.dart';
import '../design/components/gati_snap_scroll.dart';
import '../design/components/gati_play_button.dart';
import '../config/districts.dart';
import '../design/components/gati_article_sheet.dart';
import '../design/tokens.dart';
import '../design/section_colors.dart';
import '../l10n/strings.dart';
import '../models/newspaper_article.dart';
import '../services/cricket_service.dart';
import '../services/news_feed_service.dart';
import '../services/playback_service.dart';
import '../services/settings_provider.dart';
import '../widgets/gati_shell.dart';
import '../widgets/news_ticker.dart';

/// v2 landing — a discovery surface that sits in FRONT of the newspaper.
///
/// Layout (top → bottom):
///   • header (menu + title/dateline + search)
///   • breaking-news marquee ticker
///   • live cricket card (only while a match is live)
///   • Podcasts tiles
///   • Newspaper tile → opens the existing Today experience at /newspaper
///   • Latest stories list
///   • persistent mini-player
///
/// This screen does NOT touch the Today/newspaper UI — tapping the Newspaper
/// tile pushes /newspaper, which is the untouched HomeDrawerShell.
///
/// Real data: marquee + latest stories → RSS (Google News + publisher feeds);
/// cricket → CricketData.org facts → Gemini → TTS (mock until a
/// CRICKET_API_KEY secret is set); podcasts → real MP3 episodes for the shows
/// with a verified public feed (feeds-podcasts) — the other tiles stay
/// "coming soon" until a legitimate source is found for them too.
class LiveFeedScreen extends StatefulWidget {
  const LiveFeedScreen({super.key});

  @override
  State<LiveFeedScreen> createState() => _LiveFeedScreenState();
}

class _LiveFeedScreenState extends State<LiveFeedScreen> {
  // CRICKET_API_KEY is configured — the card now shows only genuine live
  // matches. Flip back to true to force the sample match for a quick demo.
  static const bool _cricketMock = false;

  final _feed = NewsFeedService();
  final _cricketSvc = CricketService();
  List<WebArticle> _articles = []; // Latest stories — full-body, readable in-app
  CricketMatch? _cricket; // null when nothing is live
  Explainer? _take; // "GatiVani Take" — today's weight-to-article pick
  bool _loading = true;

  // Latest stories browse mode. List is the default; grid groups the stories
  // into per-publisher tiles. Tapping a tile filters the list to that source.
  String _view = 'list'; // 'list' | 'grid'
  String? _sourceSel; // active publisher filter (set by a grid tile tap)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // All feeds concurrently: market ticker + diverse headlines for the marquee,
    // full articles for Latest stories, and the live cricket card (if any).
    final articlesF = _feed.fetchArticles(limit: 12);
    final cricketF = _cricketSvc.fetch(mock: _cricketMock);
    final takeF = _feed.fetchExplainer();
    final articles = await articlesF;
    final cricket = await cricketF;
    final take = await takeF;
    if (!mounted) return;
    setState(() {
      _articles = articles;
      _cricket = cricket;
      _take = take;
      _loading = false;
    });
    // Shared with the reader + player's "Related articles" — same pool
    // Latest stories already fetched, no extra request.
    ReaderStore.i.all = articles;
  }

  // Play the match's AI Telugu commentary via the shared player.
  void _playCommentary(CricketMatch m) {
    if (m.commentary.trim().isEmpty) return;
    final art = NewspaperArticle(
      id: 'a0000000-0000-4000-8000-0000000000c1', // stable → one storage file
      title: m.teams.isNotEmpty ? m.teams.join(' vs ') : 'Cricket',
      content: m.commentary,
      preview: m.status,
      category: 'Cricket',
      estimatedDurationSeconds: NewspaperArticle.estimateDuration(m.commentary),
      readingStyle: 'news_anchor',
    );
    PlaybackService.i.playOne(art);
  }

  // Play the GatiVani Take explainer via the shared player.
  void _playTake(Explainer t) {
    final art = NewspaperArticle(
      id: 'a0000000-0000-4000-8000-0000000000e1', // stable → one storage file
      title: t.title,
      content: t.commentary,
      preview: t.commentary,
      category: 'GatiVani Take',
      estimatedDurationSeconds: NewspaperArticle.estimateDuration(t.commentary),
      readingStyle: 'news_anchor',
    );
    PlaybackService.i.playOne(art);
  }

  // Open the full story in-app (ReaderStore carries it across the route).
  void _openReader(WebArticle a) {
    ReaderStore.i.current = a;
    context.push('/reader');
  }

  NewspaperArticle _toArticle(WebArticle a) => NewspaperArticle(
        id: a.id,
        title: a.title,
        content: a.body,
        preview: a.summary,
        category: a.source,
        estimatedDurationSeconds: NewspaperArticle.estimateDuration(a.body),
        readingStyle: 'news_anchor',
      );

  // Latest stories, honoring the filter dropdown / Vāni: with a district
  // set, 'location' sort pins its stories first under a small label, and
  // "my district only" hides the rest.
  List<Widget> _storyRows(String lang) {
    final visible = _sourceSel == null
        ? _articles
        : _articles.where((a) => a.source == _sourceSel).toList();
    final settings = context.watch<SettingsProvider>();
    final district = districtByEn(settings.district);
    var ordered = visible;
    var hits = 0;
    if (district != null && _sourceSel == null) {
      final hit = <WebArticle>[];
      final rest = <WebArticle>[];
      for (final a in visible) {
        (district.matches('${a.title} ${a.body}') ? hit : rest).add(a);
      }
      if (settings.districtOnly) {
        hits = hit.length;
        ordered = hit;
      } else if (settings.feedSort == 'location') {
        hits = hit.length;
        ordered = [...hit, ...rest];
      }
    }
    Widget row(WebArticle it) => _StoryRow(
          item: it,
          age: relativeAge(it.pubDate, lang),
          onTap: () => _openReader(it),
          onPlay: () => PlaybackService.i.playOne(_toArticle(it)),
          onMore: (pos) => showGatiArticleMenu(context, pos, _toArticle(it),
              onRead: () => _openReader(it)),
        );
    return [
      if (hits > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(Gati.s5, Gati.s2, Gati.s5, 0),
          child: Row(children: [
            const Icon(Icons.location_on, size: 14, color: Gati.accent),
            const SizedBox(width: 4),
            Text(
                '${tr(lang, 'your_district')} · '
                '${lang == 'te' ? district!.te : district!.en}',
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: Gati.accent)),
          ]),
        ),
      ...ordered.map(row),
      if (ordered.isEmpty && settings.districtOnly)
        Padding(
          padding: const EdgeInsets.all(Gati.s5),
          child: Text(
              _t(lang, 'No stories from your district right now.',
                  'మీ జిల్లా నుంచి ప్రస్తుతం వార్తలు లేవు.'),
              style: const TextStyle(fontSize: 13, color: Gati.muted)),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final lang = context.watch<SettingsProvider>().lang;
    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          GatiMasthead(lang: lang, actions: [
            GatiHeaderButton(
                icon: Icons.search, onTap: () => context.push('/search')),
          ]),
          const NewsTicker(),
          Expanded(
            // Section-snap: the scroll settles on the Take and on Latest
            // stories; the story list scrolls INSIDE its section.
            child: LayoutBuilder(
              builder: (context, cons) => GatiSnapScroll(
                onRefresh: _load,
                sections: [
                  Column(children: [
                    const SizedBox(height: Gati.s4),
                    if (_take != null)
                      _TakeCard(
                          take: _take!, onListen: () => _playTake(_take!)),
                    const SizedBox(height: Gati.s5),
                  ]),
                  SizedBox(
                    height: cons.maxHeight,
                    child: Column(children: [
                      _LatestHeader(
                        lang: lang,
                        view: _view,
                        showToggle: !_loading && _articles.isNotEmpty,
                        onView: (v) => setState(() {
                          _view = v;
                          _sourceSel = null; // manual toggle clears drill-down
                        }),
                      ),
                      Expanded(
                        child: _loading
                            ? const Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: kAccent),
                                ),
                              )
                            : _articles.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: Gati.s5,
                                        vertical: Gati.s3),
                                    child: Text(
                                        _t(
                                            lang,
                                            'No stories right now. Pull to refresh.',
                                            'వార్తలు లేవు. రిఫ్రెష్ చేయండి.'),
                                        style: TextStyle(
                                            fontSize: 13, color: p.muted)),
                                  )
                                : _view == 'grid'
                                    ? ListView(children: [
                                        _SourceGrid(
                                          articles: _articles,
                                          lang: lang,
                                          onTapSource: (src) => setState(() {
                                            _sourceSel = src;
                                            _view = 'list';
                                          }),
                                        ),
                                      ])
                                    : ListView(
                                        padding: const EdgeInsets.only(
                                            bottom: Gati.s4),
                                        children: [
                                          if (_sourceSel != null)
                                            _SourceFilterChip(
                                              source: _sourceSel!,
                                              count: _articles
                                                  .where((a) =>
                                                      a.source == _sourceSel)
                                                  .length,
                                              onClear: () => setState(
                                                  () => _sourceSel = null),
                                            ),
                                          ..._storyRows(lang),
                                        ],
                                      ),
                      ),
                    ]),
                  ),
                  Column(children: [
                    if (_cricket != null) ...[
                      const SizedBox(height: Gati.s5),
                      GatiSectionLabel(_t(lang, 'Live now', 'ఇప్పుడు లైవ్')),
                      _CricketCard(
                        match: _cricket!,
                        onListen: () => _playCommentary(_cricket!),
                      ),
                    ],
                    const SizedBox(height: Gati.s5),
                    _NewspaperTile(lang: lang),
                    const SizedBox(height: Gati.s6),
                  ]),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Breaking-news marquee ───────────────────────────────────────────────────

// ── GatiVani Take ────────────────────────────────────────────────────────────

// The day's single weight-to-article pick (feeds-explains): an original
// Telugu title + explainer synthesized from independently-corroborated facts
// across national/international sources — never a translation of any one
// publisher's wording. Sits above the cricket card as the editorial lead.
class _TakeCard extends StatelessWidget {
  const _TakeCard({required this.take, required this.onListen});
  final Explainer take;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gati.s5, 0, Gati.s5, 0),
      child: GestureDetector(
        onTap: onListen,
        child: Container(
          padding: const EdgeInsets.all(Gati.s4),
          decoration: BoxDecoration(
            color: kInk,
            borderRadius: BorderRadius.circular(Gati.rCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: GatiDark.accentSoft,
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('GatiVani Take',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          color: Gati.pasupuGlow)),
                ),
                const Spacer(),
                GatiPlayButton(onTap: onListen, size: 30),
              ]),
              const SizedBox(height: Gati.s3),
              Text(take.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: kPaper)),
              const SizedBox(height: Gati.s2),
              Text(take.commentary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5, height: 1.5, color: Gati.onInkMuted)),
              if (take.sources.isNotEmpty) ...[
                const SizedBox(height: Gati.s2),
                Text(take.sources.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Gati.onInkTrack)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Cricket card ────────────────────────────────────────────────────────────

class _CricketCard extends StatelessWidget {
  const _CricketCard({required this.match, required this.onListen});
  final CricketMatch match;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final teams =
        match.teams.isNotEmpty ? match.teams.join(' vs ') : match.name;
    // No commentary (India isn't playing) → nothing to listen to, so the
    // card isn't tappable and the play icon doesn't show.
    final hasCommentary = match.commentary.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gati.s5, Gati.s2, Gati.s5, 0),
      child: GestureDetector(
        onTap: hasCommentary ? onListen : null,
        child: Container(
          padding: const EdgeInsets.all(Gati.s4),
          decoration: BoxDecoration(
            color: kInk,
            borderRadius: BorderRadius.circular(Gati.rCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration:
                      const BoxDecoration(color: kAccent, shape: BoxShape.circle),
                  child: const Text('🏏', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: Gati.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                              color: kAccent, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: Gati.s2),
                        Expanded(
                          child: Text('LIVE  ·  $teams',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Gati.onInkMuted)),
                        ),
                        if (match.mock) ...[
                          const SizedBox(width: Gati.s2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Gati.onInkTrack,
                                borderRadius: BorderRadius.circular(6)),
                            child: const Text('DEMO',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w500,
                                    color: Gati.onInk)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: Gati.s1),
                      Text(
                          match.scoreText.isNotEmpty
                              ? match.scoreText
                              : match.status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Gati.onInk)),
                    ],
                  ),
                ),
                if (hasCommentary)
                  const Icon(Icons.play_circle_fill, color: kAccent, size: 34),
              ]),
              // The AI-generated Telugu commentary line.
              if (hasCommentary) ...[
                const SizedBox(height: Gati.s3),
                Text(match.commentary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: Gati.onInkFuture)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Newspaper tile (gateway to the existing Today screen) ───────────────────

class _NewspaperTile extends StatelessWidget {
  const _NewspaperTile({required this.lang});
  final String lang;

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gati.s5),
      child: GestureDetector(
        onTap: () => context.push('/newspaper'),
        child: Container(
          padding: const EdgeInsets.all(Gati.s5),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(Gati.rCard),
            border: Border.all(color: p.line),
          ),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: Gati.accentSoft,
                  borderRadius: BorderRadius.circular(Gati.rChip)),
              child: const Icon(Icons.menu_book, color: kAccent, size: 24),
            ),
            const SizedBox(width: Gati.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_t(lang, "Today's Newspaper", 'నేటి దినపత్రిక'),
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: p.ink)),
                  const SizedBox(height: 2),
                  Text(_t(lang, 'Full edition · listen by section',
                      'పూర్తి ఎడిషన్ · విభాగాల వారీగా వినండి'),
                      style: TextStyle(fontSize: 12.5, color: p.muted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: p.muted, size: 22),
          ]),
        ),
      ),
    );
  }
}

// ── Latest story row ────────────────────────────────────────────────────────

class _StoryRow extends StatelessWidget {
  // Styled exactly like the Paper tab's article cards (soft section-tinted
  // card, play button right) so stories and articles read as one system.
  // Tap opens the story text; only the ▶ plays it (in the mini-player).
  const _StoryRow(
      {required this.item,
      required this.age,
      required this.onTap,
      required this.onPlay,
      required this.onMore});
  final WebArticle item;
  final String age;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final void Function(Offset globalPos) onMore;

  @override
  Widget build(BuildContext context) {
    final dark = GatiPalette.of(context).dark;
    final r = sectionRamp('News', dark: dark);
    return GestureDetector(
      // Long-press anywhere on the card → the same anchored actions menu
      // the Paper articles get.
      onLongPressStart: (d) => onMore(d.globalPosition),
      child: Padding(
      padding: const EdgeInsets.fromLTRB(Gati.s5, 0, Gati.s5, 10),
      child: Container(
        decoration: BoxDecoration(
          color: r[0],
          borderRadius: BorderRadius.circular(Gati.rCard),
          border: Border.all(color: r[1].withValues(alpha: 0.07)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                              color: r[1])),
                      const SizedBox(height: 4),
                      Text(
                          age.isEmpty
                              ? item.source
                              : '${item.source} · $age',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: r[2])),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Builder(
                  builder: (btnCtx) => GestureDetector(
                    onTap: () {
                      final box =
                          btnCtx.findRenderObject()! as RenderBox;
                      onMore(box
                          .localToGlobal(box.size.center(Offset.zero)));
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.more_horiz, color: r[2], size: 20),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onPlay,
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                        color: kAccent, shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow,
                        color: kPaper, size: 20),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

// ── Latest stories: header toggle + source grid ─────────────────────────────

// "Latest stories" label + a list⇄grid toggle. List is the default; grid
// groups the stories into per-publisher tiles. Mirrors the newspaper screen's
// browse toggle so the two surfaces feel the same.
class _LatestHeader extends StatelessWidget {
  const _LatestHeader({
    required this.lang,
    required this.view,
    required this.showToggle,
    required this.onView,
  });
  final String lang;
  final String view;
  final bool showToggle;
  final void Function(String view) onView;

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gati.s5, 0, Gati.s5, Gati.s3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_t(lang, 'Latest stories', 'తాజా వార్తలు'),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: p.ink)),
          if (showToggle)
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                  color: p.chip, borderRadius: BorderRadius.circular(9)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _viewBtn(context, Icons.view_list_rounded, 'list'),
                _viewBtn(context, Icons.grid_view_rounded, 'grid'),
                const GatiFilterButton(),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _viewBtn(BuildContext context, IconData icon, String v) {
    final sel = view == v;
    return GestureDetector(
      onTap: () => onView(v),
      child: Container(
        width: 32,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? kAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(icon,
            size: 17, color: sel ? kPaper : GatiPalette.of(context).muted),
      ),
    );
  }
}

// Grid mode: one colored tile per publisher (NTV Telugu, HMTV, Big TV…) with a
// story count, like the newspaper's section tiles. Tapping a tile drills into
// that source — it filters the list back in list view.
class _SourceGrid extends StatelessWidget {
  const _SourceGrid({
    required this.articles,
    required this.lang,
    required this.onTapSource,
  });
  final List<WebArticle> articles;
  final String lang;
  final void Function(String source) onTapSource;

  // Cohesive per-source tints: cycle a few section ramps in first-seen order.
  static const _rampKeys = [
    'State', 'National', 'Business', 'District', 'Politics'
  ];

  @override
  Widget build(BuildContext context) {
    final dark = GatiPalette.of(context).dark;
    // Unique sources in first-seen order, with their story counts.
    final counts = <String, int>{};
    for (final a in articles) {
      if (a.source.trim().isEmpty) continue;
      counts[a.source] = (counts[a.source] ?? 0) + 1;
    }
    final sources = counts.keys.toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gati.s5),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.6,
        mainAxisSpacing: Gati.s3,
        crossAxisSpacing: Gati.s3,
        children: [
          for (var i = 0; i < sources.length; i++)
            _tile(sources[i], counts[sources[i]]!,
                sectionRamp(_rampKeys[i % _rampKeys.length], dark: dark)),
        ],
      ),
    );
  }

  Widget _tile(String source, int count, List<Color> r) {
    return GestureDetector(
      onTap: () => onTapSource(source),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration:
            BoxDecoration(color: r[0], borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.newspaper, color: r[1], size: 20),
          const Spacer(),
          Text(source,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w500, color: r[1])),
          const SizedBox(height: 2),
          Text(
              lang == 'te'
                  ? '$count కథనాలు'
                  : '$count ${count == 1 ? 'story' : 'stories'}',
              style: TextStyle(fontSize: 12, color: r[2])),
        ]),
      ),
    );
  }
}

// Shown above the list when a source tile was tapped: names the active
// publisher filter with a tap-to-clear ✕.
class _SourceFilterChip extends StatelessWidget {
  const _SourceFilterChip({
    required this.source,
    required this.count,
    required this.onClear,
  });
  final String source;
  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gati.s5, 0, Gati.s5, Gati.s2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: onClear,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Gati.accentSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('$source · $count',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: kAccent)),
              const SizedBox(width: 6),
              const Icon(Icons.close, size: 15, color: kAccent),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Small shared bits ───────────────────────────────────────────────────────



/// Tiny inline bilingual helper so the scaffold doesn't need new l10n keys yet.
String _t(String lang, String en, String te) => lang == 'te' ? te : en;

// Indian digit grouping (last 3, then pairs): 121418 → "1,21,418".


// One marquee segment for a market item, e.g. "నిఫ్టీ 23,865.75 ▼0.65%".


