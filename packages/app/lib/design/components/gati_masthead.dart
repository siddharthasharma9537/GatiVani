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
    // A soft tinted band + hairline so the masthead reads as its own layer
    // above the content.
    return Container(
      decoration: BoxDecoration(
        color: p.dark ? GatiDark.band : Gati.band,
        border: Border(bottom: BorderSide(color: p.line, width: 0.5)),
        boxShadow: [
          BoxShadow(
              color: const Color(0x14000000),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(Gati.s5, Gati.s3, Gati.s4, Gati.s3),
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
          // Sized so wordmark + dateline together stay INSIDE the 40px
          // header buttons' vertical extent (≈35px total), nudged a few
          // px down so it sits optically level with the buttons.
          // Tapping the brand goes home (Live) — the universal masthead
          // convention.
          child: GestureDetector(
          onTap: () => context.go('/'),
          behavior: HitTestBehavior.opaque,
          child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GatiWordmark(size: 19, color: p.ink, lang: lang),
              Text(dateline,
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.15,
                      fontWeight: FontWeight.w500,
                      color: p.muted)),
            ],
          ),
          ),
          ),
        ),
        for (final a in actions) ...[const SizedBox(width: Gati.s2), a],
      ]),
    );
  }
}
