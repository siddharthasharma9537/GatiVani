import 'package:flutter/material.dart';

import '../design/components/gati_states.dart';
import '../design/components/gati_tile.dart';
import '../design/section_colors.dart';
import '../design/tokens.dart';
import '../l10n/strings.dart';
import '../models/newspaper_article.dart';
import '../services/news_feed_service.dart';
import '../services/playback_service.dart';

/// The podcast shows we surface, shared by the Live and Shows tabs.
const kPodcastTiles =
    <({String key, String title, String meta, String section})>[
  (key: 'air_news', title: 'AIR Telugu News', meta: '8 min · today', section: 'general'),
  (key: 'mann_ki_baat', title: 'Mann Ki Baat', meta: '30 min · monthly', section: 'politics'),
  (key: 'bhagavad_gita', title: 'Bhagavad Gita', meta: '12 min · daily', section: 'devotional'),
  (key: 'cinema_talk', title: 'Cinema Talk', meta: '18 min · weekly', section: 'entertainment'),
];

// Stable per-show ids so each show's tile always overwrites one recent-plays
// row instead of piling up as the latest episode changes.
const _podcastIds = <String, String>{
  'air_news': 'a0000000-0000-4000-8000-0000000000d0',
  'bhagavad_gita': 'a0000000-0000-4000-8000-0000000000d1',
  'cinema_talk': 'a0000000-0000-4000-8000-0000000000d2',
};

/// Play a podcast episode directly — audioUrl is a real MP3, so playOne
/// skips TTS synthesis entirely. Mann Ki Baat is the one exception: it
/// opens the full archive as a playlist instead of just the latest episode.
void playPodcastEpisode(PodcastEpisode ep) {
  if (ep.key == 'mann_ki_baat') {
    openMkbPlaylist();
    return;
  }
  final art = NewspaperArticle(
    id: _podcastIds[ep.key] ?? 'a0000000-0000-4000-8000-0000000000d0',
    title: ep.episodeTitle,
    content: '',
    preview: ep.title,
    category: ep.title,
    estimatedDurationSeconds: ep.durationSeconds > 0 ? ep.durationSeconds : 60,
    audioUrl: ep.audioUrl,
  );
  PlaybackService.i.playOne(art);
}

/// Loads the full Mann Ki Baat archive (Part-1, 2014 → latest) as the play
/// queue and starts the newest episode. Every other episode's audio stays
/// unresolved until it's actually tapped — see playMkbQueueEntry.
Future<void> openMkbPlaylist() async {
  final feed = NewsFeedService();
  final episodes = await feed.fetchMkbPlaylist();
  if (episodes.isEmpty) return;
  final articles = episodes
      .map((e) => NewspaperArticle(
            id: e.id,
            title: e.title,
            content: '',
            preview: e.title,
            category: 'Mann Ki Baat',
            estimatedDurationSeconds: 0, // unknown until resolved
            documentType: 'mkb_episode',
          ))
      .toList();
  final resolved = await feed.resolveMkbEpisode(articles.first.id);
  if (resolved == null) return;
  articles.first.audioUrl = resolved.audioUrl;
  await PlaybackService.i.playAll(articles, start: 0);
}

/// Two-column grid of show tiles, tinted by section ramp.
class PodcastsGrid extends StatelessWidget {
  const PodcastsGrid({
    super.key,
    required this.episodes,
    required this.lang,
    this.tiles = kPodcastTiles,
  });

  final Map<String, PodcastEpisode> episodes;
  final String lang;
  final List<({String key, String title, String meta, String section})> tiles;

  @override
  Widget build(BuildContext context) {
    final dark = GatiPalette.of(context).dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gati.s5),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: Gati.s3,
        crossAxisSpacing: Gati.s3,
        childAspectRatio: 1.55,
        children: tiles.map((it) {
          final ep = episodes[it.key];
          return GatiTile(
            title: it.title,
            meta: ep != null ? _episodeMeta(ep, lang) : it.meta,
            ramp: sectionRamp(it.section, dark: dark),
            onTap: ep != null
                ? () => playPodcastEpisode(ep)
                // No verified real audio source for this show yet.
                : () => gatiSnack(context, 'Podcasts coming soon'),
          );
        }).toList(),
      ),
    );
  }

  // e.g. "14 min · 2d" — real episode length + how recently it dropped.
  String _episodeMeta(PodcastEpisode ep, String lang) {
    final mins = (ep.durationSeconds / 60).round().clamp(1, 999);
    final unit = lang == 'te' ? 'ని.' : 'min';
    final age = relativeAge(ep.pubDate, lang);
    return age.isEmpty ? '$mins $unit' : '$mins $unit · $age';
  }
}
