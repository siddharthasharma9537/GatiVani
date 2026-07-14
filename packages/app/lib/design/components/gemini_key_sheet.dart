import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../services/gemini_key_store.dart';
import '../tokens.dart';

/// BYOK entry point (menu → GatiVāni → Gemini API key). Narrating/processing
/// a user's own uploaded Paper edition runs on their own Gemini key instead of
/// a shared one — the key is cached locally (see GeminiKeyStore), attached as
/// a header on requests the user themselves triggers, and synced to their
/// account so it carries over to other signed-in devices.
void showGeminiKeySheet(BuildContext context) {
  final p = GatiPalette.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.paper,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _GeminiKeySheet(),
  );
}

class _GeminiKeySheet extends StatefulWidget {
  const _GeminiKeySheet();

  @override
  State<_GeminiKeySheet> createState() => _GeminiKeySheetState();
}

class _GeminiKeySheetState extends State<_GeminiKeySheet> {
  late final _ctrl = TextEditingController(text: GeminiKeyStore.key ?? '');
  bool _hidden = true;
  bool _validating = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Confirms the key actually works before saving it — straight from the
  /// browser to Google (models.list is free: no generation, just an auth
  /// check), so the key never touches our server even for validation.
  Future<String?> _validate(String key) async {
    try {
      final r = await http
          .get(Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models?key=$key'))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) return null;
      final body = json.decode(r.body) as Map<String, dynamic>;
      return (body['error'] as Map<String, dynamic>?)?['message'] as String? ??
          'That key doesn\'t work (HTTP ${r.statusCode}).';
    } catch (_) {
      return 'Could not reach Google to check the key. Check your connection.';
    }
  }

  Future<void> _save() async {
    final key = _ctrl.text.trim();
    if (key.isEmpty) {
      await GeminiKeyStore.setKey(null);
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _validating = true;
      _error = null;
    });
    final error = await _validate(key);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _validating = false;
        _error = error;
      });
      return;
    }
    await GeminiKeyStore.setKey(key);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _clear() async {
    _ctrl.clear();
    _error = null;
    await GeminiKeyStore.setKey(null);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: p.line, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Gemini API key',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, color: p.ink)),
          const SizedBox(height: 6),
          Text(
            "Narrating your uploaded Paper editions runs on your own free "
            "Gemini key, not GatiVāni's — saved to your account, so you "
            "won't need to re-enter it on other signed-in devices.",
            style: TextStyle(fontSize: 13, color: p.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            obscureText: _hidden,
            style: TextStyle(color: p.ink),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Paste your Gemini API key',
              hintStyle: TextStyle(color: p.muted, fontSize: 13),
              filled: true,
              fillColor: p.chip,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Gati.rCard),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                    _hidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: p.muted),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(fontSize: 12.5, color: Gati.kumkuma)),
          ],
          const SizedBox(height: 12),
          Row(children: [
            TextButton(
              onPressed: () => launchUrl(
                  Uri.parse('https://aistudio.google.com/apikey'),
                  mode: LaunchMode.externalApplication),
              child: const Text('Get a free key'),
            ),
            const Spacer(),
            if (GeminiKeyStore.hasKey)
              TextButton(
                onPressed: _validating ? null : _clear,
                child: Text('Clear', style: TextStyle(color: Gati.kumkuma)),
              ),
            const SizedBox(width: 4),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: kAccent, foregroundColor: kPaper),
              onPressed: _validating ? null : _save,
              child: _validating
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kPaper))
                  : const Text('Save'),
            ),
          ]),
        ],
      ),
    );
  }
}
