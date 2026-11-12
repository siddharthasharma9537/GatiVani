import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../design/tokens.dart';

/// Built in only with `--dart-define=EENADU_REVIEW=true`; the normal and
/// deployed builds never contain the route.
const bool kEenaduReview = bool.fromEnvironment('EENADU_REVIEW');

/// Local-only review of converted Eenadu text (personal use, owner's Mac).
/// Talks to scripts/eenadu_review_server.py on the same origin; nothing here
/// goes to Supabase or any other host.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  List<Map<String, dynamic>> _editions = [];
  Map<String, dynamic>? _ed; // the chosen edition entry
  int _page = 1;
  Map<String, dynamic>? _data; // current page: width, height, blocks
  Map<String, dynamic> _results = {}; // blockId -> {verdict}
  String? _selected;
  String? _error;
  bool _loading = true;

  Uri _api(String route, [Map<String, String> q = const {}]) =>
      Uri.base.replace(path: '/review-api/$route', queryParameters: q, fragment: '');

  Map<String, String> get _edQ =>
      {'edition': _ed!['edition'] as String, 'date': _ed!['date'] as String};

  Future<dynamic> _get(Uri u) async {
    final r = await http.get(u);
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode} (open the link with the key the server printed)';
    return json.decode(utf8.decode(r.bodyBytes));
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final list = (await _get(_api('editions')) as List).cast<Map<String, dynamic>>();
      _editions = list;
      if (list.isEmpty) throw 'No editions found in the Drive folder.';
      await _pick(list.first);
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _pick(Map<String, dynamic> ed) async {
    _ed = ed;
    _page = 1;
    _results = Map<String, dynamic>.from(await _get(_api('results', _edQ)) as Map);
    await _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _selected = null; });
    try {
      final d = await _get(_api('page', {..._edQ, 'page': '$_page'}));
      if (mounted) setState(() { _data = d as Map<String, dynamic>; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _verdict(String id, String v) async {
    setState(() {
      if (_results[id]?['verdict'] == v) {
        _results.remove(id); // tapping the same choice again clears it
      } else {
        _results[id] = {'verdict': v};
      }
    });
    final r = await http.put(_api('results', _edQ), body: json.encode(_results));
    if (r.statusCode != 200 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save (HTTP ${r.statusCode})')));
    }
  }

  void _go(int delta) {
    final n = (_ed!['pages'] as num).toInt();
    final p = (_page + delta).clamp(1, n);
    if (p == _page) return;
    _page = p;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final blocks = ((_data?['blocks'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final done = blocks.where((b) => _results.containsKey(b['id'])).length;
    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        backgroundColor: p.paper,
        foregroundColor: p.ink,
        title: Text(_ed == null ? 'Eenadu review' : '${_ed!['edition']} · ${_ed!['date']}',
            style: const TextStyle(fontSize: 16)),
        actions: [
          if (_editions.length > 1)
            PopupMenuButton<Map<String, dynamic>>(
              tooltip: 'Edition',
              icon: const Icon(Icons.swap_horiz),
              onSelected: (e) async { setState(() => _loading = true); await _pick(e); },
              itemBuilder: (_) => [
                for (final e in _editions)
                  PopupMenuItem(value: e, child: Text('${e['edition']} · ${e['date']}')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          if (_ed != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                IconButton(
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    tooltip: 'Previous page',
                    onPressed: _page > 1 ? () => _go(-1) : null,
                    icon: const Icon(Icons.chevron_left)),
                Text('Page $_page of ${_ed!['pages']}', style: TextStyle(color: p.ink)),
                IconButton(
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    tooltip: 'Next page',
                    onPressed: _page < (_ed!['pages'] as num).toInt() ? () => _go(1) : null,
                    icon: const Icon(Icons.chevron_right)),
                const Spacer(),
                Text('$done / ${blocks.length} reviewed',
                    style: TextStyle(fontSize: 12.5, color: p.muted)),
              ]),
            ),
          Expanded(child: _body(p, blocks)),
        ]),
      ),
    );
  }

  Widget _body(GatiPalette p, List<Map<String, dynamic>> blocks) {
    if (_error != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, style: TextStyle(color: p.ink))));
    }
    if (_loading || _data == null) return const Center(child: CircularProgressIndicator());
    final image = _PageImage(
      url: _api('image', {..._edQ, 'page': '$_page'}).toString(),
      aspect: (_data!['width'] as num) / (_data!['height'] as num),
      box: blocks.where((b) => b['id'] == _selected).map((b) => (b['box'] as List).cast<num>()).firstOrNull,
    );
    final byId = {for (final b in blocks) b['id'] as String: b};
    final arts = ((_data!['articles'] as List?) ?? const []).cast<Map<String, dynamic>>();
    var n = 0;
    final list = [
      for (final a in arts) ...[
        _articleHeader(p, a),
        for (final id in (a['blockIds'] as List).cast<String>())
          if (byId[id] != null) _blockCard(p, byId[id]!, ++n),
      ],
      if (blocks.isEmpty)
        Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No body-text blocks on this page.', style: TextStyle(color: p.muted))),
    ];
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: c.maxWidth * 0.45, child: SingleChildScrollView(child: image)),
          Expanded(child: ListView(padding: const EdgeInsets.all(12), children: list)),
        ]);
      }
      return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 40), children: [image, const SizedBox(height: 12), ...list]);
    });
  }

  // FIRST CUT grouping: a headline block starts an article, the body blocks after it belong to it.
  Widget _articleHeader(GatiPalette p, Map<String, dynamic> a) {
    final h = (a['headline'] as String?) ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(h.isEmpty ? 'Other text on the page' : 'Article (first-cut grouping)',
            style: TextStyle(fontSize: 11.5, color: p.muted)),
        if (h.isNotEmpty)
          Text(h, style: TextStyle(fontSize: 17, height: 1.35, fontWeight: FontWeight.w600, color: p.ink)),
      ]),
    );
  }

  Widget _blockCard(GatiPalette p, Map<String, dynamic> b, int n) {
    final id = b['id'] as String;
    final v = _results[id]?['verdict'] as String?;
    final sel = _selected == id;
    final lines = (b['lines'] as List).cast<Map<String, dynamic>>();
    return Card(
      color: p.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Gati.rCard),
          side: BorderSide(color: sel ? kAccent : p.line, width: sel ? 2 : 1)),
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(Gati.rCard),
        onTap: () => setState(() => _selected = id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Block $n · ${lines.length} lines · ${b['kind'] == 'headline' ? 'headline' : 'body'}',
                style: TextStyle(fontSize: 12, color: p.muted)),
            const SizedBox(height: 6),
            for (final l in lines) ...[
              Text('Direct reading: ${l['converted']}',
                  style: TextStyle(fontSize: 14, height: 1.4, color: p.ink)),
              if (l['old'] != null)
                Text('Old table: ${l['old']}',
                    style: TextStyle(fontSize: 13, height: 1.4, color: p.muted)),
              if ((l['fonts'] as List).any((f) => f != 'Eenadu-Light'))
                Text('Font: ${(l['fonts'] as List).join(', ')}',
                    style: TextStyle(fontSize: 11.5, color: p.muted)),
              Text('OCR: ${l['ocr'] ?? '(none for this edition)'}',
                  style: TextStyle(fontSize: 13, height: 1.4, color: p.muted)),
              const SizedBox(height: 6),
            ],
            Row(children: [
              _verdictBtn('OK', v == 'ok', () => _verdict(id, 'ok')),
              const SizedBox(width: 8),
              _verdictBtn('Fix', v == 'fix', () => _verdict(id, 'fix')),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _verdictBtn(String label, bool on, VoidCallback f) => FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size(72, 44),
          backgroundColor: on ? kAccent : Colors.transparent,
          foregroundColor: on ? kPaper : kAccent,
          side: const BorderSide(color: kAccent),
        ),
        onPressed: f,
        child: Text(label),
      );
}

class _PageImage extends StatelessWidget {
  const _PageImage({required this.url, required this.aspect, this.box});
  final String url;
  final double aspect;
  final List<num>? box; // x0,y0,x1,y1 as fractions of the page

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspect,
      child: LayoutBuilder(builder: (context, c) {
        return Stack(children: [
          Positioned.fill(child: Image.network(url, fit: BoxFit.fill)),
          if (box != null)
            Positioned(
              left: box![0] * c.maxWidth,
              top: box![1] * c.maxHeight,
              width: (box![2] - box![0]) * c.maxWidth,
              height: (box![3] - box![1]) * c.maxHeight,
              child: Container(
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: 0.18),
                  border: Border.all(color: kAccent, width: 2),
                ),
              ),
            ),
        ]);
      }),
    );
  }
}
