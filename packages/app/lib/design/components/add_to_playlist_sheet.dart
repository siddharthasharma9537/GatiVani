import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../models/newspaper_article.dart';
import '../../services/playlists_store.dart';
import '../../services/settings_provider.dart';
import '../tokens.dart';
import 'gati_states.dart';

/// "Add to Playlist" — lists existing playlists (checkmark if [article] is
/// already in one) plus a "New playlist" row that prompts for a name and
/// adds the article to it immediately. Opened from the player's Save pill
/// and from the shared article actions menu.
void showAddToPlaylistSheet(BuildContext context, NewspaperArticle article) {
  final p = GatiPalette.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.paper,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _AddToPlaylistSheet(article: article),
  );
}

class _AddToPlaylistSheet extends StatefulWidget {
  const _AddToPlaylistSheet({required this.article});
  final NewspaperArticle article;

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  @override
  void initState() {
    super.initState();
    PlaylistsStore.i.ensureLoaded();
  }

  Future<void> _createAndAdd(String lang) async {
    final name = await promptPlaylistName(context, lang, initial: '');
    if (name == null || name.trim().isEmpty) return;
    final playlist = await PlaylistsStore.i.create(name);
    await PlaylistsStore.i.addArticle(playlist.id, widget.article);
    if (mounted) {
      Navigator.pop(context);
      gatiSnack(context, tr(lang, 'added_to_playlist'));
    }
  }

  Future<void> _toggle(String playlistId, bool alreadyIn, String lang) async {
    if (alreadyIn) {
      await PlaylistsStore.i.removeArticle(playlistId, widget.article.id);
    } else {
      await PlaylistsStore.i.addArticle(playlistId, widget.article);
      if (mounted) gatiSnack(context, tr(lang, 'added_to_playlist'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final lang = context.watch<SettingsProvider>().lang;
    return SafeArea(
      child: ListenableBuilder(
        listenable: PlaylistsStore.i,
        builder: (context, _) {
          final playlists = PlaylistsStore.i.all;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: p.line, borderRadius: BorderRadius.circular(2))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(children: [
                Expanded(
                  child: Text(tr(lang, 'add_to_playlist'),
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: p.ink)),
                ),
              ]),
            ),
            InkWell(
              onTap: () => _createAndAdd(lang),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(children: [
                  Icon(Icons.add_circle_outline, color: Gati.accent, size: 22),
                  const SizedBox(width: 12),
                  Text(tr(lang, 'new_playlist'),
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: Gati.accent)),
                ]),
              ),
            ),
            if (playlists.isNotEmpty) Divider(height: 1, color: p.line),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: playlists.length,
                itemBuilder: (_, i) {
                  final pl = playlists[i];
                  final has = pl.contains(widget.article.id);
                  return InkWell(
                    onTap: () => _toggle(pl.id, has, lang),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Row(children: [
                        Icon(Icons.queue_music_rounded,
                            color: p.muted, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(pl.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 14.5, color: p.ink)),
                              Text(
                                  storyCount(pl.articles.length, lang),
                                  style: TextStyle(
                                      fontSize: 12, color: p.muted)),
                            ],
                          ),
                        ),
                        if (has)
                          Icon(Icons.check_circle_rounded,
                              color: Gati.accent, size: 20)
                        else
                          Icon(Icons.circle_outlined,
                              color: p.line, size: 20),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// Shared name-entry dialog for both creating a new playlist and renaming
/// an existing one (different [titleKey]/[actionKey] strings, same shape).
///
/// The typed value is tracked live via onChanged into [value] rather than
/// read from controller.text at button-press — on Flutter web the committed
/// text isn't always synced back to the controller by the time the action
/// button's onPressed runs, which silently returned an empty name.
///
/// barrierDismissible is false: the Cancel/Create row sits close to the
/// dialog's edge, and a tap that grazes just outside it would otherwise
/// silently pop with null — closing the dialog and discarding the typed
/// name with no error and no feedback (reported as "Create does nothing").
Future<String?> promptPlaylistName(
  BuildContext context,
  String lang, {
  required String initial,
  String titleKey = 'new_playlist',
  String actionKey = 'create',
}) async {
  final p = GatiPalette.of(context);
  final controller = TextEditingController(text: initial);
  var value = initial;
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.paper,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(tr(lang, titleKey),
          style: TextStyle(color: p.ink, fontSize: 16)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: TextStyle(color: p.ink),
        decoration: InputDecoration(hintText: tr(lang, 'playlist_name_hint')),
        onChanged: (v) => value = v,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr(lang, 'cancel')),
        ),
        TextButton(
          style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
          onPressed: () => Navigator.pop(
              ctx, controller.text.isNotEmpty ? controller.text : value),
          child: Text(tr(lang, actionKey)),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
