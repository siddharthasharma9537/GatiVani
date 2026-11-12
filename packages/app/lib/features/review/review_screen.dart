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
///
/// Built for a phone: every block row carries its own cropped picture of the
/// page, so nothing has to be looked up on the page image; the header with the
/// page navigation, filter and counts stays on screen.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  List<Map<String, dynamic>> _editions = [];
  Map<String, dynamic>? _ed; // the chosen edition entry
  int _page = 1;
  Map<String, dynamic>? _data; // current page: width, height, blocks, articles
  Map<String, dynamic> _results = {}; // blockId -> {verdict, note}
  String? _selected;
  String? _error;
  bool _loading = true;
  bool _onlyLook = true; // "only blocks that need a look"
  bool _jumpFirst = false; // after a page change by "Next unreviewed"
  final Map<String, GlobalKey> _keys = {};
  final Map<String, TextEditingController> _notes = {};
  Timer? _noteTimer;

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

  @override
  void dispose() {
    _noteTimer?.cancel();
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
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
    setState(() { _loading = true; _error = null; _selected = null; _keys.clear(); });
    try {
      final d = await _get(_api('page', {..._edQ, 'page': '$_page'}));
      if (!mounted) return;
      setState(() { _data = d as Map<String, dynamic>; _loading = false; });
      if (_jumpFirst) {
        _jumpFirst = false;
        _nextUnreviewed(fromPageStart: true);
      }
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  List<Map<String, dynamic>> get _blocks =>
      ((_data?['blocks'] as List?) ?? const []).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> get _shown =>
      _blocks.where((b) => !_onlyLook || b['needsLook'] == true).toList();

  // Eenadu's own name for this page ("EDITORIAL", "BUSINESS"...); empty for plain pages
  String get _pageLabel => (_data?['label'] as String?) ?? '';
  String get _pageSection => (_data?['section'] as String?) ?? '';

  String? _verdictOf(String id) => (_results[id] as Map?)?['verdict'] as String?;

  Future<void> _persist() async {
    try {
      final r = await http.put(_api('results', _edQ), body: json.encode(_results));
      if (r.statusCode != 200 && mounted) _toast('Could not save (HTTP ${r.statusCode})');
    } catch (e) {
      if (mounted) _toast('Could not save: $e');
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

  void _setVerdict(String id, String v) {
    setState(() {
      final cur = Map<String, dynamic>.from((_results[id] as Map?) ?? {});
      if (cur['verdict'] == v) {
        cur.remove('verdict'); // tapping the same choice again clears it
      } else {
        cur['verdict'] = v;
      }
      if (cur.isEmpty) {
        _results.remove(id);
      } else {
        _results[id] = cur;
      }
    });
    _persist();
  }

  void _noteChanged(String id, String text) {
    final cur = Map<String, dynamic>.from((_results[id] as Map?) ?? {});
    if (text.isEmpty) {
      cur.remove('note');
    } else {
      cur['note'] = text;
    }
    _results[id] = cur;
    _noteTimer?.cancel();
    _noteTimer = Timer(const Duration(milliseconds: 700), _persist);
  }

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, () => GlobalKey());

  void _select(String id, {bool scroll = false}) {
    setState(() => _selected = id);
    if (scroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keys[id]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx, alignment: 0.05, duration: const Duration(milliseconds: 250));
        }
      });
    }
  }

  // Tapping the page picture picks the (smallest) block under the finger and jumps to its row.
  void _tapPage(double fx, double fy) {
    Map<String, dynamic>? best;
    var bestArea = double.infinity;
    for (final b in _blocks) {
      final bx = (b['box'] as List).cast<num>();
      if (fx >= bx[0] && fx <= bx[2] && fy >= bx[1] && fy <= bx[3]) {
        final a = (bx[2] - bx[0]) * (bx[3] - bx[1]);
        if (a < bestArea) {
          bestArea = a.toDouble();
          best = b;
        }
      }
    }
    if (best == null) return;
    if (_onlyLook && best['needsLook'] != true) {
      setState(() => _onlyLook = false); // the block is hidden by the filter: show everything so it can be reached
    }
    _select(best['id'] as String, scroll: true);
  }

  void _nextUnreviewed({bool fromPageStart = false}) {
    final shown = _shown;
    var start = 0;
    if (!fromPageStart && _selected != null) {
      final i = shown.indexWhere((b) => b['id'] == _selected);
      if (i >= 0) start = i + 1;
    }
    for (var k = 0; k < shown.length; k++) {
      final b = shown[(start + k) % shown.length];
      if (_verdictOf(b['id'] as String) == null) {
        _select(b['id'] as String, scroll: true);
        return;
      }
    }
    // nothing left on this page: go on to the next one
    final n = (_ed!['pages'] as num).toInt();
    if (_page < n) {
      _jumpFirst = true;
      _page += 1;
      _load();
    } else {
      _toast('Everything shown has been reviewed.');
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
    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        backgroundColor: p.paper,
        foregroundColor: p.ink,
        toolbarHeight: 44,
        title: Text(_ed == null ? 'Eenadu review' : '${_ed!['edition']} · ${_ed!['date']}',
            style: const TextStyle(fontSize: 15)),
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
          if (_ed != null) _header(p),
          Expanded(child: _body(p)),
        ]),
      ),
    );
  }

  // Sticky header: page navigation, counts, filter and "next unreviewed" stay on screen while the rows scroll.
  Widget _header(GatiPalette p) {
    final shown = _shown;
    final doneShown = shown.where((b) => _verdictOf(b['id'] as String) != null).length;
    final pages = (_ed!['pages'] as num).toInt();
    return Material(
      color: p.paper,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 8, 6),
        child: Column(children: [
          Row(children: [
            IconButton(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: 'Previous page',
                onPressed: _page > 1 ? () => _go(-1) : null,
                icon: const Icon(Icons.chevron_left)),
            Text('Page $_page / $pages${_pageLabel.isEmpty ? '' : ' · $_pageLabel'}',
                style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
            IconButton(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: 'Next page',
                onPressed: _page < pages ? () => _go(1) : null,
                icon: const Icon(Icons.chevron_right)),
            const Spacer(),
            Text('$doneShown / ${shown.length} reviewed · ${_results.length} in all',
                style: TextStyle(fontSize: 12.5, color: p.muted)),
          ]),
          Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilterChip(
              materialTapTargetSize: MaterialTapTargetSize.padded,
              label: const Text('Only blocks that need a look'),
              selected: _onlyLook,
              onSelected: (v) => setState(() => _onlyLook = v),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(44, 48), backgroundColor: kAccent, foregroundColor: kPaper),
              onPressed: _nextUnreviewed,
              child: const Text('Next unreviewed'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _body(GatiPalette p) {
    if (_error != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, style: TextStyle(color: p.ink))));
    }
    if (_loading || _data == null) return const Center(child: CircularProgressIndicator());
    final blocks = _blocks;
    final byId = {for (final b in blocks) b['id'] as String: b};
    final selBox = blocks
        .where((b) => b['id'] == _selected)
        .map((b) => (b['box'] as List).cast<num>())
        .firstOrNull;
    final image = _PageImage(
      url: _api('image', {..._edQ, 'page': '$_page'}).toString(),
      aspect: (_data!['width'] as num) / (_data!['height'] as num),
      box: selBox,
      onTap: _tapPage,
    );
    final arts = ((_data!['articles'] as List?) ?? const []).cast<Map<String, dynamic>>();
    var n = 0;
    final rows = <Widget>[];
    for (final a in arts) {
      final ids = (a['blockIds'] as List)
          .cast<String>()
          .where((id) => byId[id] != null && (!_onlyLook || byId[id]!['needsLook'] == true))
          .toList();
      if (ids.isEmpty) continue;
      if (rows.isEmpty && _pageSection.isNotEmpty) {
        // the page's own label decides the section: every story below is tagged with it
        rows.add(Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text(_pageSection,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kAccent))));
      }
      rows.add(_articleHeader(p, a));
      for (final id in ids) {
        rows.add(_blockCard(p, byId[id]!, ++n));
      }
    }
    if (rows.isEmpty) {
      rows.add(Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
              _onlyLook
                  ? 'Nothing on this page needs a look. Switch the filter off to see every block.'
                  : 'No text blocks on this page.',
              style: TextStyle(color: p.muted))));
    }
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: c.maxWidth * 0.42, child: SingleChildScrollView(child: image)),
          Expanded(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12), child: Column(children: rows))),
        ]);
      }
      return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 60),
          child: Column(children: [image, const SizedBox(height: 12), ...rows]));
    });
  }

  // FIRST CUT grouping: a headline block starts an article, the body blocks after it belong to it.
  Widget _articleHeader(GatiPalette p, Map<String, dynamic> a) {
    final h = (a['headline'] as String?) ?? '';
    final gbox = (a['graphicBox'] as List?)?.cast<num>();
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(h.isEmpty ? 'Other text on the page' : 'Article (first-cut grouping)',
              style: TextStyle(fontSize: 11.5, color: p.muted)),
          if (gbox != null) ...[
            // a wide picture sits right above this story: its big headline is probably printed as a picture,
            // with no text in the PDF, so the converter cannot read it
            Text('Headline is probably a picture (no text in the PDF): needs OCR',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kAccent)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                color: Colors.white,
                width: double.infinity,
                child: Image.network(_cropUri(gbox).toString(),
                    fit: BoxFit.fitWidth,
                    errorBuilder: (c, e, s) => const SizedBox(height: 30, child: Center(child: Text('picture unavailable')))),
              ),
            ),
            const SizedBox(height: 4),
          ],
          if (h.isNotEmpty)
            Text(h, style: TextStyle(fontSize: 17, height: 1.35, fontWeight: FontWeight.w600, color: p.ink)),
        ]),
      ),
    );
  }

  Uri _cropUri(List<num> b) => _api('crop', {
        ..._edQ,
        'page': '$_page',
        'box': b.map((v) => v.toDouble().toStringAsFixed(4)).join(','),
      });

  Widget _blockCard(GatiPalette p, Map<String, dynamic> b, int n) {
    final id = b['id'] as String;
    final v = _verdictOf(id);
    final sel = _selected == id;
    final hasOcr = b['hasOcr'] == true;
    final lines = (b['lines'] as List).cast<Map<String, dynamic>>();
    final box = (b['box'] as List).cast<num>();
    final note = _notes.putIfAbsent(
        id, () => TextEditingController(text: ((_results[id] as Map?)?['note'] as String?) ?? ''));
    return Card(
      key: _keyFor(id),
      color: p.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Gati.rCard),
          side: BorderSide(color: sel ? kAccent : p.line, width: sel ? 2 : 1)),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(Gati.rCard),
        onTap: () => setState(() => _selected = id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                'Block $n · ${lines.length} lines · ${b['kind'] == 'headline' ? 'headline' : 'body'}'
                '${hasOcr ? '' : ' · no OCR to compare'}',
                style: TextStyle(fontSize: 12, color: hasOcr ? p.muted : kAccent)),
            const SizedBox(height: 8),
            // the block as printed, so nothing has to be looked up on the page
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                color: Colors.white,
                width: double.infinity,
                child: Image.network(_cropUri(box).toString(),
                    fit: BoxFit.fitWidth,
                    loadingBuilder: (c, w, prog) => prog == null
                        ? w
                        : const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                    errorBuilder: (c, e, s) => const SizedBox(height: 40, child: Center(child: Text('picture unavailable')))),
              ),
            ),
            const SizedBox(height: 8),
            for (final l in lines) ...[
              Text('${l['converted']}', style: TextStyle(fontSize: 15, height: 1.45, color: p.ink)),
              if (hasOcr && l['ocr'] != null)
                Text('OCR: ${(l['ocr'] as String).isEmpty ? '(nothing read)' : l['ocr']}', style: TextStyle(fontSize: 13, height: 1.4, color: p.muted)),
              if ((l['fonts'] as List).any((f) => f != 'Eenadu-Light'))
                Text('Font: ${(l['fonts'] as List).join(', ')}',
                    style: TextStyle(fontSize: 11.5, color: p.muted)),
              const SizedBox(height: 6),
            ],
            Row(children: [
              Expanded(child: _verdictBtn('OK', v == 'ok', () => _setVerdict(id, 'ok'))),
              const SizedBox(width: 10),
              Expanded(child: _verdictBtn('Fix', v == 'fix', () => _setVerdict(id, 'fix'))),
            ]),
            if (v == 'fix') ...[
              const SizedBox(height: 8),
              TextField(
                controller: note,
                minLines: 2,
                maxLines: 5,
                style: TextStyle(fontSize: 15, color: p.ink),
                decoration: const InputDecoration(
                    hintText: 'What is wrong? (optional)', border: OutlineInputBorder(), isDense: true),
                onChanged: (t) => _noteChanged(id, t),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _verdictBtn(String label, bool on, VoidCallback f) => FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size(72, 56),
          backgroundColor: on ? kAccent : Colors.transparent,
          foregroundColor: on ? kPaper : kAccent,
          side: const BorderSide(color: kAccent),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        onPressed: f,
        child: Text(label),
      );
}

class _PageImage extends StatelessWidget {
  const _PageImage({required this.url, required this.aspect, this.box, this.onTap});
  final String url;
  final double aspect;
  final List<num>? box; // x0,y0,x1,y1 as fractions of the page
  final void Function(double fx, double fy)? onTap;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspect,
      child: LayoutBuilder(builder: (context, c) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => onTap?.call(d.localPosition.dx / c.maxWidth, d.localPosition.dy / c.maxHeight),
          child: Stack(children: [
            Positioned.fill(child: Image.network(url, fit: BoxFit.fill)),
            if (box != null)
              Positioned(
                left: box![0] * c.maxWidth,
                top: box![1] * c.maxHeight,
                width: (box![2] - box![0]) * c.maxWidth,
                height: (box![3] - box![1]) * c.maxHeight,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: kAccent.withValues(alpha: 0.18),
                      border: Border.all(color: kAccent, width: 2),
                    ),
                  ),
                ),
              ),
          ]),
        );
      }),
    );
  }
}
