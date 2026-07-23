import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../design/tokens.dart';
import '../../services/gemini_key_store.dart';

/// The mandatory stop between "tap play" and "hear anything": every article —
/// Live or Paper — is narrated on the LISTENER's own Gemini key, never a
/// shared one. PlaybackService pushes this route instead of starting
/// playback whenever GeminiKeyStore has no key yet.
class GeminiKeyGateScreen extends StatefulWidget {
  const GeminiKeyGateScreen({super.key});

  @override
  State<GeminiKeyGateScreen> createState() => _GeminiKeyGateScreenState();
}

class _GeminiKeyGateScreenState extends State<GeminiKeyGateScreen> {
  final _ctrl = TextEditingController(text: GeminiKeyStore.key ?? '');
  bool _hidden = true;
  bool _validating = false;
  String? _error;

  // Auto-cycling illustrated tutorial — 4 steps, ~2.3s each, so one full loop
  // reads in about 9 seconds without the user touching anything.
  static const _steps = [
    (Icons.open_in_new_rounded, 'Open Google AI Studio'),
    (Icons.add_circle_outline_rounded, 'Tap "Create API key"'),
    (Icons.edit_outlined, 'Name it "Gativani Api Key"'),
    (Icons.copy_all_rounded, 'Copy it and paste below'),
  ];
  int _step = 0;
  Timer? _cycle;

  @override
  void initState() {
    super.initState();
    _cycle = Timer.periodic(const Duration(milliseconds: 2300), (_) {
      if (mounted) setState(() => _step = (_step + 1) % _steps.length);
    });
  }

  @override
  void dispose() {
    _cycle?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

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
    if (key.isEmpty) return;
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
    if (mounted && context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        backgroundColor: p.paper,
        surfaceTintColor: p.paper,
        elevation: 0,
        foregroundColor: p.ink,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          children: [
            const Icon(Icons.key_rounded, color: kAccent, size: 34),
            const SizedBox(height: 14),
            Text('Bring your own Gemini key',
                style: TextStyle(
                    fontSize: 23, fontWeight: FontWeight.w600, color: p.ink)),
            const SizedBox(height: 8),
            Text(
              "Narrating an article — Live or Paper — costs real money to "
              "synthesize. So it runs on your own free Gemini key instead "
              "of GatiVāni's — that's what keeps this free for everyone.",
              style: TextStyle(fontSize: 14, color: p.muted, height: 1.45),
            ),
            const SizedBox(height: 24),

            // ── Illustrated 4-step tutorial, auto-cycling ──────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: kInk, borderRadius: BorderRadius.circular(18)),
              child: Column(children: [
                SizedBox(
                  height: 78,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(
                                begin: const Offset(0, 0.15),
                                end: Offset.zero)
                            .animate(anim),
                        child: child,
                      ),
                    ),
                    child: Column(
                      key: ValueKey(_step),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_steps[_step].$1, color: Gati.pasupuGlow, size: 30),
                        const SizedBox(height: 10),
                        Text(_steps[_step].$2,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: kPaper,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _steps.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _step ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color:
                            i == _step ? Gati.pasupu : Gati.onInkMuted,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 18),

            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: kPaper,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              onPressed: () => launchUrl(
                  Uri.parse('https://aistudio.google.com/apikey'),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Create your key',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 24),

            // ── Paste + validate ───────────────────────────────────────────
            Text('Paste it here',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: p.ink)),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              obscureText: _hidden,
              style: TextStyle(color: p.ink),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Paste your Gemini API key',
                hintStyle: TextStyle(color: p.muted, fontSize: 13),
                filled: true,
                fillColor: p.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kAccent),
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
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: kPaper,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              onPressed: _validating ? null : _save,
              child: _validating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kPaper))
                  : const Text('Save and continue',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}
