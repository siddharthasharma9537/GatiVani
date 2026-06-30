import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../design/tokens.dart';
import '../design/section_colors.dart';
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
class LiveFeedScreen extends StatelessWidget {
  const LiveFeedScreen({super.key});

  // Toggle until the live-score backend exists; hides the cricket card on
  // rest days so it never shows a stale match.
  static const bool _cricketLive = true;

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final lang = context.watch<SettingsProvider>().lang;
    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _Header(lang: lang),
          const _BreakingMarquee(items: _demoBreaking),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: Gati.s6),
              children: [
                const SizedBox(height: Gati.s4),
                _StoriesRow(items: _demoStories),
                if (_cricketLive) ...[
                  const SizedBox(height: Gati.s5),
                  _SectionLabel(_t(lang, 'Live now', 'ఇప్పుడు లైవ్')),
                  const _CricketCard(),
                ],
                const SizedBox(height: Gati.s5),
                _SectionLabel(_t(lang, 'Podcasts', 'పాడ్‌క్యాస్ట్‌లు')),
                _PodcastsGrid(items: _demoPodcasts),
                const SizedBox(height: Gati.s5),
                _NewspaperTile(lang: lang),
                const SizedBox(height: Gati.s5),
                _SectionLabel(_t(lang, 'Latest stories', 'తాజా వార్తలు')),
                ..._demoLatest.map((s) => _StoryRow(story: s)),
              ],
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
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 28))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Join the headlines into one long string with separators, then translate
    // it leftward across a clipped strip. A lightweight, dependency-free
    // marquee — content scrolls right-to-left and loops seamlessly.
    final line = '${widget.items.map((s) => '  •  $s').join()}   ';
    return Container(
      height: 34,
      color: kAccent,
      child: ClipRect(
        child: LayoutBuilder(builder: (context, cons) {
          return AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              // Two copies back-to-back so the loop has no visible gap.
              final dx = -_c.value * cons.maxWidth;
              return Stack(children: [
                Transform.translate(
                    offset: Offset(dx, 0), child: _strip(line, cons.maxWidth)),
                Transform.translate(
                    offset: Offset(dx + cons.maxWidth, 0),
                    child: _strip(line, cons.maxWidth)),
              ]);
            },
          );
        }),
      ),
    );
  }

  Widget _strip(String text, double width) => SizedBox(
        width: width,
        child: Row(children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Gati.s3),
            child: Icon(Icons.bolt, size: 16, color: kPaper),
          ),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: kPaper)),
          ),
        ]),
      );
}

// ── Stories row ─────────────────────────────────────────────────────────────

class _StoriesRow extends StatelessWidget {
  const _StoriesRow({required this.items});
  final List<({String label, String section})> items;

  @override
  Widget build(BuildContext context) {
    final dark = GatiPalette.of(context).dark;
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gati.s5),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: Gati.s4),
        itemBuilder: (context, i) {
          final it = items[i];
          final r = sectionRamp(it.section, dark: dark);
          return GestureDetector(
            // TODO: tap → auto-play this category's latest audio clip.
            onTap: () {},
            child: Column(children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: r[0],
                  shape: BoxShape.circle,
                  border: Border.all(color: kAccent, width: 2),
                ),
                child: Icon(Icons.podcasts, color: r[1], size: 22),
              ),
              const SizedBox(height: Gati.s1),
              SizedBox(
                width: 64,
                child: Text(it.label,
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
  const _CricketCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gati.s5, Gati.s2, Gati.s5, 0),
      child: GestureDetector(
        // TODO: tap → over-by-over AI Telugu commentary screen.
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.all(Gati.s4),
          decoration: BoxDecoration(
            color: kInk,
            borderRadius: BorderRadius.circular(Gati.rCard),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  color: kAccent, shape: BoxShape.circle),
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
                    const Text('LIVE  ·  IND vs AUS',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Gati.onInkMuted)),
                  ]),
                  const SizedBox(height: Gati.s1),
                  const Text('IND 234/4  ·  18.2 ov',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Gati.onInk)),
                ],
              ),
            ),
            const Icon(Icons.play_circle_fill, color: kAccent, size: 34),
          ]),
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
            // TODO: tap → play this podcast feed's latest episode.
            onTap: () {},
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
  const _StoryRow({required this.story});
  final ({String title, String source, String age}) story;

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    return GestureDetector(
      // TODO: tap → article detail with audio play button.
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gati.s5, Gati.s3, Gati.s5, Gati.s3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(story.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14.5, height: 1.3, color: p.ink)),
                const SizedBox(height: Gati.s1),
                Row(children: [
                  Text(story.source,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: kAccent)),
                  Text('  ·  ${story.age}',
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
            child: const Icon(Icons.play_arrow, color: kAccent, size: 18),
          ),
        ]),
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

// ── Demo content (replace with live feeds) ──────────────────────────────────

const _demoBreaking = <String>[
  'Heavy rain alert issued for coastal Andhra districts',
  'Assembly session begins today; key bills tabled',
  'India announce playing XI for the second Test',
  'Gold prices ease slightly in Hyderabad market',
];

const _demoStories = <({String label, String section})>[
  (label: 'Politics', section: 'politics'),
  (label: 'Cricket', section: 'sports'),
  (label: 'Weather', section: 'general'),
  (label: 'Devotional', section: 'devotional'),
  (label: 'Cinema', section: 'entertainment'),
  (label: 'AIR News', section: 'general'),
];

const _demoPodcasts = <({String title, String meta, String section})>[
  (title: 'AIR Telugu News', meta: '8 min · today', section: 'general'),
  (title: 'Mann Ki Baat', meta: '30 min · monthly', section: 'politics'),
  (title: 'Bhagavad Gita', meta: '12 min · daily', section: 'devotional'),
  (title: 'Cinema Talk', meta: '18 min · weekly', section: 'entertainment'),
];

const _demoLatest = <({String title, String source, String age})>[
  (
    title: 'State cabinet clears new irrigation project for Rayalaseema',
    source: 'PIB',
    age: '5m'
  ),
  (
    title: 'Hyderabad metro phase II gets central nod',
    source: 'Google News',
    age: '22m'
  ),
  (
    title: 'Telugu film industry announces relief fund for daily workers',
    source: 'TeluguOne',
    age: '1h'
  ),
];
