import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../services/settings_provider.dart';
import '../tokens.dart';
import 'gati_district_sheet.dart';

/// Filter dropdown for the story lists (Live + Paper) — sits right of the
/// grid-view toggle, inside the same chip. Sort options first, then the
/// filters this app actually has. Vāni drives the same settings when the
/// user asks for location news.
class GatiFilterButton extends StatelessWidget {
  const GatiFilterButton({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    final lang = s.lang;
    final p = GatiPalette.of(context);
    // Non-default state (district-only, or latest-first override) fills the
    // button like a selected view toggle.
    final active = s.districtOnly || s.feedSort != 'location';
    return PopupMenuButton<String>(
      tooltip: tr(lang, 'filter'),
      position: PopupMenuPosition.under,
      color: p.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.line, width: 0.5)),
      onSelected: (v) {
        switch (v) {
          case 'sort_latest':
            s.setFeedSort('latest');
          case 'sort_location':
            if (s.district == null) {
              showGatiDistrictSheet(context);
            }
            s.setFeedSort('location');
          case 'district_only':
            if (s.district == null) {
              showGatiDistrictSheet(context);
            }
            s.setDistrictOnly(!s.districtOnly);
          case 'choose_district':
            showGatiDistrictSheet(context);
        }
      },
      itemBuilder: (_) => [
        _header(p, tr(lang, 'sort')),
        _check(p, 'sort_location', tr(lang, 'sort_location'),
            s.feedSort == 'location'),
        _check(p, 'sort_latest', tr(lang, 'sort_latest'),
            s.feedSort == 'latest'),
        const PopupMenuDivider(),
        _header(p, tr(lang, 'filter')),
        _check(p, 'district_only', tr(lang, 'district_only'), s.districtOnly),
        PopupMenuItem<String>(
          value: 'choose_district',
          height: 40,
          child: Row(children: [
            Icon(Icons.location_on_outlined, size: 18, color: p.muted),
            const SizedBox(width: 10),
            Text(tr(lang, 'choose_district'),
                style: TextStyle(fontSize: 13.5, color: p.ink)),
          ]),
        ),
      ],
      child: Container(
        width: 32,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? kAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(Icons.tune_rounded,
            size: 17, color: active ? kPaper : p.muted),
      ),
    );
  }

  PopupMenuItem<String> _header(GatiPalette p, String text) =>
      PopupMenuItem<String>(
        enabled: false,
        height: 30,
        child: Text(text,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w500, color: p.muted)),
      );

  PopupMenuItem<String> _check(
          GatiPalette p, String value, String label, bool checked) =>
      PopupMenuItem<String>(
        value: value,
        height: 40,
        child: Row(children: [
          Icon(checked ? Icons.check_rounded : null,
              size: 18, color: Gati.accent),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13.5, color: p.ink)),
        ]),
      );
}
