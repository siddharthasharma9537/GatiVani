import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../l10n/strings.dart';
import '../models/newspaper_article.dart';
import '../services/document_service.dart';
import '../services/edition_store.dart';
import '../services/playback_service.dart';
import '../services/settings_provider.dart';
import '../design/components/gati_masthead.dart';
import '../design/section_colors.dart';
import '../design/tokens.dart';
import '../widgets/article_card.dart';
import '../widgets/edition_masthead.dart';

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
  String _lens = 'section'; // 'section' | 'page'
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

  Future<void> _loadRecent() async {
    try {
      final r = await http.get(
        Uri.parse('${ApiConfig.restUrl}/recent_plays'
            '?select=article_id,title,category,position_seconds,duration_seconds,completed'
            '&order=played_at.desc&limit=20'),
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
    'Editorial', 'Opinion', 'State', 'National', 'International', 'District',
    'Politics', 'Judiciary', 'Crime', 'Business', 'Sports', 'Health', 'Sci-Tech',
    'Education', 'Agriculture', 'Entertainment', 'Devotional', 'Trending', 'News',
  ];
  int _sectionRank(String s) {
    final i = _sectionOrder.indexOf(s);
    return i < 0 ? _sectionOrder.length : i;
  }

  void _openPlayer() => context.push('/player');

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    final p = GatiPalette.of(context);
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              fontSize: 12,
              color: selected ? Gati.accentText : p.ink)),
      selected: selected,
      showCheckmark: false,
      backgroundColor: p.surface,
      selectedColor: Gati.accentSoft,
      side: BorderSide(color: p.line),
      onSelected: (_) => onTap(),
    );
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

  // Tapping a recently-played tile: resume a partially-heard article at its
  // saved spot, or replay a finished one from the top.
  Future<void> _playRecent(Map<String, dynamic> m) async {
    _openPlayer();
    final a = await _svc.fetchArticleById(m['article_id'] as String);
    if (a == null) return;
    final done = m['completed'] as bool? ?? false;
    final pos = (m['position_seconds'] as num?)?.toInt() ?? 0;
    PlaybackService.i.playOne(a,
        resumeAt: done ? Duration.zero : Duration(seconds: pos));
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
  void _showArticleSheet(NewspaperArticle a) {
    final lang = context.read<SettingsProvider>().lang;
    final p = GatiPalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        Widget item(IconData icon, String label, VoidCallback onTap) =>
            ListTile(
              leading: Icon(icon, color: p.ink, size: 22),
              title:
                  Text(label, style: TextStyle(color: p.ink, fontSize: 15)),
              onTap: () {
                Navigator.pop(ctx);
                onTap();
              },
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(a.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
              ),
            ),
            item(Icons.play_arrow_rounded, tr(lang, 'play_now'),
                () => _play(a)),
            item(Icons.auto_awesome, tr(lang, 'summarize'),
                () => _summarize(a)),
            item(Icons.queue_play_next_rounded, tr(lang, 'play_next'), () {
              PlaybackService.i.playNext([a]);
              _toast(lang, 'added_play_next');
            }),
            item(Icons.playlist_add_rounded, tr(lang, 'add_to_queue'), () {
              PlaybackService.i.addToQueue([a]);
              _toast(lang, 'added_queue');
            }),
            item(Icons.download_rounded, tr(lang, 'download'),
                () => _download(a)),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
  }

  // Summarize = an AI gist (a few sentences) narrated in the mini-player.
  // Grounded-Gemini writes a short Telugu summary, then it's synthesized + cached
  // and played. Much shorter than the full article, so it's quick and cheap.
  Future<void> _summarize(NewspaperArticle a) async {
    final lang = context.read<SettingsProvider>().lang;
    _toast(lang, 'summarizing');
    try {
      final summary = await _svc.ask(
        a.id,
        'ఈ వ్యాసాన్ని తెలుగులో 3-4 చిన్న వాక్యాల్లో సంక్షిప్త సారాంశంగా చెప్పు. '
        'ఉపోద్ఘాతం, అదనపు వ్యాఖ్యలు వద్దు — కేవలం సారాంశం మాత్రమే.',
      );
      if (summary.trim().isEmpty) {
        _toast(lang, 'summary_failed');
        return;
      }
      await PlaybackService.i.playSummary(a, summary);
    } catch (_) {
      if (mounted) _toast(lang, 'summary_failed');
    }
  }

  // Download = pre-generate the full audio so it's cached and instant to play
  // later. (True offline-bytes storage is a follow-up.)
  Future<void> _download(NewspaperArticle a) async {
    final lang = context.read<SettingsProvider>().lang;
    if (a.audioUrl != null && a.audioUrl!.startsWith('http')) {
      _toast(lang, 'downloaded');
      return;
    }
    _toast(lang, 'downloading');
    try {
      final r = await http
          .post(Uri.parse(ApiConfig.documentsSynthesizeUrl),
              headers: {
                ...ApiConfig.authHeaders,
                'Content-Type': 'application/json'
              },
              body: json.encode({
                'text': a.spokenText,
                'language': 'te-IN',
                'articleId': a.id,
              }))
          .timeout(const Duration(seconds: 150));
      final data = json.decode(r.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        a.audioUrl = data['audioUrl'] as String?;
        _toast(lang, 'downloaded');
      } else {
        _toast(lang, 'download_failed');
      }
    } catch (_) {
      _toast(lang, 'download_failed');
    }
  }

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
        padding: const EdgeInsets.only(top: 2, bottom: 8),
        child: Text(tr(lang, pickIsOpinion ? 'editorial_opinion' : 'front_page'),
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: p.ink)),
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
        borderRadius: BorderRadius.circular(18),
        onTap: () => _play(a),
        onLongPress: () => _showArticleSheet(a),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: r[0],
            borderRadius: BorderRadius.circular(18),
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
      onTap: () => _play(a),
      onLongPress: () => _showArticleSheet(a),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: r[0],
            borderRadius: BorderRadius.circular(14),
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
          GatiMasthead(lang: lang, actions: [
            if (!showHero)
              GestureDetector(
                onTap: _upload,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                      color: kAccent, borderRadius: BorderRadius.circular(20)),
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
            GatiHeaderButton(
                icon: Icons.search, onTap: () => context.push('/search')),
          ]),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: [
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
                // Front page: the editor's pick lead + Editorial/Opinion when
                // the edition carries those fixed sections.
                if (_articles.isNotEmpty) _frontPageBand(p, lang),
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
                    onTap: _playRecent,
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
                                    color:
                                        _selectMode ? kAccent : p.chip,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Icon(Icons.checklist_rounded,
                                    size: 17,
                                    color: _selectMode ? kPaper : p.muted),
                              ),
                            ),
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
                        ]),
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
                      onLongPress: () => _showArticleSheet(a),
                      selectionMode: _selectMode,
                      selected: _selected.contains(a.id),
                      onToggleSelect: () => _toggleSelect(a.id),
                    ),
                ],
              ],
            ),
          ),
          if (_selectMode) _selectionBar(p, lang, visible),
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
  final void Function(Map<String, dynamic> item) onTap;
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
    final pos = (m['position_seconds'] as num?)?.toInt() ?? 0;
    final dur = (m['duration_seconds'] as num?)?.toInt() ?? 0;
    final completed = m['completed'] as bool? ?? false;
    final started = !completed && pos > 0 && dur > 0;
    final frac = completed ? 1.0 : (dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0);

    // Action label + length: Replay (finished) / Resume · N left (partial) / Play.
    final IconData icon;
    final String label;
    final String? meta;
    if (completed) {
      icon = Icons.refresh_rounded;
      label = tr(widget.lang, 'replay');
      meta = dur > 0 ? '${(dur / 60).ceil()} ${tr(widget.lang, 'min')}' : null;
    } else if (started) {
      icon = Icons.play_arrow_rounded;
      label = tr(widget.lang, 'resume');
      meta = '${((dur - pos) / 60).ceil()} ${tr(widget.lang, 'min_left')}';
    } else {
      icon = Icons.play_arrow_rounded;
      label = tr(widget.lang, 'play');
      meta = dur > 0 ? '${(dur / 60).ceil()} ${tr(widget.lang, 'min')}' : null;
    }

    return GestureDetector(
      onTap: () => widget.onTap(m),
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
            if (dur > 0) ...[
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 3,
                    backgroundColor: p.line,
                    color: completed ? p.muted : kAccent),
              ),
            ],
            const SizedBox(height: 6),
            Row(children: [
              Icon(icon, color: completed ? p.muted : kAccent, size: 17),
              const SizedBox(width: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: started ? p.ink : p.muted)),
              if (meta != null) ...[
                const SizedBox(width: 4),
                Expanded(
                  child: Text('· $meta',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: p.muted)),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }
}
