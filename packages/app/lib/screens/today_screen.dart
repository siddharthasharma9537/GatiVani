import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../config/districts.dart';
import '../l10n/strings.dart';
import '../models/newspaper_article.dart';
import '../services/document_service.dart';
import '../services/edition_store.dart';
import '../services/news_feed_service.dart';
import '../services/playback_service.dart';
import '../services/settings_provider.dart';
import '../design/components/gati_article_sheet.dart';
import '../design/components/gati_filter_button.dart';
import '../design/components/gati_masthead.dart';
import '../design/components/gati_snap_scroll.dart';
import '../design/section_colors.dart';
import '../design/tokens.dart';
import '../widgets/article_card.dart';
import '../widgets/edition_masthead.dart';
import '../widgets/news_ticker.dart';

/// Reimagined home: today's edition front and center, live processing card,
/// in-place category chips, persistent mini-player. Upload via FAB.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, this.onMenu});
  // When hosted inside the reveal drawer, the header menu button toggles the
  // drawer instead of pushing a /menu route.
  final VoidCallback? onMenu;
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final _svc = DocumentService();
  List<NewspaperArticle> _articles = [];
  String _editionTitle = '';
  String? _category;
  int? _pageSel;
  String _view = 'list'; // 'tiles' | 'list' — list is the default browse view
  // Multi-select (list view): batch articles into the Up Next queue.
  bool _selectMode = false;
  final Set<String> _selected = {};
  EditionJob? _job;
  EditionJobStatus? _jobStatus;
  Timer? _poll;
  String? _error;
  bool _uploading = false;
  double _uploadProgress = 0;

  bool _featuredLoaded = false;

  Offset _pressPos = Offset.zero; // last tap-down, anchors long-press menus

  @override
  void initState() {
    super.initState();
    _loadFeatured();
  }

  // Open onto real content: load the featured/most-recent edition so the app is
  // never an empty screen. Skipped once the user starts their own upload.
  Future<void> _loadFeatured() async {
    final ed = await _svc.fetchFeaturedEdition();
    if (ed == null || !mounted || _job != null || _articles.isNotEmpty) return;
    EditionStore.i.articles = ed.articles;
    setState(() {
      _articles = ed.articles;
      _editionTitle = ed.title;
      _featuredLoaded = true;
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _upload() async {
    final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    setState(() {
      _error = null;
      _uploading = true;
      _uploadProgress = 0;
      _editionTitle = f.name.replaceAll(RegExp(r'\.(pdf|jpe?g|png)$'), '');
      _articles = [];
      _job = null;
      _jobStatus = null;
    });
    try {
      final job = await _svc.startEdition(
          filePath: f.path ?? '',
          filename: f.name,
          fileBytes: f.bytes,
          onProgress: (p) {
            if (mounted) setState(() => _uploadProgress = p);
          });
      setState(() {
        _job = job;
        _uploading = false;
      });
      _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    } catch (e) {
      setState(() {
        _error = e.toString();
        _uploading = false;
      });
    }
  }

  // Tapping an article opens its TEXT (same reader as Live stories, with a
  // "Listen" button). Audio starts only from the ▶ — and in the mini-player.
  void _openArticle(NewspaperArticle a) {
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

  // The row's ▶ → play in place (mini-player), like a track list.
  void _playInline(NewspaperArticle a) {
    PlaybackService.i.playOne(a);
  }

  // Play a whole section/filter back-to-back, like a playlist.
  void _playList(List<NewspaperArticle> list) {
    if (list.isEmpty) return;
    PlaybackService.i.playAll(list);
  }

  // Sensible chip order: hard news first, the catch-all "News" last.
  static const _sectionOrder = [
    'Editorial', 'Opinion', 'State', 'National', 'International', 'District',
    'Politics', 'Judiciary', 'Crime', 'Business', 'Sports', 'Health', 'Sci-Tech',
    'Education', 'Agriculture', 'Entertainment', 'Devotional', 'Trending', 'News',
  ];
  int _sectionRank(String s) {
    final i = _sectionOrder.indexOf(s);
    return i < 0 ? _sectionOrder.length : i;
  }

  // The EN/తె toggle that used to live here moved to the menu drawer's
  // Language section — the standardized GatiMasthead keeps headers uniform
  // across tabs.

  // List ⇄ tiles toggle, like Google Drive/Files.
  Widget _viewBtn(IconData icon, String view) {
    final sel = _view == view;
    return GestureDetector(
      onTap: () => setState(() => _view = view),
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

  // Drill down: tapping a section tile opens that section's article list. The
  // section name goes in the URL so the browser Back button can return here;
  // the articles are resolved from EditionStore (extra isn't back-safe).
  void _openSection(String section) {
    context.push('/section/${Uri.encodeComponent(section)}');
  }

  // A colored section tile: tap the body → open the section; tap the ▶ → play
  // the whole section as a playlist.
  Widget _sectionTile(String section, int count, List<NewspaperArticle> arts) {
    final lang = context.watch<SettingsProvider>().lang;
    final r = sectionRamp(section, dark: GatiPalette.of(context).dark);
    return GestureDetector(
      onTap: () => _openSection(section),
      child: Container(
        decoration: BoxDecoration(
            color: r[0], borderRadius: BorderRadius.circular(Gati.rCard)),
        padding: const EdgeInsets.all(13),
        child: Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sectionLabel(section, lang),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500, color: r[1])),
            const SizedBox(height: 2),
            Text(storyCount(count, lang),
                style: TextStyle(fontSize: 12, color: r[2])),
          ]),
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () => _playList(arts),
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration:
                    const BoxDecoration(color: kAccent, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow, color: kPaper, size: 15),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // "Listen to briefing" narrates the short version of the top dozen picks
  // instead of all ~175 articles. One tap never synthesizes the whole edition,
  // and the dozen it does play are cached, so it's cents and free on replay.
  static const _briefingCount = 12;
  void _playBriefing() {
    final ranked = [..._articles]
      ..sort((a, b) {
        final r = _sectionRank(a.category).compareTo(_sectionRank(b.category));
        return r != 0 ? r : a.page.compareTo(b.page);
      });
    final pick = ranked.take(_briefingCount).toList();
    if (pick.isEmpty) return;
    PlaybackService.i.playAll(pick, brief: true); // narrate the short version
  }

  // ── Multi-select → Up Next queue ───────────────────────────────────────────
  void _toggleSelect(String id) => setState(() {
        if (!_selected.remove(id)) _selected.add(id);
      });

  void _exitSelect() => setState(() {
        _selectMode = false;
        _selected.clear();
      });

  void _toast(String lang, String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(lang, key)), duration: const Duration(seconds: 2)));
  }

  Widget _selectionBar(
      GatiPalette p, String lang, List<NewspaperArticle> visible) {
    final picked = visible.where((a) => _selected.contains(a.id)).toList();
    final n = picked.length;
    return Material(
      color: p.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(children: [
            Text('$n ${tr(lang, 'selected_count')}',
                style: TextStyle(
                    color: p.ink, fontSize: 13, fontWeight: FontWeight.w500)),
            const Spacer(),
            TextButton(
              onPressed: n == 0
                  ? null
                  : () {
                      PlaybackService.i.playNext(picked);
                      _exitSelect();
                      _toast(lang, 'added_play_next');
                    },
              child: Text(tr(lang, 'play_next'),
                  style: const TextStyle(color: kAccent)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: kAccent, foregroundColor: kPaper),
              onPressed: n == 0
                  ? null
                  : () {
                      PlaybackService.i.addToQueue(picked);
                      _exitSelect();
                      _toast(lang, 'added_queue');
                    },
              child: Text(tr(lang, 'add_to_queue')),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Long-press → per-article options ───────────────────────────────────────
  // ── Front page (Editorial / Editor's pick) ──────────────────────────────────
  // The editor's pick = the day's lead: the paper's own editorial if present,
  // else the front-page lead (earliest page, longest story).
  NewspaperArticle? get _editorsPick {
    if (_articles.isEmpty) return null;
    final ed = _articles.where((a) => a.category == 'Editorial').toList();
    final pool = ed.isNotEmpty ? ed : _articles;
    final sorted = [...pool]
      ..sort((a, b) {
        final p = a.page.compareTo(b.page);
        return p != 0 ? p : b.spokenText.length.compareTo(a.spokenText.length);
      });
    return sorted.first;
  }

  // The paper's fixed opinion pages, in editorial order.
  List<NewspaperArticle> get _opinionRail {
    final list = _articles
        .where((a) => a.category == 'Editorial' || a.category == 'Opinion')
        .toList()
      ..sort((a, b) => _sectionRank(a.category).compareTo(_sectionRank(b.category)));
    return list;
  }

  Widget _frontPageBand(GatiPalette p, String lang) {
    final pick = _editorsPick;
    if (pick == null) return const SizedBox.shrink();
    final rail = _opinionRail.where((a) => a.id != pick.id).toList();
    // When the lead itself is the paper's editorial/opinion, the whole band is
    // one "Editorial & Opinion" group (hero + rail under it). When the lead is a
    // news story, it's the "Front page" lead, and any opinion pages get their
    // own labelled rail beneath.
    final pickIsOpinion =
        pick.category == 'Editorial' || pick.category == 'Opinion';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(tr(lang, pickIsOpinion ? 'editorial_opinion' : 'front_page'),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: p.ink)),
      ),
      _editorsPickCard(p, lang, pick),
      if (rail.isNotEmpty) ...[
        const SizedBox(height: 12),
        if (!pickIsOpinion)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Text(tr(lang, 'editorial_opinion'),
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: p.muted)),
          ),
        SizedBox(
          height: 134,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: rail.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _opinionCard(p, lang, rail[i]),
          ),
        ),
      ],
      const SizedBox(height: 18),
    ]);
  }

  Widget _editorsPickCard(GatiPalette p, String lang, NewspaperArticle a) {
    final r = sectionRamp(a.category, dark: p.dark);
    final mins = (a.estimatedDurationSeconds / 60).ceil();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Gati.rCard),
        onTap: () => _openArticle(a),
        onTapDown: (d) => _pressPos = d.globalPosition,
        onLongPress: () => showGatiArticleMenu(context, _pressPos, a,
            onRead: () => _openArticle(a)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: r[0],
            borderRadius: BorderRadius.circular(Gati.rCard),
            border: Border.all(color: r[1].withValues(alpha: 0.10)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.star_rounded, size: 15, color: kAccent),
              const SizedBox(width: 5),
              Text(tr(lang, 'editors_pick').toUpperCase(),
                  style: const TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                      color: kAccent)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                    color: r[1].withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(sectionLabel(a.category, lang),
                    style: TextStyle(
                        fontSize: 11,
                        color: r[1],
                        fontWeight: FontWeight.w500)),
              ),
            ]),
            const SizedBox(height: 12),
            Text(a.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 18,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: r[1])),
            const SizedBox(height: 12),
            Row(children: [
              GestureDetector(
                onTap: () => _playInline(a),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: const BoxDecoration(
                      color: kAccent,
                      borderRadius: BorderRadius.all(Radius.circular(22))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.play_arrow_rounded,
                        color: kPaper, size: 19),
                    const SizedBox(width: 4),
                    Text(tr(lang, 'play'),
                        style: const TextStyle(
                            color: kPaper,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Text('p${a.page} · $mins ${tr(lang, 'min')}',
                  style: TextStyle(fontSize: 12.5, color: r[2])),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _opinionCard(GatiPalette p, String lang, NewspaperArticle a) {
    final r = sectionRamp(a.category, dark: p.dark);
    return GestureDetector(
      onTap: () => _openArticle(a),
      onLongPressStart: (d) => showGatiArticleMenu(context, d.globalPosition, a,
          onRead: () => _openArticle(a)),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: r[0],
            borderRadius: BorderRadius.circular(Gati.rCard),
            border: Border.all(color: r[1].withValues(alpha: 0.08))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(sectionLabel(a.category, lang).toUpperCase(),
              style: const TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 0.4,
                  color: kAccent,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Expanded(
            child: Text(a.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, height: 1.3, color: r[1])),
          ),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.play_arrow_rounded, size: 16, color: kAccent),
            const SizedBox(width: 3),
            Text(tr(lang, 'play'),
                style: TextStyle(fontSize: 11.5, color: p.muted)),
          ]),
        ]),
      ),
    );
  }

  Future<void> _refresh() async {
    final job = _job;
    if (job == null) return;
    try {
      final st = await _svc.pollEdition(job.jobId);
      final arts = await _svc.fetchEditionArticles(job.newspaperId);
      EditionStore.i.articles = arts;
      setState(() {
        _jobStatus = st;
        _articles = arts;
      });
      if (st.isDone) _poll?.cancel();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().lang;
    final p = GatiPalette.of(context);
    final cats = <String, int>{};
    final pages = <int, int>{};
    for (final a in _articles) {
      cats[a.category] = (cats[a.category] ?? 0) + 1;
      pages[a.page] = (pages[a.page] ?? 0) + 1;
    }
    final pageKeys = pages.keys.toList()..sort();
    final catKeys = cats.keys.toList()
      ..sort((a, b) => _sectionRank(a).compareTo(_sectionRank(b)));
    var visible = _articles
        .where((a) => _pageSel == null || a.page == _pageSel)
        .where((a) => _category == null || a.category == _category)
        .toList();
    // District preference (filter dropdown / Vāni): pin the district's
    // articles first, or show only them — same behavior as Live stories.
    final settings = context.watch<SettingsProvider>();
    final district = districtByEn(settings.district);
    if (district != null) {
      bool m(NewspaperArticle a) =>
          district.matches('${a.title} ${a.content}');
      if (settings.districtOnly) {
        visible = visible.where(m).toList();
      } else if (settings.feedSort == 'location') {
        final hit = visible.where(m).toList();
        if (hit.isNotEmpty) {
          visible = [...hit, ...visible.where((a) => !m(a))];
        }
      }
    }
    final st = _jobStatus;
    // First-run / empty state shows the hero "Upload edition" CTA — hide the FAB
    // then so there aren't two upload buttons. The FAB returns once an edition
    // is loaded, as the persistent "add another" action.
    final showHero = !_uploading && _articles.isEmpty && st == null;

    final edition = !showHero && !_uploading && (st == null || st.isDone) &&
        _articles.isNotEmpty;

    return Scaffold(
      backgroundColor: p.paper,
      // Upload lives as a simple "+" floating above the Vāni button —
      // Paper tab only. Hidden while the hero card IS the upload CTA.
      floatingActionButton: showHero
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 92),
              child: FloatingActionButton.small(
                heroTag: 'paper_upload',
                backgroundColor: kAccent,
                foregroundColor: kPaper,
                elevation: 2,
                onPressed: _upload,
                child: const Icon(Icons.add),
              ),
            ),
      body: SafeArea(
        child: Column(children: [
          GatiMasthead(lang: lang, actions: [
            GatiHeaderButton(
                icon: Icons.search, onTap: () => context.push('/search')),
          ]),
          const NewsTicker(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(_error!,
                  style: const TextStyle(color: kAccent, fontSize: 12.5)),
            ),
          if (edition)
            // Section-snap scrolling (§8): sections keep natural heights (no
            // page gaps), the scroll settles at each section's top, and the
            // article list scrolls INSIDE its section.
            Expanded(
              child: LayoutBuilder(
                builder: (context, cons) => GatiSnapScroll(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  sections: [
                    EditionMasthead(
                      rawTitle: _editionTitle,
                      articleCount: _articles.length,
                      pageCount: pages.length,
                      onListen: _playBriefing,
                    ),
                    _frontPageBand(p, lang),
                    SizedBox(
                      height: cons.maxHeight - 16,
                      child: _allArticlesSection(
                          p, lang, catKeys, cats, pageKeys, visible),
                    ),
                  ],
                ),
              ),
            )
          else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: [
                if (_uploading)
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                        color: kInk, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                                _uploadProgress >= 0.999
                                    ? 'Processing $_editionTitle…'
                                    : 'Uploading $_editionTitle…',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: kPaper, fontSize: 13)),
                          ),
                          const SizedBox(width: 8),
                          Text('${(_uploadProgress * 100).round()}%',
                              style: const TextStyle(
                                  color: kAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500)),
                        ]),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                              value: _uploadProgress >= 0.999
                                  ? null
                                  : _uploadProgress,
                              minHeight: 4,
                              backgroundColor: Gati.onInkTrack,
                              color: Gati.pasupu),
                        ),
                      ],
                    ),
                  )
                // While a fresh upload is still processing, keep the progress
                // card; once the edition is ready, show the masthead.
                else if (st != null && !st.isDone)
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                        color: kInk,
                        borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_editionTitle,
                            style: const TextStyle(
                                color: kPaper,
                                fontSize: 17,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text(
                            'Page ${st.donePages}/${st.totalPages} · '
                            '${st.articleCount} articles found',
                            style: const TextStyle(
                                color: Gati.onInkMuted, fontSize: 12)),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                              value: st.progress,
                              minHeight: 4,
                              backgroundColor: Gati.onInkTrack,
                              color: Gati.pasupu),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                        color: kInk, borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.headphones_rounded,
                            color: kAccent, size: 30),
                        const SizedBox(height: 14),
                        const Text('Listen to the newspaper',
                            style: TextStyle(
                                color: kPaper,
                                fontSize: 21,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 6),
                        const Text(
                            'Upload today’s edition and Gativani turns every '
                            'article into audio you can listen to.',
                            style: TextStyle(
                                color: Gati.onInkMuted,
                                fontSize: 13.5,
                                height: 1.5)),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: kAccent,
                              foregroundColor: kPaper,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12)),
                          onPressed: _upload,
                          icon: const Icon(Icons.upload_file, size: 18),
                          label: const Text('Upload edition'),
                        ),
                      ],
                    ),
                  ),
                  for (final step in const [
                    ['1', 'Upload', 'A newspaper PDF or a photo of a page'],
                    ['2', 'We separate', 'Each article, headline and section, automatically'],
                    ['3', 'Listen', 'Play article by article, like a podcast'],
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                                color: Gati.accentSoft,
                                shape: BoxShape.circle),
                            child: Text(step[0],
                                style: const TextStyle(
                                    color: Gati.accentText,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(step[1],
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: p.ink)),
                                Text(step[2],
                                    style: TextStyle(
                                        fontSize: 12.5, color: p.muted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── "All articles" as a self-contained snap section: consistent label +
  // select/view/filter controls on one row (sections & pages live in the
  // funnel dropdown now), with the article list scrolling INSIDE.
  Widget _allArticlesSection(GatiPalette p, String lang, List<String> catKeys,
      Map<String, int> cats, List<int> pageKeys, List<NewspaperArticle> visible) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  tr(lang,
                      _view == 'tiles' ? 'browse_by_section' : 'all_articles'),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: p.ink)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (_view == 'list')
                  GestureDetector(
                    onTap: () => setState(() {
                      _selectMode = !_selectMode;
                      if (!_selectMode) _selected.clear();
                    }),
                    child: Container(
                      width: 32,
                      height: 28,
                      alignment: Alignment.center,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                          color: _selectMode ? kAccent : p.chip,
                          borderRadius: BorderRadius.circular(8)),
                      child: Icon(Icons.checklist_rounded,
                          size: 17, color: _selectMode ? kPaper : p.muted),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                      color: p.chip, borderRadius: BorderRadius.circular(9)),
                  child: Row(children: [
                    _viewBtn(Icons.view_list_rounded, 'list'),
                    _viewBtn(Icons.grid_view_rounded, 'tiles'),
                    GatiFilterButton(
                      sections: catKeys,
                      selectedSection: _category,
                      onSection: (v) => setState(() => _category = v),
                      pages: pageKeys,
                      selectedPage: _pageSel,
                      onPage: (v) => setState(() => _pageSel = v),
                      sectionLabelOf: (sec) => sectionLabel(sec, lang),
                    ),
                  ]),
                ),
              ]),
            ],
          ),
        ),
        Expanded(
          child: _view == 'tiles'
              ? GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 1.6,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  children: [
                    for (final k in catKeys)
                      _sectionTile(k, cats[k]!,
                          _articles.where((a) => a.category == k).toList()),
                  ],
                )
              : ListView(children: [
                  if ((_category != null || _pageSel != null) &&
                      visible.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        onTap: () => _playList(visible),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.play_circle_fill,
                              color: kAccent, size: 22),
                          const SizedBox(width: 6),
                          Text(
                              '${tr(lang, 'play_all')} '
                              '${_category != null ? sectionLabel(_category!, lang) : '${tr(lang, 'page')} $_pageSel'}'
                              ' · ${visible.length}',
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: kAccent)),
                        ]),
                      ),
                    ),
                  for (final a in visible)
                    ArticleCard(
                      article: a,
                      onOpen: () => _openArticle(a), // read, don't autoplay
                      onPlay: () => _playInline(a), // mini-player only
                      onLongPressAt: (pos) =>
                          showGatiArticleMenu(context, pos, a,
                              onRead: () => _openArticle(a)),
                      selectionMode: _selectMode,
                      selected: _selected.contains(a.id),
                      onToggleSelect: () => _toggleSelect(a.id),
                    ),
                ]),
        ),
        if (_selectMode) _selectionBar(p, lang, visible),
      ]),
    );
  }
}
