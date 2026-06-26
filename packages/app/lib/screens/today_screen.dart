import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../l10n/strings.dart';
import '../models/newspaper_article.dart';
import '../services/document_service.dart';
import '../services/playback_service.dart';
import '../services/settings_provider.dart';
import '../design/section_colors.dart';
import '../widgets/article_card.dart';
import '../widgets/edition_masthead.dart';
import '../widgets/mini_player.dart';
import 'lyrics_player_screen.dart';
import 'menu_screen.dart';
import 'section_screen.dart';

/// Reimagined home: today's edition front and center, live processing card,
/// in-place category chips, persistent mini-player. Upload via FAB.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final _svc = DocumentService();
  List<NewspaperArticle> _articles = [];
  String _editionTitle = '';
  String? _category;
  int? _pageSel;
  String _lens = 'section'; // 'section' | 'page'
  String _view = 'tiles'; // 'tiles' | 'list'
  EditionJob? _job;
  EditionJobStatus? _jobStatus;
  Timer? _poll;
  String? _error;
  bool _uploading = false;
  double _uploadProgress = 0;
  List<Map<String, dynamic>> _recent = [];

  bool _featuredLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _loadFeatured();
  }

  // Open onto real content: load the featured/most-recent edition so the app is
  // never an empty screen. Skipped once the user starts their own upload.
  Future<void> _loadFeatured() async {
    final ed = await _svc.fetchFeaturedEdition();
    if (ed == null || !mounted || _job != null || _articles.isNotEmpty) return;
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

  Future<void> _loadRecent() async {
    try {
      final r = await http.get(
        Uri.parse('${ApiConfig.restUrl}/recent_plays'
            '?select=article_id,title,category&order=played_at.desc&limit=20'),
        headers: ApiConfig.authHeaders,
      );
      final rows = (json.decode(r.body) as List).cast<Map<String, dynamic>>();
      final seen = <String>{};
      final dedup = <Map<String, dynamic>>[];
      for (final m in rows) {
        final id = m['article_id'] as String?;
        if (id == null || !seen.add(id)) continue;
        dedup.add(m);
        if (dedup.length >= 8) break;
      }
      if (mounted) setState(() => _recent = dedup);
    } catch (_) {}
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

  // Tapping the article text → open the full-screen player with the text.
  void _play(NewspaperArticle a) {
    _openPlayer();
    PlaybackService.i.playOne(a);
    Future.delayed(const Duration(seconds: 2), _loadRecent);
  }

  // Tapping the row's play icon → just start playing (mini-player), no full
  // screen — like a track list.
  void _playInline(NewspaperArticle a) {
    PlaybackService.i.playOne(a);
    Future.delayed(const Duration(seconds: 2), _loadRecent);
  }

  // Play a whole section/filter back-to-back, like a playlist.
  void _playList(List<NewspaperArticle> list) {
    if (list.isEmpty) return;
    PlaybackService.i.playAll(list);
    Future.delayed(const Duration(seconds: 2), _loadRecent);
  }

  // Sensible chip order: hard news first, the catch-all "News" last.
  static const _sectionOrder = [
    'State', 'National', 'International', 'District', 'Politics', 'Editorial',
    'Judiciary', 'Crime', 'Business', 'Sports', 'Health', 'Sci-Tech',
    'Education', 'Agriculture', 'Entertainment', 'Devotional', 'Trending', 'News',
  ];
  int _sectionRank(String s) {
    final i = _sectionOrder.indexOf(s);
    return i < 0 ? _sectionOrder.length : i;
  }

  void _openPlayer() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const LyricsPlayerScreen()));
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    final p = GatiPalette.of(context);
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              fontSize: 12,
              color: selected ? const Color(0xFF993C1D) : p.ink)),
      selected: selected,
      showCheckmark: false,
      backgroundColor: p.surface,
      selectedColor: const Color(0xFFFAECE7),
      side: BorderSide(color: p.line),
      onSelected: (_) => onTap(),
    );
  }

  // Compact EN/తె language toggle for the header.
  Widget _langToggle() {
    final s = context.watch<SettingsProvider>();
    final p = GatiPalette.of(context);
    Widget cell(String label, String code) {
      final sel = s.lang == code;
      return GestureDetector(
        onTap: () => s.setLanguage(code),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: sel ? kAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: sel ? kPaper : p.muted)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: p.chip, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        cell('EN', 'en'),
        cell('తె', 'te'),
      ]),
    );
  }

  void _openMenu() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const MenuScreen()));
  }

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

  // Drill down: tapping a section tile opens that section's article list.
  void _openSection(String section, List<NewspaperArticle> arts) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => SectionScreen(section: section, articles: arts)));
  }

  // A colored section tile: tap the body → open the section; tap the ▶ → play
  // the whole section as a playlist.
  Widget _sectionTile(String section, int count, List<NewspaperArticle> arts) {
    final lang = context.watch<SettingsProvider>().lang;
    final r = sectionRamp(section, dark: GatiPalette.of(context).dark);
    return GestureDetector(
      onTap: () => _openSection(section, arts),
      child: Container(
        decoration: BoxDecoration(
            color: r[0], borderRadius: BorderRadius.circular(14)),
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

  Widget _lensBtn(String label, String lens) {
    final sel = _lens == lens;
    final p = GatiPalette.of(context);
    return GestureDetector(
      onTap: () => setState(() => _lens = lens),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? p.ink : Colors.transparent,
          border: Border.all(color: sel ? p.ink : p.line),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                color: sel ? p.paper : p.muted,
                fontWeight: FontWeight.w500)),
      ),
    );
  }

  Future<void> _playRecent(String id) async {
    _openPlayer();
    final a = await _svc.fetchArticleById(id);
    if (a == null) return;
    PlaybackService.i.playOne(a);
  }

  // "Listen to briefing": a curated handful — top editorial sections first —
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
    Future.delayed(const Duration(seconds: 2), _loadRecent);
  }

  Future<void> _refresh() async {
    final job = _job;
    if (job == null) return;
    try {
      final st = await _svc.pollEdition(job.jobId);
      final arts = await _svc.fetchEditionArticles(job.newspaperId);
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
    final visible = _lens == 'page'
        ? (_pageSel == null
            ? _articles
            : _articles.where((a) => a.page == _pageSel).toList())
        : (_category == null
            ? _articles
            : _articles.where((a) => a.category == _category).toList());
    final st = _jobStatus;
    // First-run / empty state shows the hero "Upload edition" CTA — hide the FAB
    // then so there aren't two upload buttons. The FAB returns once an edition
    // is loaded, as the persistent "add another" action.
    final showHero = !_uploading && _articles.isEmpty && st == null;

    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Gativani',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              color: p.ink)),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        _langToggle(),
                        const SizedBox(width: 8),
                        if (!showHero) ...[
                          GestureDetector(
                            onTap: _upload,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 11, vertical: 7),
                              decoration: BoxDecoration(
                                  color: kAccent,
                                  borderRadius: BorderRadius.circular(20)),
                              child: Row(children: [
                                const Icon(Icons.add, color: kPaper, size: 17),
                                const SizedBox(width: 3),
                                Text(tr(lang, 'upload'),
                                    style: const TextStyle(
                                        color: kPaper,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500)),
                              ]),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        GestureDetector(
                          onTap: _openMenu,
                          child: Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: p.chip,
                                borderRadius: BorderRadius.circular(10)),
                            child: Icon(Icons.menu_rounded,
                                color: p.ink, size: 20),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!,
                        style:
                            const TextStyle(color: kAccent, fontSize: 12.5)),
                  ),
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
                              backgroundColor: const Color(0xFF5F5E5A),
                              color: kAccent),
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
                                color: Color(0xFFB4B2A9), fontSize: 12)),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                              value: st.progress,
                              minHeight: 4,
                              backgroundColor: const Color(0xFF5F5E5A),
                              color: kAccent),
                        ),
                      ],
                    ),
                  )
                else if (_articles.isNotEmpty)
                  EditionMasthead(
                    rawTitle: _editionTitle,
                    articleCount: _articles.length,
                    pageCount: pages.length,
                    onListen: _playBriefing,
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
                                color: Color(0xFFB4B2A9),
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
                                color: Color(0xFFFAECE7),
                                shape: BoxShape.circle),
                            child: Text(step[0],
                                style: const TextStyle(
                                    color: Color(0xFF993C1D),
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
                if (_recent.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 6),
                    child: Text(tr(lang, 'recently_played'),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: p.ink)),
                  ),
                  _RecentlyPlayedMarquee(
                    items: _recent,
                    lang: lang,
                    onTap: (id) => _playRecent(id),
                  ),
                  const SizedBox(height: 16),
                ],
                // Header for the browse area + the list ⇄ tiles toggle.
                if (_articles.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            tr(lang,
                                _view == 'tiles'
                                    ? 'browse_by_section'
                                    : 'all_articles'),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: p.ink)),
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                              color: p.chip,
                              borderRadius: BorderRadius.circular(9)),
                          child: Row(children: [
                            _viewBtn(Icons.view_list_rounded, 'list'),
                            _viewBtn(Icons.grid_view_rounded, 'tiles'),
                          ]),
                        ),
                      ],
                    ),
                  ),
                // Tile view: a colored grid of sections, drilling into a list.
                if (_articles.isNotEmpty && _view == 'tiles')
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
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
                // List view: lens + chips + play-all + flat article list.
                else if (_articles.isNotEmpty) ...[
                  if (pageKeys.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        _lensBtn(tr(lang, 'sections'), 'section'),
                        const SizedBox(width: 8),
                        _lensBtn(tr(lang, 'pages'), 'page'),
                      ]),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (_lens == 'page') ...[
                          _chip('${tr(lang, 'all')} · ${_articles.length}',
                              _pageSel == null,
                              () => setState(() => _pageSel = null)),
                          for (final p in pageKeys)
                            _chip('${tr(lang, 'page')} $p · ${pages[p]}',
                                _pageSel == p,
                                () => setState(
                                    () => _pageSel = _pageSel == p ? null : p)),
                        ] else ...[
                          _chip('${tr(lang, 'all')} · ${_articles.length}',
                              _category == null,
                              () => setState(() => _category = null)),
                          for (final k in catKeys)
                            _chip('${sectionLabel(k, lang)} · ${cats[k]}',
                                _category == k,
                                () => setState(() =>
                                    _category = _category == k ? null : k)),
                        ],
                      ],
                    ),
                  ),
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
                      onOpen: () => _play(a), // open the full player with text
                      onPlay: () => _playInline(a), // play in place
                    ),
                ],
              ],
            ),
          ),
          MiniPlayer(onExpand: _openPlayer),
        ]),
      ),
    );
  }
}

/// "Recently played" as a slow right-to-left marquee. The strip auto-scrolls on
/// its own (no user drag); the items are repeated so the loop is seamless. Tap a
/// card to play it.
class _RecentlyPlayedMarquee extends StatefulWidget {
  const _RecentlyPlayedMarquee(
      {required this.items, required this.lang, required this.onTap});
  final List<Map<String, dynamic>> items;
  final String lang;
  final void Function(String id) onTap;
  @override
  State<_RecentlyPlayedMarquee> createState() => _RecentlyPlayedMarqueeState();
}

class _RecentlyPlayedMarqueeState extends State<_RecentlyPlayedMarquee> {
  final _ctrl = ScrollController();
  Timer? _timer;
  Timer? _resume;
  bool _userActive = false; // paused while the user drags / flings
  static const _cardW = 160.0;
  static const _gap = 10.0;

  double get _setW => widget.items.length * (_cardW + _gap);

  @override
  void initState() {
    super.initState();
    // Start one set in, so there's content to scroll into on BOTH sides.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_ctrl.hasClients && _setW > 0) _ctrl.jumpTo(_setW);
    });
    // Drive the scroll a few pixels per tick → a calm ~13 px/s drift, unless the
    // user is scrolling it themselves.
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (_userActive || !_ctrl.hasClients || _setW <= 0) return;
      final setW = _setW;
      var next = _ctrl.offset + 0.4;
      // Keep the offset in the middle set [setW, 2*setW); the repeated content
      // makes the wrap seamless and leaves a set on each side to drag into.
      while (next >= 2 * setW) next -= setW;
      while (next < setW) next += setW;
      _ctrl.jumpTo(next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _resume?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final n = widget.items.length;
    if (n == 0) return const SizedBox.shrink();
    // ≥3 sets so the middle-set drift always has a set to scroll into either way.
    final reps = n <= 3 ? 5 : 3;
    return SizedBox(
      height: 96,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notif) {
          // Pause the auto-drift while the user is dragging, and keep it paused
          // through any fling until the scroll settles.
          if (notif is ScrollStartNotification &&
              notif.dragDetails != null) {
            _userActive = true;
            _resume?.cancel();
          } else if (notif is ScrollEndNotification) {
            _resume?.cancel();
            _resume = Timer(const Duration(milliseconds: 1200),
                () => _userActive = false);
          }
          return false;
        },
        child: ListView.builder(
          controller: _ctrl,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          itemCount: n * reps,
          itemBuilder: (_, i) {
            final m = widget.items[i % n];
            return Padding(
              padding: const EdgeInsets.only(right: _gap),
              child: _card(p, m),
            );
          },
        ),
      ),
    );
  }

  Widget _card(GatiPalette p, Map<String, dynamic> m) {
    final c = sectionLabel(m['category'] as String? ?? 'News', widget.lang);
    return GestureDetector(
      onTap: () => widget.onTap(m['article_id'] as String),
      child: Container(
        width: _cardW,
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
            color: p.surface,
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.lang == 'en' ? c.toUpperCase() : c,
                style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.4,
                    color: kAccent,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 5),
            Expanded(
              child: Text(m['title'] as String? ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, height: 1.3, color: p.ink)),
            ),
            Row(children: [
              const Icon(Icons.play_circle_fill, color: kAccent, size: 18),
              const SizedBox(width: 4),
              Text(tr(widget.lang, 'play'),
                  style: TextStyle(fontSize: 11.5, color: p.muted)),
            ]),
          ],
        ),
      ),
    );
  }
}
