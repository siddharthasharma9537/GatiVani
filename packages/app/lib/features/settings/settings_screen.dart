import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../design/tokens.dart';
import '../design/components/gati_wordmark.dart';
import '../l10n/strings.dart';
import '../services/gemini_key_store.dart';
import '../services/settings_provider.dart';

/// Dedicated Settings screen (menu → Settings): language, theme, playback
/// speed and the Gemini BYOK key all live here instead of inline in the
/// Menu drawer, which stays pure navigation.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _geminiCtrl =
      TextEditingController(text: GeminiKeyStore.key ?? '');
  bool _geminiHidden = true;
  bool _validating = false;
  String? _geminiError;

  @override
  void dispose() {
    _geminiCtrl.dispose();
    super.dispose();
  }

  /// Confirms the key actually works before saving — straight from the
  /// browser to Google (models.list is free: no generation, just an auth
  /// check), so the key never touches our server even for validation.
  Future<String?> _validateGeminiKey(String key) async {
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

  Future<void> _saveGeminiKey() async {
    final key = _geminiCtrl.text.trim();
    if (key.isEmpty) {
      await GeminiKeyStore.setKey(null);
      if (mounted) setState(() {});
      return;
    }
    setState(() {
      _validating = true;
      _geminiError = null;
    });
    final err = await _validateGeminiKey(key);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _validating = false;
        _geminiError = err;
      });
      return;
    }
    await GeminiKeyStore.setKey(key);
    if (mounted) setState(() => _validating = false);
  }

  Future<void> _clearGeminiKey() async {
    _geminiCtrl.clear();
    _geminiError = null;
    await GeminiKeyStore.setKey(null);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    final lang = s.lang;
    final p = GatiPalette.of(context);
    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        backgroundColor: p.paper,
        surfaceTintColor: p.paper,
        elevation: 0,
        foregroundColor: p.ink,
        title: Text(tr(lang, 'settings'),
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w500, color: p.ink)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // ── Language ─────────────────────────────────────────────────────
            _sectionLabel(p, tr(lang, 'language')),
            _card(p, Column(children: [
              _choiceRow(
                  p, 'English', s.lang == 'en', () => s.setLanguage('en')),
              Divider(height: 1, color: p.line),
              _choiceRow(
                  p, 'తెలుగు', s.lang == 'te', () => s.setLanguage('te')),
            ])),
            const SizedBox(height: 20),

            // ── News Language (content, not UI chrome) ──────────────────────
            _sectionLabel(p, 'News Language'),
            _card(p, Column(children: [
              _choiceRow(p, 'తెలుగు', s.newsLanguage == 'te',
                  () => s.setNewsLanguage('te'),
                  subtitle: 'Telugu'),
              Divider(height: 1, color: p.line),
              _choiceRow(p, 'हिन्दी', s.newsLanguage == 'hi',
                  () => s.setNewsLanguage('hi'),
                  subtitle: 'Hindi'),
            ])),
            const SizedBox(height: 20),

            // ── Theme ────────────────────────────────────────────────────────
            _sectionLabel(p, tr(lang, 'theme')),
            _card(p, Column(children: [
              _choiceRow(p, tr(lang, 'theme_system'),
                  s.themeMode == ThemeMode.system,
                  () => s.setThemeMode(ThemeMode.system),
                  subtitle: tr(lang, 'theme_auto_sub')),
              Divider(height: 1, color: p.line),
              _choiceRow(p, tr(lang, 'theme_light'),
                  s.themeMode == ThemeMode.light,
                  () => s.setThemeMode(ThemeMode.light)),
              Divider(height: 1, color: p.line),
              _choiceRow(p, tr(lang, 'theme_dark'), s.themeMode == ThemeMode.dark,
                  () => s.setThemeMode(ThemeMode.dark)),
            ])),
            const SizedBox(height: 20),

            // ── Playback ─────────────────────────────────────────────────────
            _sectionLabel(p, tr(lang, 'playback')),
            _card(p, Column(children: [
              for (final sp in const [0.75, 1.0, 1.25, 1.5, 2.0])
                Column(children: [
                  if (sp != 0.75) Divider(height: 1, color: p.line),
                  _choiceRow(p, '${sp}×', s.playbackSpeed == sp,
                      () => s.setPlaybackSpeed(sp)),
                ]),
            ])),
            const SizedBox(height: 20),

            // ── Gemini API key (BYOK) ───────────────────────────────────────
            _sectionLabel(p, 'Gemini API key'),
            _card(p, Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Narrating an article — Live or Paper — runs on your own "
                  "free Gemini key, saved to your account so you won't need "
                  "to re-enter it on other signed-in devices.",
                  style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.4),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _geminiCtrl,
                  obscureText: _geminiHidden,
                  style: TextStyle(color: p.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Paste your Gemini API key',
                    hintStyle: TextStyle(color: p.muted, fontSize: 13),
                    filled: true,
                    fillColor: p.chip,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Gati.rCard),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _geminiHidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                          color: p.muted),
                      onPressed: () =>
                          setState(() => _geminiHidden = !_geminiHidden),
                    ),
                  ),
                ),
                if (_geminiError != null) ...[
                  const SizedBox(height: 8),
                  Text(_geminiError!,
                      style: TextStyle(fontSize: 12.5, color: Gati.kumkuma)),
                ],
                const SizedBox(height: 10),
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
                      onPressed: _validating ? null : _clearGeminiKey,
                      child: Text('Clear',
                          style: TextStyle(color: Gati.kumkuma)),
                    ),
                  const SizedBox(width: 4),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: kAccent, foregroundColor: kPaper),
                    onPressed: _validating ? null : _saveGeminiKey,
                    child: _validating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: kPaper))
                        : const Text('Save'),
                  ),
                ]),
              ],
            ))),
            const SizedBox(height: 24),

            // ── About ────────────────────────────────────────────────────────
            Center(
              child: Column(children: [
                GatiWordmark(size: 18, color: p.ink, lang: lang, animated: false),
                const SizedBox(height: 2),
                Text(tr(lang, 'about_tagline'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: p.muted)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(GatiPalette p, String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: p.muted,
                letterSpacing: 0.3)),
      );

  Widget _card(GatiPalette p, Widget child) => Container(
        decoration: BoxDecoration(
            color: p.surface,
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: Material(color: Colors.transparent, child: child),
      );

  Widget _choiceRow(GatiPalette p, String label, bool selected,
          VoidCallback onTap,
          {String? subtitle}) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 14.5, color: p.ink)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle,
                          style: TextStyle(fontSize: 12, color: p.muted)),
                    ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded, color: kAccent, size: 20),
          ]),
        ),
      );
}
