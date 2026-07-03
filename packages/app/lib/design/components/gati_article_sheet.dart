import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../models/newspaper_article.dart';
import '../../services/document_service.dart';
import '../../services/playback_service.dart';
import '../../services/settings_provider.dart';
import '../../widgets/assistant_sheet.dart';
import '../tokens.dart';
import 'gati_states.dart';

/// THE article actions menu — the same options everywhere an article (or
/// episode) appears: Paper cards, Live stories, Shows tiles. A compact
/// popup anchored at [globalPos] (the ⋯ button / long-press point), not a
/// full-width sheet. Play now · Summarize · Play next · Add to Up Next ·
/// Download · Read · Ask Vāni.
void showGatiArticleMenu(
  BuildContext context,
  Offset globalPos,
  NewspaperArticle a, {
  VoidCallback? onRead,
  VoidCallback? onPlayed,
}) {
  final lang = context.read<SettingsProvider>().lang;
  final p = GatiPalette.of(context);
  final hasText = a.content.trim().isNotEmpty;
  final overlay =
      Overlay.of(context).context.findRenderObject()! as RenderBox;

  PopupMenuItem<VoidCallback> item(
          IconData icon, String label, VoidCallback onTap) =>
      PopupMenuItem<VoidCallback>(
        value: onTap,
        height: 38,
        child: Row(children: [
          Icon(icon, color: p.muted, size: 18),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: p.ink, fontSize: 13.5)),
        ]),
      );

  showMenu<VoidCallback>(
    context: context,
    position: RelativeRect.fromRect(
        globalPos & const Size(1, 1), Offset.zero & overlay.size),
    color: p.surface,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.line, width: 0.5)),
    constraints: const BoxConstraints(minWidth: 200, maxWidth: 240),
    items: [
      item(Icons.play_arrow_rounded, tr(lang, 'play_now'), () {
        PlaybackService.i.playOne(a);
        onPlayed?.call();
      }),
      if (hasText)
        item(Icons.auto_awesome, tr(lang, 'summarize'),
            () => _summarize(context, a, lang)),
      item(Icons.queue_play_next_rounded, tr(lang, 'play_next'), () {
        PlaybackService.i.playNext([a]);
        gatiSnack(context, tr(lang, 'added_play_next'));
      }),
      item(Icons.playlist_add_rounded, tr(lang, 'add_to_queue'), () {
        PlaybackService.i.addToQueue([a]);
        gatiSnack(context, tr(lang, 'added_queue'));
      }),
      item(Icons.download_rounded, tr(lang, 'download'),
          () => _download(context, a, lang)),
      if (onRead != null)
        item(Icons.chrome_reader_mode_outlined, tr(lang, 'read_story'),
            onRead),
      if (hasText)
        item(
            Icons.graphic_eq,
            tr(lang, 'ask_vani'),
            () => AssistantSheet.open(context, a.id, a.title,
                articleText: a.content)),
    ],
  ).then((action) => action?.call());
}

// Summarize = an AI gist (a few sentences) narrated in the mini-player,
// grounded on the article (DB edition when it exists, the raw text otherwise).
Future<void> _summarize(
    BuildContext context, NewspaperArticle a, String lang) async {
  gatiSnack(context, tr(lang, 'summarizing'));
  try {
    final summary = await DocumentService().ask(
      a.id,
      'ఈ వ్యాసాన్ని తెలుగులో 3-4 చిన్న వాక్యాల్లో సంక్షిప్త సారాంశంగా చెప్పు. '
      'ఉపోద్ఘాతం, అదనపు వ్యాఖ్యలు వద్దు — కేవలం సారాంశం మాత్రమే.',
      articleText: a.content,
      articleTitle: a.title,
    );
    if (summary.trim().isEmpty) {
      if (context.mounted) gatiSnack(context, tr(lang, 'summary_failed'));
      return;
    }
    await PlaybackService.i.playSummary(a, summary);
  } catch (_) {
    if (context.mounted) gatiSnack(context, tr(lang, 'summary_failed'));
  }
}

// Download = pre-generate the full audio so it's cached and instant later.
Future<void> _download(
    BuildContext context, NewspaperArticle a, String lang) async {
  gatiSnack(context, tr(lang, 'downloading'));
  final ok = await PlaybackService.i.preload(a);
  if (context.mounted) {
    gatiSnack(context, tr(lang, ok ? 'downloaded' : 'download_failed'));
  }
}
