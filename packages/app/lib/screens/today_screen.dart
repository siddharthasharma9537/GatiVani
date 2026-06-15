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

  void _play(NewspaperArticle a) {
    // Open the player first (synchronously, inside the tap gesture) so the
    // play control is available immediately — mobile browsers block audio that
    // starts after an async gap, so the player's own play button is the
    // reliable path there.
    _openPlayer();
    PlaybackService.i.playOne(a);
    Future.delayed(const Duration(seconds: 2), _loadRecent);
  }

  void _openPlayer() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const LyricsPlayerScreen()));
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
      floatingActionButton: showHero
          ? null
          : FloatingActionButton(
              backgroundColor: kAccent,
              onPressed: _upload,
              child: const Icon(Icons.add, color: kPaper),
            ),
      body: Listener(
        // First tap unlocks mobile web audio (autoplay policy).
        onPointerDown: (_) => PlaybackService.i.unlock(),
        child: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text('GatiVani',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                          color: kInk)),
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
                            'Upload today’s edition and GatiVani turns every '
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
                        if (_lens == 'page')
                          for (final p in pageKeys)
                            ChoiceChip(
                              label: Text('Page $p · ${pages[p]}',
                                  style: const TextStyle(fontSize: 12)),
                              selected: _pageSel == p,
                              selectedColor: const Color(0xFFFAECE7),
                              onSelected: (_) => setState(() =>
                                  _pageSel = _pageSel == p ? null : p),
                            )
                        else
                          for (final e in cats.entries)
                            ChoiceChip(
                              label: Text('${e.key} · ${e.value}',
                                  style: const TextStyle(fontSize: 12)),
                              selected: _category == e.key,
                              selectedColor: const Color(0xFFFAECE7),
                              onSelected: (_) => setState(() => _category =
                                  _category == e.key ? null : e.key),
                            ),
                      ],
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
                    trailing:
                        const Icon(Icons.play_arrow, color: kAccent),
                    onTap: () => _play(a),
                  ),
              ],
            ),
          ),
          MiniPlayer(onExpand: _openPlayer),
        ]),
      ),
      ),
    );
  }
}
