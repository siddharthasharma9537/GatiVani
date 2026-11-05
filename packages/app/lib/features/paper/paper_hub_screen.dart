import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/papers.dart';
import '../../design/components/gati_masthead.dart';
import '../../design/tokens.dart';
import '../../l10n/strings.dart';
import '../../services/settings_provider.dart';

/// Paper tab: five text-only paper tiles plus a "My uploads" entry.
/// No logos, mastheads or paper imagery, and nothing is fetched from any
/// paper (see [Paper.licensed]).
class PaperHubScreen extends StatelessWidget {
  const PaperHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().lang;
    final p = GatiPalette.of(context);
    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        child: Column(children: [
          GatiMasthead(lang: lang),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  children: [
                    Text(tr(lang, 'paper_choose'),
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: p.ink)),
                    const SizedBox(height: Gati.s3),
                    LayoutBuilder(builder: (context, c) {
                      final cols = c.maxWidth >= 560 ? 3 : 2;
                      const gap = Gati.s3;
                      final w = (c.maxWidth - gap * (cols - 1)) / cols;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final paper in kPapers)
                            SizedBox(
                              width: w,
                              child: _PaperTile(
                                  name: paper.name(lang),
                                  onTap: () =>
                                      context.push('/paper/${paper.id}')),
                            ),
                        ],
                      );
                    }),
                    const SizedBox(height: Gati.s5),
                    _MyUploadsRow(lang: lang),
                    if (lang == 'te') ...[
                      const SizedBox(height: Gati.s4),
                      const ReviewNote(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PaperTile extends StatelessWidget {
  const _PaperTile({required this.name, required this.onTap});
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    return Semantics(
      button: true,
      label: name,
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(Gati.rCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(Gati.rCard),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 88),
            padding: const EdgeInsets.all(Gati.s4),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Gati.rCard),
              border: Border.all(color: p.line),
            ),
            child: Text(name,
                style: TextStyle(
                    fontSize: 17,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: p.ink)),
          ),
        ),
      ),
    );
  }
}

class _MyUploadsRow extends StatelessWidget {
  const _MyUploadsRow({required this.lang});
  final String lang;

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Gati.rCard),
        onTap: () => context.push('/paper/uploads'),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
              horizontal: Gati.s4, vertical: Gati.s3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Gati.rCard),
            border: Border.all(color: p.line),
          ),
          child: Row(children: [
            Icon(Icons.upload_file_rounded, color: p.ink),
            const SizedBox(width: Gati.s3),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr(lang, 'paper_my_uploads'),
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: p.ink)),
                    Text(tr(lang, 'paper_my_uploads_sub'),
                        style: TextStyle(fontSize: 12.5, color: p.muted)),
                  ]),
            ),
            Icon(Icons.chevron_right, color: p.muted),
          ]),
        ),
      ),
    );
  }
}

/// Marks the Telugu wording on these screens as an unreviewed AI draft.
/// Remove only after a native reader has signed the text off.
class ReviewNote extends StatelessWidget {
  const ReviewNote({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().lang;
    final p = GatiPalette.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: p.dark ? GatiDark.accentSoft : Gati.accentSoft,
            borderRadius: BorderRadius.circular(Gati.rChip)),
        child: Text(tr(lang, 'paper_being_reviewed'),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: p.dark ? Gati.pasupuGlow : Gati.accentText)),
      ),
    );
  }
}
