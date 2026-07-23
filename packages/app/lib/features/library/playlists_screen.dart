import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../design/components/add_to_playlist_sheet.dart';
import '../../design/components/gati_states.dart';
import '../../design/tokens.dart';
import '../../l10n/strings.dart';
import '../../models/playlist.dart';
import '../../services/playlists_store.dart';
import '../../services/settings_provider.dart';
import '../../widgets/gati_puck.dart';

/// Menu → Playlists: named collections the user built via Save/Add to
/// Playlist. Tap opens the playlist; the + creates a new (empty) one.
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  @override
  void initState() {
    super.initState();
    PlaylistsStore.i.ensureLoaded();
  }

  Future<void> _createPlaylist(String lang) async {
    final name = await promptPlaylistName(context, lang, initial: '');
    if (name == null || name.trim().isEmpty) return;
    final playlist = await PlaylistsStore.i.create(name);
    if (mounted) context.push('/playlists/${playlist.id}');
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
                Expanded(
                  child: Text(tr(lang, 'playlists'),
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          color: p.ink)),
                ),
                IconButton(
                  icon: Icon(Icons.add_rounded, color: p.ink),
                  tooltip: tr(lang, 'new_playlist'),
                  onPressed: () => _createPlaylist(lang),
                ),
              ]),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: PlaylistsStore.i,
                builder: (context, _) {
                  final items = PlaylistsStore.i.all;
                  if (items.isEmpty) {
                    return GatiEmpty(
                        message: tr(lang, 'playlists_empty'), onInk: false);
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

  Widget _row(GatiPalette p, String lang, Playlist pl) {
    return InkWell(
      onTap: () => context.push('/playlists/${pl.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gati.s3),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: p.chip, borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.queue_music_rounded, color: p.muted, size: 20),
          ),
          const SizedBox(width: Gati.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pl.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14.5, height: 1.35, color: p.ink)),
                const SizedBox(height: 4),
                Text(storyCount(pl.articles.length, lang),
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Gati.accent)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: p.muted),
        ]),
      ),
    );
  }
}
