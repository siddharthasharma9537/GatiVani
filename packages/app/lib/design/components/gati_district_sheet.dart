import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/districts.dart';
import '../../l10n/strings.dart';
import '../../services/settings_provider.dart';
import '../tokens.dart';

/// Searchable district picker (the header's location option). Selecting a
/// district biases Live stories and surfaces district news from the printed
/// edition; the preference persists in settings.
void showGatiDistrictSheet(BuildContext context) {
  final p = GatiPalette.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.paper,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _DistrictSheet(),
  );
}

class _DistrictSheet extends StatefulWidget {
  const _DistrictSheet();

  @override
  State<_DistrictSheet> createState() => _DistrictSheetState();
}

class _DistrictSheetState extends State<_DistrictSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final s = context.watch<SettingsProvider>();
    final lang = s.lang;
    final q = _query.trim().toLowerCase();
    final matches = q.isEmpty
        ? kDistricts
        : kDistricts
            .where((d) =>
                d.en.toLowerCase().contains(q) ||
                d.te.contains(_query.trim()) ||
                d.state.toLowerCase().contains(q))
            .toList();
    // Group by state, preserving data order.
    final states = <String>[];
    for (final d in matches) {
      if (!states.contains(d.state)) states.add(d.state);
    }
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.78,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 10),
        Center(
          child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: p.line, borderRadius: BorderRadius.circular(2))),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Text(tr(lang, 'choose_district'),
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w500, color: p.ink)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: tr(lang, 'search_district'),
              prefixIcon: Icon(Icons.search, size: 20, color: p.muted),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              ListTile(
                leading: Icon(Icons.public, size: 20, color: p.muted),
                title: Text(tr(lang, 'no_district'),
                    style: TextStyle(fontSize: 14.5, color: p.ink)),
                trailing: s.district == null
                    ? const Icon(Icons.check_rounded,
                        color: Gati.accent, size: 20)
                    : null,
                onTap: () {
                  s.setDistrict(null);
                  Navigator.pop(context);
                },
              ),
              for (final state in states) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Text(state,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: p.muted)),
                ),
                for (final d in matches.where((d) => d.state == state))
                  ListTile(
                    dense: true,
                    title: Text(lang == 'te' ? d.te : d.en,
                        style: TextStyle(fontSize: 14.5, color: p.ink)),
                    subtitle: Text(lang == 'te' ? d.en : d.te,
                        style: TextStyle(fontSize: 11.5, color: p.muted)),
                    trailing: s.district == d.en
                        ? const Icon(Icons.check_rounded,
                            color: Gati.accent, size: 20)
                        : null,
                    onTap: () {
                      s.setDistrict(d.en);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}
