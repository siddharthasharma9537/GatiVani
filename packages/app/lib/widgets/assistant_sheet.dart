import 'package:flutter/material.dart';
import '../design/tokens.dart';
import '../services/document_service.dart';

/// Grounded "ask about this edition" chat. Opens as a bottom sheet over the
/// player; answers come only from the article + edition content.
class AssistantSheet extends StatefulWidget {
  const AssistantSheet({super.key, required this.articleId, required this.articleTitle});
  final String articleId;
  final String articleTitle;

  static void open(BuildContext context, String articleId, String title) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AssistantSheet(articleId: articleId, articleTitle: title),
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

  static const _suggestions = [
    'Summarize this article',
    'Give me the background',
    'What are the key facts?',
  ];

  Future<void> _send(String q) async {
    q = q.trim();
    if (q.isEmpty || _busy) return;
    setState(() {
      _msgs.add((me: true, text: q));
      _busy = true;
      _input.clear();
    });
    _scrollDown();
    try {
      final a = await _svc.ask(widget.articleId, q);
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
            const Icon(Icons.auto_awesome, color: Gati.accent, size: 18),
            const SizedBox(width: 8),
            const Text('Ask about this edition',
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
              const Text('Ask anything about the article you’re listening to,\nor today’s edition.',
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
