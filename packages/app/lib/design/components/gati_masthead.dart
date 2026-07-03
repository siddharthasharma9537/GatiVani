import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../config/districts.dart';
import '../../l10n/strings.dart';
import '../../services/settings_provider.dart';
import '../../widgets/gati_shell.dart';
import '../tokens.dart';
import 'gati_wordmark.dart';

/// Standard header icon button (menu, search, …) — one size everywhere.
class GatiHeaderButton extends StatelessWidget {
  const GatiHeaderButton({super.key, required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: p.chip, borderRadius: BorderRadius.circular(Gati.rChip)),
        child: Icon(icon, size: 20, color: p.ink),
      ),
    );
  }
}

/// The one app masthead (§10): menu button (opens the shell drawer),
/// wordmark + today's dateline, screen-specific actions on the right.
/// Every tab mounts this, so switching tabs reads as one app — same
/// brand row, same sizes, same paddings — with only the content below
/// changing.
class GatiMasthead extends StatelessWidget {
  const GatiMasthead({super.key, required this.lang, this.actions = const []});

  final String lang;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final now = DateTime.now();
    // The chosen district joins the dateline, so the location preference is
    // visible without its own chip taking header space.
    final district =
        districtByEn(context.watch<SettingsProvider>().district);
    final dateline = [
      '${weekdayShort(now, lang)} · ${formatEditionDate(now, lang)}',
      if (district != null) lang == 'te' ? district.te : district.en,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gati.s5, Gati.s3, Gati.s4, Gati.s2),
      child: Row(children: [
        GatiHeaderButton(
          icon: Icons.menu,
          onTap: () {
            final scope = GatiShellScope.maybeOf(context);
            if (scope != null) {
              scope.openMenu();
            } else {
              context.push('/menu');
            }
          },
        ),
        const SizedBox(width: Gati.s3),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GatiWordmark(size: 22, color: p.ink, lang: lang),
              Text(dateline,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: p.muted)),
            ],
          ),
        ),
        for (final a in actions) ...[const SizedBox(width: Gati.s2), a],
      ]),
    );
  }
}
