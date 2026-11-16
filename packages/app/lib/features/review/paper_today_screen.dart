import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../design/tokens.dart';
import 'listen_panel.dart';
import 'review_screen.dart' show kEenaduReview;

/// "Today's paper": Eenadu's e-paper as news inside the app, grouped by the paper's own page labels. Local only: it talks to
/// scripts/eenadu_review_server.py on the same origin (the owner's Mac), is compiled in only with --dart-define=EENADU_REVIEW=true,
/// and saves uploads only on that Mac. The story screen can read a story aloud with the on-device voice (services/tts; the text is synthesised
/// on this device and goes nowhere; in the browser the device's own voice is not used).
const String kPaperNotice =
    'Telugu reading: AI proposal, not proofread. Machine-converted from the printed PDF. Eenadu text: owner only, on this Mac.';

Uri _api(String route, [Map<String, String> q = const {}]) =>
    Uri.base.replace(path: '/review-api/$route', queryParameters: q, fragment: '');

Future<dynamic> _get(Uri u) async {
  final r = await http.get(u);
  if (r.statusCode != 200) throw 'HTTP ${r.statusCode} (open the link with the key the server printed)';
  return json.decode(utf8.decode(r.bodyBytes));
}

class PaperTodayScreen extends StatefulWidget {
  const PaperTodayScreen({super.key});
  @override
  State<PaperTodayScreen> createState() => _PaperTodayScreenState();
}

class _PaperTodayScreenState extends State<PaperTodayScreen> {
  List<Map<String, dynamic>> _editions = [];
  Map<String, dynamic>? _ed;
  List<Map<String, dynamic>> _sections = [];
  String? _sel; // selected section name
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _uploadJob;
  Timer? _jobPoll;
  bool _saving = false;
  bool _polling = false;
  int _paperRequest = 0;
  bool get _busy => _saving || _uploadJob?['status'] == 'extracting';

  @override
  void dispose() {
    _jobPoll?.cancel();
    super.dispose();
  }

  Future<void> _upload() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (!mounted || picked == null) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty || bytes.length > 100 * 1024 * 1024) {
      setState(() => _error = 'Choose a PDF smaller than 100 MB.');
      return;
    }
    _paperRequest++;
    setState(() { _saving = true; _uploadJob = null; _error = null; _loading = false; _sections = []; _sel = null; });
    try {
      final response = await http.post(_api('upload'),
          headers: {'Content-Type': 'application/pdf', 'X-Filename': Uri.encodeComponent(file.name)}, body: bytes);
      final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode != 202) throw data['error'] ?? 'Local upload failed (${response.statusCode})';
      if (!mounted) return;
      setState(() { _uploadJob = data; _saving = false; });
      _jobPoll?.cancel();
      _jobPoll = Timer.periodic(const Duration(seconds: 2), (_) => _pollUpload());
      await _pollUpload();
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = '$e'; });
    }
  }

  Future<void> _pollUpload() async {
    if (_polling || _uploadJob == null) return;
    _polling = true;
    try {
      final job = await _get(_api('upload-job', {'id': _uploadJob!['id'] as String})) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _uploadJob = job);
      if (job['status'] != 'extracting') {
        _jobPoll?.cancel();
        if (job['status'] == 'ready') {
          _editions = (await _get(_api('editions')) as List).cast<Map<String, dynamic>>();
          if (!mounted) return;
          await _pick(_editions.firstWhere((e) => e['edition'] == job['edition']));
        } else if (job['status'] == 'failed') {
          setState(() => _error = job['error'] as String? ?? 'Local extraction failed.');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Local status unavailable: $e');
    } finally {
      _polling = false;
    }
  }

  Future<void> _cancelUpload() async {
    try {
      final r = await http.post(_api('cancel-upload', {'id': _uploadJob!['id'] as String}));
      if (r.statusCode != 200) throw 'Cancel failed (${r.statusCode})';
      if (!mounted) return;
      setState(() => _uploadJob = json.decode(r.body) as Map<String, dynamic>);
      _jobPoll?.cancel();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _editions = (await _get(_api('editions')) as List).cast<Map<String, dynamic>>();
      if (_editions.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      await _pick(_editions.first);
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _pick(Map<String, dynamic> ed) async {
    final request = ++_paperRequest;
    setState(() { _ed = ed; _loading = true; _error = null; });
    try {
      final d = await _get(_api('paper', {'edition': ed['edition'] as String, 'date': ed['date'] as String}));
      final secs = ((d as Map)['sections'] as List).cast<Map<String, dynamic>>();
      if (mounted && request == _paperRequest) setState(() { _sections = secs; _sel = secs.isEmpty ? null : secs.first['name'] as String; _loading = false; });
    } catch (e) {
      if (mounted && request == _paperRequest) setState(() { _error = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final sec = _sections.where((s) => s['name'] == _sel).firstOrNull;
    final stories = ((sec?['stories'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        backgroundColor: p.paper,
        foregroundColor: p.ink,
        toolbarHeight: 48,
        title: Text(_ed == null ? 'Local paper' : "${_ed!['title'] ?? _ed!['edition']} · ${_ed!['date']}", style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(tooltip: 'Upload PDF locally', onPressed: _busy ? null : _upload, icon: const Icon(Icons.upload_file)),
          if (_editions.length > 1)
            PopupMenuButton<Map<String, dynamic>>(
              tooltip: 'Edition',
              icon: const Icon(Icons.swap_horiz),
              onSelected: (e) { if (!_busy) _pick(e); },
              itemBuilder: (_) => [
                for (final e in _editions) PopupMenuItem(value: e, child: Text("${e['title'] ?? e['edition']} · ${e['date']}")),
              ],
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _upload,
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload PDF locally'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text('Extracted on this Mac. PDFs stay local; no sign-in or cloud processing.',
                style: TextStyle(fontSize: 13, color: p.ink)),
          ),
          if (_saving || _uploadJob != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_saving ? 'Saving PDF on this Mac…' : '${_uploadJob!['filename']} · ${_uploadJob!['stage']}',
                    style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
                if (!_saving) Text('Pages ${_uploadJob!['donePages']}/${_uploadJob!['totalPages']} · ${_uploadJob!['articles']} articles',
                    style: TextStyle(color: p.muted)),
                if (_busy) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: _saving ? null : (_uploadJob!['donePages'] as int) / (_uploadJob!['totalPages'] as int)),
                  if (!_saving) TextButton(onPressed: _cancelUpload, child: const Text('Cancel extraction')),
                ],
              ]),
            ),
          Container(
            width: double.infinity,
            color: p.dark ? GatiDark.accentSoft : Gati.accentSoft,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(kPaperNotice, style: TextStyle(fontSize: 12, color: p.dark ? Gati.pasupuGlow : Gati.accentText)),
          ),
          if (_sections.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                children: [
                  for (final s in _sections)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        label: Text("${s['title']} · ${(s['stories'] as List).length}"),
                        selected: _sel == s['name'],
                        onSelected: (_) => setState(() => _sel = s['name'] as String),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(child: _body(p, stories)),
        ]),
      ),
    );
  }

  Widget _body(GatiPalette p, List<Map<String, dynamic>> stories) {
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: TextStyle(color: p.ink))));
    }
    if (_loading) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(),
        SizedBox(height: 12),
        Text('Reading the paper (first load takes a few seconds)…'),
      ]));
    }
    if (stories.isEmpty) {
      return Center(child: Text('Upload an Eenadu PDF to extract articles on this Mac.', style: TextStyle(color: p.ink)));
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 60),
          itemCount: stories.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (c, i) => _tile(p, stories[i]),
        ),
      ),
    );
  }

  Widget _tile(GatiPalette p, Map<String, dynamic> s) {
    final head = (s['headline'] as String).trim();
    final graphic = s['graphic'] == true;
    final title = head.isNotEmpty ? head : (graphic ? 'headline: graphic' : '(no headline in the PDF)');
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(Gati.rCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(Gati.rCard),
        onTap: () => context.push(Uri(path: '/paper/today/story', queryParameters: {
          'edition': _ed!['edition'] as String,
          'date': _ed!['date'] as String,
          'id': s['id'] as String,
        }).toString()),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(Gati.rCard), border: Border.all(color: p.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 16.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: head.isEmpty ? p.muted : p.ink)),
            if ((s['preview'] as String).isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(s['preview'] as String, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: p.muted)),
            ],
            const SizedBox(height: 6),
            Text(
                'page ${s['page']} · ${s['words']} words'
                '${s['continued'] == true ? (s['unmatched'] == true ? ' · continues (part not matched)' : ' · joined with its continuation') : ''}',
                style: TextStyle(fontSize: 12, color: p.muted)),
          ]),
        ),
      ),
    );
  }
}

/// One story, end to end, readable on a phone.
class StoryScreen extends StatefulWidget {
  const StoryScreen({super.key, required this.edition, required this.date, required this.id});
  final String edition, date, id;
  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  Map<String, dynamic>? _s;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _loadStory();
  }

  @override
  void didUpdateWidget(covariant StoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.edition != widget.edition || oldWidget.date != widget.date) {
      _loadStory();
    }
  }

  void _loadStory() {
    final request = ++_request;
    _s = null;
    _error = null;
    _get(_api('story', {'edition': widget.edition, 'date': widget.date, 'id': widget.id}))
        .then((d) => mounted && request == _request ? setState(() => _s = d as Map<String, dynamic>) : null)
        .catchError((e) { if (mounted && request == _request) setState(() => _error = '$e'); });
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final s = _s;
    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        backgroundColor: p.paper,
        foregroundColor: p.ink,
        toolbarHeight: 48,
        title: Text(s == null ? 'Story' : "${s['editionTitle'] ?? widget.edition} · page ${s['page']}", style: const TextStyle(fontSize: 15)),
      ),
      bottomNavigationBar: s == null || ((s['narration'] as String?) ?? '').trim().isEmpty
          ? null
          : ListenPanel(key: ValueKey(widget.id), narration: s['narration'] as String),
      body: SafeArea(
        child: _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: TextStyle(color: p.ink))))
            : s == null
                ? const Center(child: CircularProgressIndicator())
                : _read(p, s),
      ),
    );
  }

  /// The story in its parts: deck bullets, byline, paragraphs, subheadings and markers in reading order; photo captions and boxed
  /// "also on this page" notes gathered under the story, never inside the paragraphs.
  List<Widget> _storyBody(GatiPalette p, List<Map<String, dynamic>> items) {
    final out = <Widget>[];
    for (final it in items) {
      final text = it['text'] as String;
      switch (it['role'] as String) {
        case 'deck':
          out.add(Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(text.startsWith('\u2022') ? text : '\u2022 $text',
                  style: TextStyle(fontSize: 18, height: 1.5, fontWeight: FontWeight.w600, color: p.ink))));
        case 'byline':
          out.add(Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 10),
              child: Text('Byline: $text',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: kAccent))));
        case 'subhead':
          out.add(Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 8),
              child: Text(text, style: TextStyle(fontSize: 21, height: 1.4, fontWeight: FontWeight.w700, color: p.ink))));
        case 'marker':
          out.add(Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 10),
              child: Text('\u2014 $text \u2014', style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: p.muted))));
        case 'body':
          out.add(Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(text, style: TextStyle(fontSize: 18, height: 1.75, color: p.ink))));
      }
    }
    final side = items.where((i) => i['role'] == 'sidebar').toList();
    if (side.isNotEmpty) {
      out.add(const SizedBox(height: 8));
      out.add(Text('Also on this page', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kAccent)));
      for (final i in side) {
        out.add(Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: p.surface, borderRadius: BorderRadius.circular(Gati.rCard), border: Border.all(color: p.line)),
          child: Text(i['text'] as String, style: TextStyle(fontSize: 16, height: 1.6, color: p.ink)),
        ));
      }
    }
    final caps = items.where((i) => i['role'] == 'caption').toList();
    if (caps.isNotEmpty) {
      out.add(const SizedBox(height: 16));
      out.add(Text('Photo captions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kAccent)));
      for (final i in caps) {
        out.add(Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(i['text'] as String, style: TextStyle(fontSize: 14, height: 1.5, color: p.muted))));
      }
    }
    return out;
  }

  Widget _read(GatiPalette p, Map<String, dynamic> s) {
    final head = (s['headline'] as String).trim();
    final graphic = (s['graphic'] as List?)?.cast<num>();
    final label = (s['label'] as String?) ?? '';
    final items = (s['items'] as List).cast<Map<String, dynamic>>();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 80), children: [
          Text(kPaperNotice, style: TextStyle(fontSize: 12, color: kAccent)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            Chip(label: Text(s['section'] == 'Editorial' ? 'Editorial news' : '${s['section']}')),
            if (label.isNotEmpty) Chip(label: Text('Eenadu page: $label')),
          ]),
          const SizedBox(height: 6),
          if (graphic != null) ...[
            Text('headline: graphic (no text in the PDF; needs OCR)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kAccent)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                color: Colors.white,
                width: double.infinity,
                child: Image.network(
                    _api('crop', {
                      'edition': widget.edition,
                      'date': widget.date,
                      'page': '${s['page']}',
                      'box': graphic.map((v) => v.toDouble().toStringAsFixed(4)).join(','),
                    }).toString(),
                    fit: BoxFit.fitWidth,
                    errorBuilder: (c, e, st) => const SizedBox(height: 30, child: Center(child: Text('picture unavailable')))),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (((s['kicker'] as String?) ?? '').isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(s['kicker'] as String, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.muted))),
          if (head.isNotEmpty)
            Text(head, style: TextStyle(fontSize: 24, height: 1.35, fontWeight: FontWeight.w700, color: p.ink))
          else if (graphic == null)
            Text('(no headline in the PDF text)', style: TextStyle(fontSize: 16, color: p.muted)),
          const SizedBox(height: 14),
          ..._storyBody(p, items),
        ]),
      ),
    );
  }
}

/// Used by the Paper tab to show the entry only in the local review build.
bool get paperTodayAvailable => kEenaduReview;
