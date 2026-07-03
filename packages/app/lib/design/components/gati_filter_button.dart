import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../services/settings_provider.dart';
import '../tokens.dart';
import 'gati_district_sheet.dart';

/// Filter dropdown for the story lists — sits right of the grid-view
/// toggle, inside the same chip. Sort options first, then the filters this
/// app actually has. Paper additionally folds its Sections and Pages
/// chips in here via [sections]/[pages]. Vāni drives the same settings
/// when the user asks for location news.
class GatiFilterButton extends StatelessWidget {
  const GatiFilterButton({
    super.key,
    this.sections = const [],
    this.selectedSection,
    this.onSection,
    this.pages = const [],
    this.selectedPage,
    this.onPage,
    this.sectionLabelOf,
  });

  /// Edition sections (Paper only).
  final List<String> sections;
  final String? selectedSection;
  final ValueChanged<String?>? onSection;

  /// Edition page numbers (Paper only).
  final List<int> pages;
  final int? selectedPage;
  final ValueChanged<int?>? onPage;

  /// Localizes a section name for display.
  final String Function(String section)? sectionLabelOf;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    final lang = s.lang;
    final p = GatiPalette.of(context);
    // Non-default state fills the button like a selected view toggle.
    final active = s.districtOnly ||
        s.feedSort != 'location' ||
        selectedSection != null ||
        selectedPage != null;
    return PopupMenuButton<String>(
      tooltip: tr(lang, 'filter'),
      position: PopupMenuPosition.under,
      color: p.surface,
      constraints: const BoxConstraints(maxWidth: 250, maxHeight: 440),
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
          case 'sec_all':
            onSection?.call(null);
          case 'page_all':
            onPage?.call(null);
          default:
            if (v.startsWith('sec:')) onSection?.call(v.substring(4));
            if (v.startsWith('page:')) {
              onPage?.call(int.tryParse(v.substring(5)));
            }
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
          height: 38,
          child: Row(children: [
            Icon(Icons.location_on_outlined, size: 18, color: p.muted),
            const SizedBox(width: 10),
            Text(tr(lang, 'choose_district'),
                style: TextStyle(fontSize: 13.5, color: p.ink)),
          ]),
        ),
        if (sections.isNotEmpty) ...[
          const PopupMenuDivider(),
          _header(p, tr(lang, 'sections')),
          _check(p, 'sec_all', tr(lang, 'all'), selectedSection == null),
          for (final sec in sections)
            _check(p, 'sec:$sec', sectionLabelOf?.call(sec) ?? sec,
                selectedSection == sec),
        ],
        if (pages.isNotEmpty) ...[
          const PopupMenuDivider(),
          _header(p, tr(lang, 'pages')),
          _check(p, 'page_all', tr(lang, 'all'), selectedPage == null),
          for (final pg in pages)
            _check(p, 'page:$pg', 'p$pg', selectedPage == pg),
        ],
      ],
      child: Container(
        width: 32,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? kAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(Icons.filter_alt_outlined,
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
        height: 38,
        child: Row(children: [
          Icon(checked ? Icons.check_rounded : null,
              size: 18, color: Gati.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: p.ink)),
          ),
        ]),
      );
}
