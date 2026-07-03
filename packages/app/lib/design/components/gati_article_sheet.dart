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

/// THE article actions sheet — the same options everywhere an article (or
/// episode) appears: Paper cards, Live stories, Shows tiles. Play now ·
/// Summarize · Play next · Add to Up Next · Download · Ask Vāni, plus an
/// optional "read" row when the piece has a readable source (web stories).
void showGatiArticleSheet(
  BuildContext context,
  NewspaperArticle a, {
  VoidCallback? onRead,
  VoidCallback? onPlayed,
}) {
  final lang = context.read<SettingsProvider>().lang;
  final p = GatiPalette.of(context);
  final hasText = a.content.trim().isNotEmpty;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: p.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      Widget item(IconData icon, String label, VoidCallback onTap) => ListTile(
            leading: Icon(icon, color: p.ink, size: 22),
            title: Text(label, style: TextStyle(color: p.ink, fontSize: 15)),
            onTap: () {
              Navigator.pop(ctx);
              onTap();
            },
          );
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(a.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
            ),
          ),
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
            item(Icons.graphic_eq, tr(lang, 'ask_vani'),
                () => AssistantSheet.open(context, a.id, a.title,
                    articleText: a.content)),
          const SizedBox(height: 8),
        ]),
      );
    },
  );
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
