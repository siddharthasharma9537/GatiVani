import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/tokens.dart';
import '../l10n/strings.dart';
import '../services/edition_meta.dart';
import '../services/settings_provider.dart';

/// The hero edition card, reinvented as a newspaper masthead. Instead of
/// echoing the raw filename, it parses publication / edition / date out of the
/// title and lays them out like a front-page nameplate. Falls back to a
/// junk-stripped title when nothing parses. All chrome respects the UI language.
class EditionMasthead extends StatelessWidget {
  const EditionMasthead({
    super.key,
    required this.rawTitle,
    required this.articleCount,
    required this.pageCount,
    required this.onListen,
    this.contentLang = 'te',
    this.fallbackDate,
  });

  final String rawTitle;
  final int articleCount;
  final int pageCount;
  final VoidCallback onListen;
  final String contentLang;
  final DateTime? fallbackDate;

  static const _ink = Color(0xFF2C2C2A);
  static const _light = Color(0xFFF7F2EA);
  static const _dim = Color(0xFF9A958A);
  static const _kicker = Color(0xFFE08A63);

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().lang;
    final meta = EditionMeta.parse(rawTitle);
    final date = meta.date ?? fallbackDate;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration:
          BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kicker: weekday · date · today's edition
          Row(children: [
            if (date != null) ...[
              Text(
                  '${weekdayShort(date, lang)} · ${formatEditionDate(date, lang)}',
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.4,
                      color: _kicker)),
              const SizedBox(width: 8),
              Container(
                  width: 4, height: 4,
                  decoration: const BoxDecoration(
                      color: Color(0xFF5F5E5A), shape: BoxShape.circle)),
              const SizedBox(width: 8),
            ],
            Text(tr(lang, 'todays_edition'),
                style: const TextStyle(fontSize: 11.5, color: Color(0xFFB4B2A9))),
          ]),
          const SizedBox(height: 12),

          // Masthead (or clean-title fallback)
          if (meta.hasMasthead) ...[
            Text(meta.publication(lang),
                style: const TextStyle(
                    fontFamily: 'serif',
                    fontSize: 29,
                    fontWeight: FontWeight.w600,
                    height: 1.05,
                    color: _light)),
            if (meta.edition(lang) != null) ...[
              const SizedBox(height: 7),
              Row(children: [
                if (lang == 'en' && meta.publicationTe != null) ...[
                  Text(meta.publicationTe!,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFFE7E2D8))),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: GatiDark.accentSoft,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(meta.edition(lang)!,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Gati.pasupuGlow)),
                ),
              ]),
            ],
          ] else
            Text(meta.cleanTitle,
                style: const TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w600, color: _light)),

          const SizedBox(height: 16),

          // Stats
          Row(children: [
            _stat('$articleCount', tr(lang, 'articles')),
            if (pageCount > 0) ...[
              const SizedBox(width: 18),
              _stat('$pageCount', tr(lang, 'pages')),
            ],
            const SizedBox(width: 18),
            _stat(contentLang == 'te' ? 'తెలుగు' : 'English',
                tr(lang, 'language')),
          ]),
          const SizedBox(height: 16),

          // Listen
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: kAccent,
                foregroundColor: kPaper,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22))),
            onPressed: articleCount == 0 ? null : onListen,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: Text(tr(lang, 'listen_briefing')),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w500, color: _light)),
          Text(label, style: const TextStyle(fontSize: 11, color: _dim)),
        ],
      );
}
