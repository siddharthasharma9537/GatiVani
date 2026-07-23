import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../design/components/gati_states.dart';
import '../../design/tokens.dart';
import '../../l10n/strings.dart';
import '../../services/downloads_store.dart';
import '../../services/playback_service.dart';
import '../../services/settings_provider.dart';
import '../../widgets/gati_puck.dart';

/// Menu → Downloads: everything saved via ⋯ → Download, newest first.
/// Tap plays (from the local file when it exists); the trash removes the
/// record and its audio.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  @override
  void initState() {
    super.initState();
    DownloadsStore.i.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final lang = context.watch<SettingsProvider>().lang;
    return Scaffold(
      backgroundColor: p.paper,
      body: Stack(children: [
        SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Gati.s3, Gati.s2, Gati.s5, Gati.s2),
              child: Row(children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: p.ink),
                  onPressed: () => context.pop(),
                ),
                Text(tr(lang, 'downloads'),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: p.ink)),
              ]),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: DownloadsStore.i,
                builder: (context, _) {
                  final items = DownloadsStore.i.items;
                  if (items.isEmpty) {
                    return GatiEmpty(
                        message: tr(lang, 'downloads_empty'), onInk: false);
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        Gati.s5, Gati.s2, Gati.s5, Gati.s6),
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: p.line),
                    itemBuilder: (_, i) => _row(p, lang, items[i]),
                  );
                },
              ),
            ),
          ]),
        ),
        const GatiPuck(),
      ]),
    );
  }

  Widget _row(GatiPalette p, String lang, DownloadRecord r) {
    final a = r.article;
    return InkWell(
      onTap: () => PlaybackService.i.playOne(a),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gati.s3),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14.5, height: 1.35, color: p.ink)),
                const SizedBox(height: 4),
                Text(
                    '${sectionLabel(a.category, lang)}'
                    ' · ${formatEditionDate(r.savedAt, lang)}'
                    '${r.offline ? ' · ${tr(lang, 'offline')}' : ''}',
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Gati.accent)),
              ],
            ),
          ),
          const SizedBox(width: Gati.s3),
          const Icon(Icons.play_arrow_rounded, color: Gati.accent, size: 22),
          IconButton(
            icon: Icon(Icons.delete_outline, color: p.muted, size: 20),
            tooltip: tr(lang, 'remove_download'),
            onPressed: () async {
              await DownloadsStore.i.remove(a.id);
              if (mounted) gatiSnack(context, tr(lang, 'download_removed'));
            },
          ),
        ]),
      ),
    );
  }
}
