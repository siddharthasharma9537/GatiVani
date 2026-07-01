import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../design/tokens.dart';
import '../design/section_colors.dart';
import '../models/newspaper_article.dart';
import '../services/cricket_service.dart';
import '../services/news_feed_service.dart';
import '../services/playback_service.dart';
import '../services/settings_provider.dart';
import '../widgets/mini_player.dart';

/// v2 landing — a discovery surface that sits in FRONT of the newspaper.
///
/// Layout (top → bottom):
///   • header (menu + title + search)
///   • breaking-news marquee ticker
///   • Stories row (horizontal bubbles)
///   • live cricket card (only while a match is live)
///   • Podcasts tiles
///   • Newspaper tile → opens the existing Today experience at /newspaper
///   • Latest stories list
///   • persistent mini-player
///
/// This screen does NOT touch the Today/newspaper UI — tapping the Newspaper
/// tile pushes /newspaper, which is the untouched HomeDrawerShell.
///
/// All content here is placeholder scaffolding. Real data wires in next:
///   - marquee + stories + latest  → RSS (PIB / Google News / TeluguOne)
///   - podcasts                     → AIR / Prasar Bharati direct MP3 feeds
///   - cricket                      → CricketData.org facts → Gemini → TTS
class LiveFeedScreen extends StatefulWidget {
  const LiveFeedScreen({super.key});

  @override
  State<LiveFeedScreen> createState() => _LiveFeedScreenState();
}

class _LiveFeedScreenState extends State<LiveFeedScreen> {
  // Until a CRICKET_API_KEY is configured, request the sample match so the
  // card + real Gemini Telugu commentary are demoable. Flip to false once the
  // key is set and the card will show only genuine live matches.
  static const bool _cricketMock = true;

  final _feed = NewsFeedService();
  final _cricketSvc = CricketService();
  List<NewsItem> _headlines = []; // marquee — Google News, diverse
  List<MarketItem> _markets = []; // marquee — indices + metals ticker
  List<WebArticle> _articles = []; // Latest stories — full-body, readable in-app
  CricketMatch? _cricket; // null when nothing is live
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
    final marketsF = _feed.fetchMarkets();
    final headlinesF = _feed.fetch(topic: 'top', limit: 8);
    final articlesF = _feed.fetchArticles(limit: 12);
    final cricketF = _cricketSvc.fetch(mock: _cricketMock);
    final markets = await marketsF;
    final headlines = await headlinesF;
    final articles = await articlesF;
    final cricket = await cricketF;
    if (!mounted) return;
    setState(() {
      _markets = markets;
      _headlines = headlines;
      _articles = articles;
      _cricket = cricket;
      _loading = false;
    });
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

  List<String> get _marqueeTitles =>
      _headlines.take(6).map((e) => e.title).toList();

  // Open the full story in-app (ReaderStore carries it across the route).
  void _openReader(WebArticle a) {
    ReaderStore.i.current = a;
    context.push('/reader');
  }

  // Which category bubble is currently loading its bulletin (shows a spinner).
  String? _loadingTopic;

  // Stable per-topic ids so a category's bulletin audio overwrites one storage
  // file instead of piling up, while still re-synthesizing fresh each session
  // (the cache is DB-row-based, and these ids have no article row).
  static const _catUuids = <String, String>{
    'top': 'a0000000-0000-4000-8000-000000000001',
    'politics': 'a0000000-0000-4000-8000-000000000002',
    'cricket': 'a0000000-0000-4000-8000-000000000003',
    'cinema': 'a0000000-0000-4000-8000-000000000004',
    'business': 'a0000000-0000-4000-8000-000000000005',
    'weather': 'a0000000-0000-4000-8000-000000000006',
    'national': 'a0000000-0000-4000-8000-000000000007',
  };

  // Tap a Stories bubble → narrate a short spoken bulletin of that category's
  // current top headlines, via the shared player.
  Future<void> _playCategory(String topic, String label) async {
    if (_loadingTopic != null) return;
    setState(() => _loadingTopic = topic);
    try {
      final items = await _feed.fetch(topic: topic, limit: 6);
      if (!mounted || items.isEmpty) return;
      final heads = items.take(5).map((e) => e.title.trim()).join('. ');
      final art = NewspaperArticle(
        id: _catUuids[topic] ?? 'a0000000-0000-4000-8000-000000000000',
        title: '$label తాజా వార్తలు',
        content: '$heads.',
        preview: heads,
        category: label,
        estimatedDurationSeconds: NewspaperArticle.estimateDuration(heads),
        readingStyle: 'news_anchor',
      );
      await PlaybackService.i.playOne(art);
    } finally {
      if (mounted) setState(() => _loadingTopic = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final lang = context.watch<SettingsProvider>().lang;
    // Market ticker leads the marquee, then the news headlines.
    final marketStrs = _markets.map((m) => _marketString(m, lang)).toList();
    final combined = [...marketStrs, ..._marqueeTitles];
    final marquee = combined.isEmpty
        ? [_t(lang, 'Loading…', 'లోడ్ అవుతోంది…')]
        : combined;
    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _Header(lang: lang),
          _BreakingMarquee(items: marquee),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: kAccent,
              child: ListView(
                padding: const EdgeInsets.only(bottom: Gati.s6),
                children: [
                  const SizedBox(height: Gati.s4),
                  _StoriesRow(
                    categories: _categories,
                    lang: lang,
                    loadingTopic: _loadingTopic,
                    onTap: _playCategory,
                  ),
                  if (_cricket != null) ...[
                    const SizedBox(height: Gati.s5),
                    _SectionLabel(_t(lang, 'Live now', 'ఇప్పుడు లైవ్')),
                    _CricketCard(
                      match: _cricket!,
                      onListen: () => _playCommentary(_cricket!),
                    ),
                  ],
                  const SizedBox(height: Gati.s5),
                  _SectionLabel(_t(lang, 'Podcasts', 'పాడ్‌క్యాస్ట్‌లు')),
                  _PodcastsGrid(items: _demoPodcasts),
                  const SizedBox(height: Gati.s5),
                  _NewspaperTile(lang: lang),
                  const SizedBox(height: Gati.s5),
                  _LatestHeader(
                    lang: lang,
                    view: _view,
                    showToggle: !_loading && _articles.isNotEmpty,
                    onView: (v) => setState(() {
                      _view = v;
                      _sourceSel = null; // manual toggle clears any drill-down
                    }),
                  ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(Gati.s6),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: kAccent),
                        ),
                      ),
                    )
                  else if (_articles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Gati.s5, vertical: Gati.s3),
                      child: Text(
                          _t(lang, 'No stories right now. Pull to refresh.',
                              'వార్తలు లేవు. రిఫ్రెష్ చేయండి.'),
                          style: TextStyle(fontSize: 13, color: p.muted)),
                    )
                  else if (_view == 'grid')
                    _SourceGrid(
                      articles: _articles,
                      lang: lang,
                      onTapSource: (src) => setState(() {
                        _sourceSel = src;
                        _view = 'list';
                      }),
                    )
                  else ...[
                    if (_sourceSel != null)
                      _SourceFilterChip(
                        source: _sourceSel!,
                        count: _articles
                            .where((a) => a.source == _sourceSel)
                            .length,
                        onClear: () => setState(() => _sourceSel = null),
                      ),
                    ...(_sourceSel == null
                            ? _articles
                            : _articles
                                .where((a) => a.source == _sourceSel)
                                .toList())
                        .map((it) => _StoryRow(
                              item: it,
                              age: relativeAge(it.pubDate, lang),
                              onTap: () => _openReader(it),
                            )),
                  ],
                ],
              ),
            ),
          ),
          MiniPlayer(onExpand: () => context.push('/player')),
        ]),
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.lang});
  final String lang;

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gati.s5, Gati.s3, Gati.s4, Gati.s2),
      child: Row(children: [
        _iconBtn(p, Icons.menu, () => context.push('/menu')),
        const SizedBox(width: Gati.s3),
        Text('GatiVani',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w500, color: p.ink)),
        const Spacer(),
        _iconBtn(p, Icons.search, () => context.push('/search')),
      ]),
    );
  }

  Widget _iconBtn(GatiPalette p, IconData icon, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: p.chip, borderRadius: BorderRadius.circular(Gati.rChip)),
          child: Icon(icon, size: 20, color: p.ink),
        ),
      );
}

// ── Breaking-news marquee ───────────────────────────────────────────────────

class _BreakingMarquee extends StatefulWidget {
  const _BreakingMarquee({required this.items});
  final List<String> items;

  @override
  State<_BreakingMarquee> createState() => _BreakingMarqueeState();
}

class _BreakingMarqueeState extends State<_BreakingMarquee>
    with SingleTickerProviderStateMixin {
  // A fixed ⚡ badge sits on the left; ONLY the headline band scrolls. The band
  // is the full run of headlines at their natural width (measured once), drawn
  // twice back-to-back and translated by exactly one band-width for a seamless
  // loop. Speed is a constant px/sec (duration ∝ width), so the scroll feels
  // the same no matter how many headlines there are — the previous version
  // clipped the text to one screen-width and used a fixed duration, which made
  // the motion inconsistent and hid later headlines.
  static const _style =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kPaper);
  static const _pxPerSec = 55.0;

  late final AnimationController _c;
  String _line = '';
  double _bandWidth = 0;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 20));
    _sync();
    // Flutter web loads the Telugu font asynchronously. If we measure the band
    // width before it's ready, TextPainter reports a too-small width using the
    // fallback font — the two copies then overlap and the loop restarts after
    // only a few headlines. Re-measure whenever a system font finishes loading.
    PaintingBinding.instance.systemFonts.addListener(_resyncOnFont);
  }

  void _resyncOnFont() {
    if (mounted) setState(_sync);
  }

  @override
  void didUpdateWidget(_BreakingMarquee old) {
    super.didUpdateWidget(old);
    if (_composeLine(old.items) != _composeLine(widget.items)) _sync();
  }

  // Headlines separated by a bullet, with a trailing gap so the loop seam keeps
  // a separator between the last and first item.
  String _composeLine(List<String> items) =>
      '${items.map((s) => s.trim()).join('   •   ')}   •   ';

  void _sync() {
    _line = _composeLine(widget.items);
    final tp = TextPainter(
      text: TextSpan(text: _line, style: _style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    _bandWidth = tp.width;
    final secs = (_bandWidth / _pxPerSec).clamp(6.0, 180.0);
    _c
      ..stop()
      ..duration = Duration(milliseconds: (secs * 1000).round())
      ..repeat();
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_resyncOnFont);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      color: kAccent,
      child: Row(children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: Gati.s3),
          child: Icon(Icons.bolt, size: 16, color: kPaper),
        ),
        Expanded(
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final dx = -_c.value * _bandWidth;
                return Stack(clipBehavior: Clip.none, children: [
                  Positioned(
                      left: dx, top: 0, bottom: 0, width: _bandWidth, child: _band()),
                  Positioned(
                      left: dx + _bandWidth,
                      top: 0,
                      bottom: 0,
                      width: _bandWidth,
                      child: _band()),
                ]);
              },
            ),
          ),
        ),
      ]),
    );
  }

  Widget _band() => Align(
        alignment: Alignment.centerLeft,
        child: Text(_line,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: _style),
      );
}

// ── Stories row ─────────────────────────────────────────────────────────────

class _StoriesRow extends StatelessWidget {
  const _StoriesRow({
    required this.categories,
    required this.lang,
    required this.loadingTopic,
    required this.onTap,
  });
  final List<({String en, String te, String topic, String section})> categories;
  final String lang;
  final String? loadingTopic;
  final void Function(String topic, String label) onTap;

  @override
  Widget build(BuildContext context) {
    final dark = GatiPalette.of(context).dark;
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gati.s5),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: Gati.s4),
        itemBuilder: (context, i) {
          final it = categories[i];
          final label = lang == 'te' ? it.te : it.en;
          final r = sectionRamp(it.section, dark: dark);
          final loading = loadingTopic == it.topic;
          return GestureDetector(
            onTap: () => onTap(it.topic, label),
            child: Column(children: [
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: r[0],
                  shape: BoxShape.circle,
                  border: Border.all(color: kAccent, width: 2),
                ),
                child: loading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: r[1]),
                      )
                    : Icon(Icons.play_arrow, color: r[1], size: 24),
              ),
              const SizedBox(height: Gati.s1),
              SizedBox(
                width: 64,
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11.5, color: GatiPalette.of(context).muted)),
              ),
            ]),
          );
        },
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gati.s5, Gati.s2, Gati.s5, 0),
      child: GestureDetector(
        onTap: onListen, // tap → narrate the AI Telugu commentary
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
                const Icon(Icons.play_circle_fill, color: kAccent, size: 34),
              ]),
              // The AI-generated Telugu commentary line.
              if (match.commentary.trim().isNotEmpty) ...[
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

// ── Podcasts grid ───────────────────────────────────────────────────────────

class _PodcastsGrid extends StatelessWidget {
  const _PodcastsGrid({required this.items});
  final List<({String title, String meta, String section})> items;

  @override
  Widget build(BuildContext context) {
    final dark = GatiPalette.of(context).dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gati.s5),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: Gati.s3,
        crossAxisSpacing: Gati.s3,
        childAspectRatio: 1.55,
        children: items.map((it) {
          final r = sectionRamp(it.section, dark: dark);
          return GestureDetector(
            // Placeholder until real AIR / Prasar Bharati MP3 feeds are wired.
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Podcasts coming soon'),
                duration: Duration(seconds: 2),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(Gati.s4),
              decoration: BoxDecoration(
                  color: r[0], borderRadius: BorderRadius.circular(Gati.rCard)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.graphic_eq, color: r[1], size: 22),
                  const Spacer(),
                  Text(it.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: r[1])),
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.play_arrow, size: 14, color: r[2]),
                    const SizedBox(width: 2),
                    Text(it.meta,
                        style: TextStyle(fontSize: 12, color: r[2])),
                  ]),
                ],
              ),
            ),
          );
        }).toList(),
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
  const _StoryRow(
      {required this.item, required this.age, required this.onTap});
  final WebArticle item;
  final String age;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gati.s5, Gati.s3, Gati.s5, Gati.s3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14.5, height: 1.3, color: p.ink)),
                const SizedBox(height: Gati.s1),
                Row(children: [
                  Flexible(
                    child: Text(item.source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: kAccent)),
                  ),
                  if (age.isNotEmpty)
                    Text('  ·  $age',
                        style: TextStyle(fontSize: 11.5, color: p.muted)),
                ]),
              ],
            ),
          ),
          const SizedBox(width: Gati.s3),
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: Gati.accentSoft, shape: BoxShape.circle),
            child: const Icon(Icons.chevron_right, color: kAccent, size: 20),
          ),
        ]),
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
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                  color: p.muted)),
          if (showToggle)
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                  color: p.chip, borderRadius: BorderRadius.circular(9)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _viewBtn(context, Icons.view_list_rounded, 'list'),
                _viewBtn(context, Icons.grid_view_rounded, 'grid'),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gati.s5, 0, Gati.s5, Gati.s3),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
              color: GatiPalette.of(context).muted)),
    );
  }
}

/// Tiny inline bilingual helper so the scaffold doesn't need new l10n keys yet.
String _t(String lang, String en, String te) => lang == 'te' ? te : en;

// Indian digit grouping (last 3, then pairs): 121418 → "1,21,418".
String _inr(double v, {int decimals = 0}) {
  final neg = v < 0;
  final fixed = v.abs().toStringAsFixed(decimals);
  final dot = fixed.indexOf('.');
  var intPart = dot >= 0 ? fixed.substring(0, dot) : fixed;
  final dec = dot >= 0 ? fixed.substring(dot) : '';
  String grouped;
  if (intPart.length <= 3) {
    grouped = intPart;
  } else {
    final last3 = intPart.substring(intPart.length - 3);
    var rest = intPart.substring(0, intPart.length - 3);
    final chunks = <String>[];
    while (rest.length > 2) {
      chunks.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) chunks.insert(0, rest);
    grouped = '${chunks.join(',')},$last3';
  }
  return '${neg ? '-' : ''}$grouped$dec';
}

// One marquee segment for a market item, e.g. "నిఫ్టీ 23,865.75 ▼0.65%".
String _marketString(MarketItem m, String lang) {
  const labels = {
    'nifty': ['Nifty', 'నిఫ్టీ'],
    'sensex': ['Sensex', 'సెన్సెక్స్'],
    'gold': ['Gold', 'బంగారం'],
    'silver': ['Silver', 'వెండి'],
  };
  final l = labels[m.key];
  final label = l == null ? m.key : (lang == 'te' ? l[1] : l[0]);
  final chg = '${m.changePct >= 0 ? '▲' : '▼'}${m.changePct.abs().toStringAsFixed(2)}%';
  switch (m.key) {
    case 'gold':
      return '$label ₹${_inr(m.value)}/10g $chg';
    case 'silver':
      return '$label ₹${_inr(m.value)}/kg $chg';
    default:
      return '$label ${_inr(m.value, decimals: 2)} $chg';
  }
}

// ── Placeholder content (Stories + Podcasts await audio sources) ────────────
// Marquee + Latest stories are now live (feeds-news). These two still await
// their audio backends: Stories = AIR clips, Podcasts = AIR/PB MP3 feeds.

// Stories bubbles → feeds-news topics. Tap plays a spoken headline bulletin.
const _categories =
    <({String en, String te, String topic, String section})>[
  (en: 'Top', te: 'తాజా', topic: 'top', section: 'general'),
  (en: 'Politics', te: 'రాజకీయం', topic: 'politics', section: 'politics'),
  (en: 'Cricket', te: 'క్రికెట్', topic: 'cricket', section: 'sports'),
  (en: 'Cinema', te: 'సినిమా', topic: 'cinema', section: 'entertainment'),
  (en: 'Business', te: 'వ్యాపారం', topic: 'business', section: 'general'),
  (en: 'Weather', te: 'వాతావరణం', topic: 'weather', section: 'general'),
  (en: 'National', te: 'జాతీయం', topic: 'national', section: 'politics'),
];

const _demoPodcasts = <({String title, String meta, String section})>[
  (title: 'AIR Telugu News', meta: '8 min · today', section: 'general'),
  (title: 'Mann Ki Baat', meta: '30 min · monthly', section: 'politics'),
  (title: 'Bhagavad Gita', meta: '12 min · daily', section: 'devotional'),
  (title: 'Cinema Talk', meta: '18 min · weekly', section: 'entertainment'),
];
