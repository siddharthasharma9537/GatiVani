import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../design/tokens.dart';
import 'review_screen.dart' show kEenaduReview;

/// "Today's paper": Eenadu's e-paper as news inside the app, grouped by the paper's own page labels. Local only: it talks to
/// scripts/eenadu_review_server.py on the same origin (the owner's Mac), is compiled in only with --dart-define=EENADU_REVIEW=true,
/// and writes nothing anywhere. Nothing here is narrated: no text leaves the Mac.
const String kPaperNotice =
    'Machine-converted from the printed PDF, not proofread. Eenadu text: owner only, on this Mac.';

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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _editions = (await _get(_api('editions')) as List).cast<Map<String, dynamic>>();
      if (_editions.isEmpty) throw 'No editions found.';
      await _pick(_editions.first);
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _pick(Map<String, dynamic> ed) async {
    setState(() { _ed = ed; _loading = true; _error = null; });
    try {
      final d = await _get(_api('paper', {'edition': ed['edition'] as String, 'date': ed['date'] as String}));
      final secs = ((d as Map)['sections'] as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() { _sections = secs; _sel = secs.isEmpty ? null : secs.first['name'] as String; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
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
        title: Text(_ed == null ? "Today's paper" : "${_ed!['edition']} · ${_ed!['date']}", style: const TextStyle(fontSize: 15)),
        actions: [
          if (_editions.length > 1)
            PopupMenuButton<Map<String, dynamic>>(
              tooltip: 'Edition',
              icon: const Icon(Icons.swap_horiz),
              onSelected: _pick,
              itemBuilder: (_) => [
                for (final e in _editions) PopupMenuItem(value: e, child: Text("${e['edition']} · ${e['date']}")),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
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

  @override
  void initState() {
    super.initState();
    _get(_api('story', {'edition': widget.edition, 'date': widget.date, 'id': widget.id}))
        .then((d) => mounted ? setState(() => _s = d as Map<String, dynamic>) : null)
        .catchError((e) { if (mounted) setState(() => _error = '$e'); });
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
        title: Text(s == null ? 'Story' : "${widget.edition} · page ${s['page']}", style: const TextStyle(fontSize: 15)),
      ),
      body: SafeArea(
        child: _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: TextStyle(color: p.ink))))
            : s == null
                ? const Center(child: CircularProgressIndicator())
                : _read(p, s),
      ),
    );
  }

  Widget _read(GatiPalette p, Map<String, dynamic> s) {
    final head = (s['headline'] as String).trim();
    final graphic = (s['graphic'] as List?)?.cast<num>();
    final label = (s['label'] as String?) ?? '';
    final paras = (s['paras'] as List).cast<String>();
    final unmatched = ((s['contTo'] as List?) ?? const []).cast<Map>().where((c) => c['linked'] != true).toList();
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
          if (head.isNotEmpty)
            Text(head, style: TextStyle(fontSize: 24, height: 1.35, fontWeight: FontWeight.w700, color: p.ink))
          else if (graphic == null)
            Text('(no headline in the PDF text)', style: TextStyle(fontSize: 16, color: p.muted)),
          const SizedBox(height: 14),
          for (final t in paras)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: t.startsWith('— continued')
                  ? Text(t, style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: p.muted))
                  : Text(t, style: TextStyle(fontSize: 18, height: 1.75, color: p.ink)),
            ),
          if (unmatched.isNotEmpty)
            Text(
                'The story says it continues on page ${unmatched.map((c) => c['page']).join(', ')}; that part could not be matched '
                'automatically yet.',
                style: TextStyle(fontSize: 13, color: kAccent)),
        ]),
      ),
    );
  }
}

/// Used by the Paper tab to show the entry only in the local review build.
bool get paperTodayAvailable => kEenaduReview;
