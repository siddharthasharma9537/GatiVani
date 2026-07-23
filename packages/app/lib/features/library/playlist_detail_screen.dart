import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../design/components/add_to_playlist_sheet.dart';
import '../../design/components/gati_states.dart';
import '../../design/tokens.dart';
import '../../l10n/strings.dart';
import '../../models/newspaper_article.dart';
import '../../services/news_feed_service.dart' show ReaderStore, WebArticle;
import '../../services/playback_service.dart';
import '../../services/playlists_store.dart';
import '../../services/settings_provider.dart';
import '../../widgets/gati_puck.dart';

/// One playlist: reorder by dragging, remove a story, "Play all" starts it
/// from the top. Tapping a row opens the full story (same reader as
/// everywhere else in the app); the ▶ plays it in the mini-player.
class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});
  final String playlistId;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  @override
  void initState() {
    super.initState();
    PlaylistsStore.i.ensureLoaded();
  }

  Future<void> _rename(String lang) async {
    final pl = PlaylistsStore.i.byId(widget.playlistId);
    if (pl == null) return;
    final name = await promptPlaylistName(context, lang,
        initial: pl.name,
        titleKey: 'rename_playlist',
        actionKey: 'rename_playlist');
    if (name == null || name.trim().isEmpty) return;
    await PlaylistsStore.i.rename(widget.playlistId, name);
  }

  Future<void> _delete(String lang) async {
    final p = GatiPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.paper,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr(lang, 'delete_playlist'),
            style: TextStyle(color: p.ink, fontSize: 16)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(lang, 'cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(lang, 'delete_playlist'))),
        ],
      ),
    );
    if (confirmed == true) {
      await PlaylistsStore.i.delete(widget.playlistId);
      if (mounted) context.pop();
    }
  }

  // Tap opens the article TEXT (same reader as everywhere else); the ▶
  // starts playback in the mini-player instead.
  void _openArticle(NewspaperArticle a) {
    final lang = context.read<SettingsProvider>().lang;
    ReaderStore.i.current = WebArticle(
      id: a.id,
      title: a.title,
      link: '',
      source: sectionLabel(a.category, lang),
      pubDate: '',
      summary: a.preview,
      body: a.content,
    );
    context.push('/reader');
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
          child: ListenableBuilder(
            listenable: PlaylistsStore.i,
            builder: (context, _) {
              final pl = PlaylistsStore.i.byId(widget.playlistId);
              if (pl == null) {
                // Deleted from elsewhere (e.g. another tab) — bounce back.
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => context.pop());
                return const SizedBox.shrink();
              }
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Gati.s3, Gati.s2, Gati.s5, Gati.s2),
                  child: Row(children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: p.ink),
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Text(pl.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              color: p.ink)),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: p.ink),
                      color: p.surface,
                      onSelected: (v) {
                        if (v == 'rename') _rename(lang);
                        if (v == 'delete') _delete(lang);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                            value: 'rename',
                            child: Text(tr(lang, 'rename_playlist'))),
                        PopupMenuItem(
                            value: 'delete',
                            child: Text(tr(lang, 'delete_playlist'))),
                      ],
                    ),
                  ]),
                ),
                if (pl.articles.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Gati.s5, 0, Gati.s5, Gati.s3),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: Gati.accent,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        onPressed: () =>
                            PlaybackService.i.playAll(pl.articles),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: Text(tr(lang, 'play_all')),
                      ),
                    ),
                  ),
                Expanded(
                  child: pl.articles.isEmpty
                      ? GatiEmpty(
                          message: tr(lang, 'playlist_empty'), onInk: false)
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                              Gati.s5, 0, Gati.s5, Gati.s6),
                          itemCount: pl.articles.length,
                          onReorder: (oldIndex, newIndex) =>
                              PlaylistsStore.i.reorder(
                                  widget.playlistId, oldIndex, newIndex),
                          itemBuilder: (_, i) =>
                              _row(p, lang, pl.articles[i], i, key: ValueKey(pl.articles[i].id)),
                        ),
                ),
              ]);
            },
          ),
        ),
        const GatiPuck(),
      ]),
    );
  }

  Widget _row(GatiPalette p, String lang, NewspaperArticle a, int index,
      {required Key key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: Gati.s2),
      child: Row(children: [
        Expanded(
          child: InkWell(
            onTap: () => _openArticle(a),
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
                    '${sectionLabel(a.category, lang)} · '
                    '${(a.estimatedDurationSeconds / 60).ceil()} ${tr(lang, 'min')}',
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Gati.accent)),
              ],
            ),
          ),
        ),
        const SizedBox(width: Gati.s2),
        IconButton(
          icon: const Icon(Icons.play_arrow_rounded,
              color: Gati.accent, size: 22),
          tooltip: tr(lang, 'play_all'),
          onPressed: () {
            final pl = PlaylistsStore.i.byId(widget.playlistId);
            if (pl != null) {
              PlaybackService.i.playAll(pl.articles, start: index);
            }
          },
        ),
        IconButton(
          icon: Icon(Icons.remove_circle_outline, color: p.muted, size: 20),
          tooltip: tr(lang, 'remove_from_playlist'),
          onPressed: () =>
              PlaylistsStore.i.removeArticle(widget.playlistId, a.id),
        ),
        Icon(Icons.drag_handle_rounded, color: p.line, size: 20),
      ]),
    );
  }
}
