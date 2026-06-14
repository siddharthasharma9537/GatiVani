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
import 'home_screen.dart';

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
    final picked = await FilePicker
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    setState(() => _error = null);
    try {
      final job = await _svc.startEdition(
          filePath: f.path ?? '', filename: f.name, fileBytes: f.bytes);
      setState(() {
        _job = job;
        _editionTitle = f.name.replaceAll(RegExp(r'\.pdf$'), '');
        _articles = [];
      });
      _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    } catch (e) {
      setState(() => _error = e.toString());
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('GatiVani',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            color: kInk)),
                    IconButton(
                      icon: const Icon(Icons.apps, color: kMuted),
                      tooltip: 'Classic home',
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const HomeScreen())),
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!,
                        style:
                            const TextStyle(color: kAccent, fontSize: 12.5)),
                  ),
                if (_articles.isNotEmpty || st != null)
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
                else
                  Container(
                    padding: const EdgeInsets.all(24),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFD3D1C7)),
                        borderRadius: BorderRadius.circular(16)),
                    child: const Center(
                        child: Text(
                            'Upload a newspaper PDF with + to build\n'
                            "today's audio edition",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: kMuted, fontSize: 13))),
                  ),
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
