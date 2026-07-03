import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/districts.dart';
import '../design/tokens.dart';
import '../services/document_service.dart';
import '../services/settings_provider.dart';

/// Vāni — GatiVāni's grounded assistant, as a bottom-sheet chat. Edition
/// articles are grounded server-side from the DB; web stories and podcasts
/// (which aren't in the DB) pass their text via [articleText] so Vāni can
/// answer about them too.
class AssistantSheet extends StatefulWidget {
  const AssistantSheet(
      {super.key,
      required this.articleId,
      required this.articleTitle,
      this.articleText,
      this.general = false});
  final String articleId;
  final String articleTitle;
  final String? articleText;

  /// Global mode (the floating Vāni button): not tied to one article —
  /// grounded on today's content index, may use general knowledge for
  /// non-news questions, and can ACT on the app (e.g. a location question
  /// sets the district filter on the Live + Paper lists).
  final bool general;

  static void open(BuildContext context, String articleId, String title,
      {String? articleText, bool general = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AssistantSheet(
          articleId: articleId,
          articleTitle: title,
          articleText: articleText,
          general: general),
    );
  }

  @override
  State<AssistantSheet> createState() => _AssistantSheetState();
}

class _AssistantSheetState extends State<AssistantSheet> {
  final _svc = DocumentService();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <({bool me, String text})>[];
  bool _busy = false;

  static const _articleSuggestions = [
    'Summarize this article',
    'Give me the background',
    'What are the key facts?',
  ];
  static const _generalSuggestions = [
    'హైదరాబాద్ వార్తలు చూపించు',
    "What's today's top story?",
    'Summarize today’s news',
  ];

  List<String> get _suggestions =>
      widget.general ? _generalSuggestions : _articleSuggestions;

  // Location intent: a question naming a district is an APP ACTION, not a
  // chat completion — set the district preference + location sort so the
  // Live and Paper lists both show that place's news, and confirm in chat.
  bool _tryDistrictAction(String q) {
    if (!widget.general) return false;
    for (final d in kDistricts) {
      if (q.contains(d.te) || q.toLowerCase().contains(d.en.toLowerCase())) {
        final s = context.read<SettingsProvider>();
        s.setDistrict(d.en);
        s.setFeedSort('location');
        s.setDistrictOnly(true);
        setState(() => _msgs.add((
              me: false,
              text: s.lang == 'te'
                  ? '${d.te} వార్తలను చూపిస్తున్నాను — లైవ్, పేపర్ రెండు ట్యాబ్‌లలో వర్తిస్తుంది. ఫిల్టర్ మెనూలో "${'నా జిల్లా మాత్రమే'}" తీసేస్తే అన్ని వార్తలు కనిపిస్తాయి.'
                  : 'Showing ${d.en} news — applied to both the Live and Paper tabs. Clear "My district only" from the filter menu to see everything again.'
            )));
        return true;
      }
    }
    return false;
  }

  Future<void> _send(String q) async {
    q = q.trim();
    if (q.isEmpty || _busy) return;
    setState(() {
      _msgs.add((me: true, text: q));
      _input.clear();
    });
    _scrollDown();
    if (_tryDistrictAction(q)) {
      _scrollDown();
      return;
    }
    setState(() => _busy = true);
    try {
      final a = await _svc.ask(widget.articleId, q,
          articleText: widget.articleText,
          articleTitle: widget.articleTitle,
          general: widget.general);
      setState(() => _msgs.add((me: false, text: a)));
    } catch (e) {
      setState(() => _msgs.add((me: false, text: 'Sorry — $e')));
    } finally {
      setState(() => _busy = false);
      _scrollDown();
    }
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      padding: EdgeInsets.only(bottom: inset),
      decoration: const BoxDecoration(
        color: Gati.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        const SizedBox(height: 10),
        Container(width: 36, height: 4, decoration: BoxDecoration(
            color: const Color(0xFFD3D1C7), borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(children: [
            const Icon(Icons.graphic_eq, color: Gati.accent, size: 18),
            const SizedBox(width: 8),
            const Text('Vāni',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Gati.ink)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: Gati.muted, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),
        Expanded(
          child: _msgs.isEmpty
              ? _empty()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  itemCount: _msgs.length + (_busy ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= _msgs.length) return _bubble(false, '…');
                    final m = _msgs[i];
                    return _bubble(m.me, m.text);
                  },
                ),
        ),
        _inputBar(),
      ]),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.general
                      ? 'Ask Vāni anything — today’s news, a place,\nor just a question.'
                      : 'Ask anything about the article you’re listening to,\nor today’s edition.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: Gati.muted, height: 1.5)),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _suggestions)
                    GestureDetector(
                      onTap: () => _send(s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFFE7E4DB)),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(s, style: const TextStyle(fontSize: 12.5, color: Gati.ink)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _bubble(bool me, String text) => Align(
        alignment: me ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: me ? Gati.ink : Colors.white,
            border: me ? null : Border.all(color: const Color(0xFFE7E4DB)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(text,
              style: TextStyle(
                  fontSize: 14, height: 1.5, color: me ? Gati.onInk : Gati.ink)),
        ),
      );

  Widget _inputBar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              decoration: InputDecoration(
                hintText: 'Ask a question…',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: Color(0xFFE7E4DB))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: Color(0xFFE7E4DB))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: Gati.accent)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _send(_input.text),
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: Gati.accent, shape: BoxShape.circle),
              child: const Icon(Icons.arrow_upward, color: Gati.onInk, size: 20),
            ),
          ),
        ]),
      );
}
