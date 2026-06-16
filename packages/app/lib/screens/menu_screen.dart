import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/tokens.dart';
import '../l10n/strings.dart';
import '../services/settings_provider.dart';
import 'auth_screen.dart';

/// The menu / account hub: account (guest + sign in / sign up scaffolding),
/// language, theme, playback and about. Reachable from the home header.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    final lang = s.lang;
    return Scaffold(
      backgroundColor: kPaper,
      appBar: AppBar(
        backgroundColor: kPaper,
        surfaceTintColor: kPaper,
        elevation: 0,
        foregroundColor: kInk,
        title: Text(tr(lang, 'menu'),
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w500, color: kInk)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // ── Account (guest) ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: kInk, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                          color: Color(0xFF43221A), shape: BoxShape.circle),
                      child: const Icon(Icons.person_outline,
                          color: Color(0xFFF0997B), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr(lang, 'guest'),
                            style: const TextStyle(
                                color: kPaper,
                                fontSize: 16,
                                fontWeight: FontWeight.w500)),
                        Text(tr(lang, 'guest_sub'),
                            style: const TextStyle(
                                color: Color(0xFFB4B2A9), fontSize: 12.5)),
                      ],
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: kAccent,
                            foregroundColor: kPaper,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        onPressed: () => _openAuth(context, signUp: false),
                        child: Text(tr(lang, 'sign_in'),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: kPaper,
                            side: const BorderSide(color: Color(0xFF4A4A47)),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        onPressed: () => _openAuth(context, signUp: true),
                        child: Text(tr(lang, 'sign_up'),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Language ─────────────────────────────────────────────────────
            _sectionLabel(tr(lang, 'language')),
            _card(Column(children: [
              _choiceRow('English', s.lang == 'en',
                  () => s.setLanguage('en')),
              const Divider(height: 1, color: Color(0xFFEDEAE1)),
              _choiceRow('తెలుగు', s.lang == 'te',
                  () => s.setLanguage('te')),
            ])),
            const SizedBox(height: 20),

            // ── Theme ────────────────────────────────────────────────────────
            _sectionLabel(tr(lang, 'theme')),
            _card(Column(children: [
              _choiceRow(tr(lang, 'theme_system'),
                  s.themeMode == ThemeMode.system,
                  () => s.setThemeMode(ThemeMode.system)),
              const Divider(height: 1, color: Color(0xFFEDEAE1)),
              _choiceRow(tr(lang, 'theme_light'),
                  s.themeMode == ThemeMode.light,
                  () => s.setThemeMode(ThemeMode.light)),
              const Divider(height: 1, color: Color(0xFFEDEAE1)),
              _choiceRow(tr(lang, 'theme_dark'),
                  s.themeMode == ThemeMode.dark,
                  () => s.setThemeMode(ThemeMode.dark)),
            ])),
            const SizedBox(height: 20),

            // ── Playback ─────────────────────────────────────────────────────
            _sectionLabel(tr(lang, 'playback')),
            _card(Column(children: [
              for (final sp in const [0.75, 1.0, 1.25, 1.5, 2.0])
                Column(children: [
                  if (sp != 0.75)
                    const Divider(height: 1, color: Color(0xFFEDEAE1)),
                  _choiceRow('${sp}×', s.playbackSpeed == sp,
                      () => s.setPlaybackSpeed(sp)),
                ]),
            ])),
            const SizedBox(height: 24),

            // ── About ────────────────────────────────────────────────────────
            Center(
              child: Column(children: [
                const Text('Gativani',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: kInk)),
                const SizedBox(height: 2),
                Text(tr(lang, 'about_tagline'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: kMuted)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  void _openAuth(BuildContext context, {required bool signUp}) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => AuthScreen(signUp: signUp)));
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: kMuted,
                letterSpacing: 0.3)),
      );

  Widget _card(Widget child) => Container(
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE7E4DB)),
            borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        // Material ancestor so the InkWell rows reliably handle taps + splash.
        child: Material(color: Colors.transparent, child: child),
      );

  Widget _choiceRow(String label, bool selected, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 14.5, color: kInk))),
            if (selected)
              const Icon(Icons.check_rounded, color: kAccent, size: 20),
          ]),
        ),
      );
}
