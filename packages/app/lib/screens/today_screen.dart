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
  EditionJob? _job;
  EditionJobStatus? _jobStatus;
  Timer? _poll;
  String? _error;
  bool _uploading = false;
  List<Map<String, dynamic>> _recent = [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
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
      _editionTitle = f.name.replaceAll(RegExp(r'\.(pdf|jpe?g|png)$'), '');
      _articles = [];
      _job = null;
      _jobStatus = null;
    });
    try {
      final job = await _svc.startEdition(
          filePath: f.path ?? '', filename: f.name, fileBytes: f.bytes);
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
    PlaybackService.i.playOne(a);
    Future.delayed(const Duration(seconds: 2), _loadRecent);
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
    for (final a in _articles) {
      cats[a.category] = (cats[a.category] ?? 0) + 1;
    }
    final visible = _category == null
        ? _articles
        : _articles.where((a) => a.category == _category).toList();
    final st = _jobStatus;

    return Scaffold(
      backgroundColor: kPaper,
      floatingActionButton: FloatingActionButton(
        backgroundColor: kAccent,
        onPressed: _upload,
        child: const Icon(Icons.add, color: kPaper),
      ),
      body: SafeArea(
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
                    child: Row(children: [
                      const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: kAccent)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Uploading $_editionTitle…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: kPaper, fontSize: 13)),
                      ),
                    ]),
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
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _recent.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final m = _recent[i];
                        final a = _articles.firstWhere(
                          (x) => x.id == m['article_id'],
                          orElse: () => _articles.isEmpty
                              ? (throw StateError('none'))
                              : _articles.first,
                        );
                        return GestureDetector(
                          onTap: () => _play(a),
                          child: Container(
                            width: 150,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                    color: const Color(0xFFD3D1C7)),
                                borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m['category'] ?? 'News',
                                    style: const TextStyle(
                                        fontSize: 10.5, color: kAccent)),
                                const SizedBox(height: 4),
                                Expanded(
                                  child: Text(m['title'] ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12.5, color: kInk)),
                                ),
                                const Icon(Icons.play_circle_fill,
                                    color: kAccent, size: 18),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (cats.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
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
          const MiniPlayer(),
        ]),
      ),
    );
  }
}
