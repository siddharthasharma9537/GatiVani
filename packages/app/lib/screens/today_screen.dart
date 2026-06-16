import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/newspaper_article.dart';
import '../services/document_service.dart';
import '../services/playback_service.dart';
import '../widgets/mini_player.dart';
import 'lyrics_player_screen.dart';

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
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              fontSize: 12,
              color: selected ? const Color(0xFF993C1D) : kInk)),
      selected: selected,
      showCheckmark: false,
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFFAECE7),
      onSelected: (_) => onTap(),
    );
  }

  Widget _lensBtn(String label, String lens) {
    final sel = _lens == lens;
    return GestureDetector(
      onTap: () => setState(() => _lens = lens),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? kInk : Colors.transparent,
          border: Border.all(color: sel ? kInk : const Color(0xFFD3D1C7)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                color: sel ? kPaper : kMuted,
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

  void _playAll() {
    PlaybackService.i.playAll(_articles);
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
      backgroundColor: kPaper,
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
                      const Text('Gativani',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              color: kInk)),
                      if (!showHero)
                        GestureDetector(
                          onTap: _upload,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                                color: kAccent,
                                borderRadius: BorderRadius.circular(20)),
                            child: const Row(children: [
                              Icon(Icons.add, color: kPaper, size: 17),
                              SizedBox(width: 4),
                              Text('Upload',
                                  style: TextStyle(
                                      color: kPaper,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                            ]),
                          ),
                        ),
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
                else if (_articles.isNotEmpty || st != null)
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
                            st != null && !st.isDone
                                ? 'Page ${st.donePages}/${st.totalPages} · '
                                    '${st.articleCount} articles found'
                                : '${_articles.length} articles',
                            style: const TextStyle(
                                color: Color(0xFFB4B2A9), fontSize: 12)),
                        if (st != null && !st.isDone) ...[
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
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: kAccent,
                              foregroundColor: kPaper),
                          onPressed: _articles.isEmpty
                              ? null
                              : _playAll,
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('Listen'),
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
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: kInk)),
                                Text(step[2],
                                    style: const TextStyle(
                                        fontSize: 12.5, color: kMuted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
                if (_recent.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 6),
                    child: Text('Recently played',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: kInk)),
                  ),
                  SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _recent.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) {
                        final m = _recent[i];
                        return GestureDetector(
                          onTap: () => _playRecent(m['article_id'] as String),
                          child: Container(
                            width: 160,
                            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                    color: const Color(0xFFE7E4DB)),
                                borderRadius: BorderRadius.circular(14)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text((m['category'] as String? ?? 'News').toUpperCase(),
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
                                      style: const TextStyle(
                                          fontSize: 13,
                                          height: 1.3,
                                          color: kInk)),
                                ),
                                Row(children: const [
                                  Icon(Icons.play_circle_fill,
                                      color: kAccent, size: 18),
                                  SizedBox(width: 4),
                                  Text('Play',
                                      style: TextStyle(
                                          fontSize: 11.5, color: kMuted)),
                                ]),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_articles.isNotEmpty && pageKeys.length > 1) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      _lensBtn('Sections', 'section'),
                      const SizedBox(width: 8),
                      _lensBtn('Pages', 'page'),
                    ]),
                  ),
                ],
                if (_articles.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (_lens == 'page') ...[
                          _chip('All · ${_articles.length}', _pageSel == null,
                              () => setState(() => _pageSel = null)),
                          for (final p in pageKeys)
                            _chip('Page $p · ${pages[p]}', _pageSel == p,
                                () => setState(
                                    () => _pageSel = _pageSel == p ? null : p)),
                        ] else ...[
                          _chip('All · ${_articles.length}', _category == null,
                              () => setState(() => _category = null)),
                          for (final k in catKeys)
                            _chip('$k · ${cats[k]}', _category == k,
                                () => setState(() =>
                                    _category = _category == k ? null : k)),
                        ],
                      ],
                    ),
                  ),
                // Play the current section/filter back-to-back, like a playlist.
                if ((_category != null || _pageSel != null) && visible.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      onTap: () => _playList(visible),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.play_circle_fill, color: kAccent, size: 22),
                        const SizedBox(width: 6),
                        Text(
                            'Play all ${_category ?? 'Page $_pageSel'} · ${visible.length}',
                            style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                color: kAccent)),
                      ]),
                    ),
                  ),
                for (final a in visible)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(a.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: kInk)),
                    subtitle: Text(
                        '${a.category} · p${a.page} · '
                        '${(a.estimatedDurationSeconds / 60).ceil()} min',
                        style:
                            const TextStyle(fontSize: 12, color: kMuted)),
                    trailing: IconButton(
                      icon: const Icon(Icons.play_circle_fill, color: kAccent),
                      tooltip: 'Play',
                      onPressed: () => _playInline(a), // play in place
                    ),
                    onTap: () => _play(a), // open the full player with text
                  ),
              ],
            ),
          ),
          MiniPlayer(onExpand: _openPlayer),
        ]),
      ),
    );
  }
}
