import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/api_config.dart';
import '../../config/alert_topics.dart';
import '../../config/districts.dart';
import '../../design/components/gati_article_sheet.dart';
import '../../design/components/gati_district_sheet.dart';
import '../../design/components/gati_masthead.dart';
import '../../design/components/gati_section_label.dart';
import '../../design/components/gati_states.dart';
import '../../design/tokens.dart';
import '../../l10n/strings.dart';
import '../../models/newspaper_article.dart';
import '../../models/playlist.dart';
import '../../services/alerts_service.dart';
import '../../services/document_service.dart';
import '../../services/downloads_store.dart';
import '../../services/edition_store.dart';
import '../../services/playback_service.dart';
import '../../services/playlists_store.dart';
import '../../services/reactions_store.dart';
import '../../services/settings_provider.dart';

/// Library tab (§8): everything personal in one place — fresh alerts for
/// watched topics, resume-where-you-left-off, the district's stories from
/// today's edition, playlists, and recent downloads. Each section is a taste
/// of its full screen and links there; sections with nothing to say don't
/// render.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Map<String, dynamic>> _resume = [];

  @override
  void initState() {
    super.initState();
    DownloadsStore.i.ensureLoaded();
    ReactionsStore.i.ensureLoaded();
    PlaylistsStore.i.ensureLoaded();
    AlertsService.i.refreshIfStale(context.read<SettingsProvider>());
    _loadResume();
  }

  // In-progress listens, newest first — same source as History, filtered to
  // what's actually resumable.
  Future<void> _loadResume() async {
    try {
      final r = await http.get(
        Uri.parse('${ApiConfig.restUrl}/recent_plays'
            '?select=article_id,title,category,position_seconds,duration_seconds,'
            'completed,played_at,content_expires_at'
            '&completed=eq.false&position_seconds=gt.0'
            '&order=played_at.desc&limit=5'),
        headers: ApiConfig.authHeaders,
      );
      final rows = (json.decode(r.body) as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _resume = rows);
    } catch (_) {}
  }

  // resolvePlayedArticle checks the 24h content snapshot first (what makes a
  // Live article resumable at all once it's scrolled out of the in-memory
  // feed pool), then that pool itself, then the permanent Paper table.
  Future<void> _resumePlay(Map<String, dynamic> m) async {
    final a = await resolvePlayedArticle(m);
    if (a == null) {
      if (mounted) {
        gatiSnack(context, 'This article is no longer available to resume.');
      }
      return;
    }
    final pos = (m['position_seconds'] as num?)?.toInt() ?? 0;
    await PlaybackService.i.playOne(a, resumeAt: Duration(seconds: pos));
  }

  // "Available for ~Xh more" — see the identical helper + rationale in
  // history_screen.dart.
  String? _expiryLabel(Map<String, dynamic> m) {
    final id = m['article_id'] as String?;
    if (id == null || PlaylistsStore.i.isInAnyPlaylist(id)) return null;
    final expiresAt =
        DateTime.tryParse(m['content_expires_at'] as String? ?? '');
    if (expiresAt == null) return null;
    final remaining = expiresAt.difference(DateTime.now().toUtc());
    if (remaining.isNegative) return null;
    final hours = remaining.inHours;
    return hours < 1
        ? 'available for less than 1h'
        : 'available for ~${hours}h more';
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final s = context.watch<SettingsProvider>();
    final lang = s.lang;
    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GatiMasthead(lang: lang, actions: [
            GatiHeaderButton(
                icon: Icons.search, onTap: () => context.push('/search')),
          ]),
          const SizedBox(height: Gati.s4),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                AlertsService.i,
                DownloadsStore.i,
                ReactionsStore.i,
                PlaylistsStore.i,
              ]),
              builder: (context, _) => _body(p, s, lang),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _body(GatiPalette p, SettingsProvider s, String lang) {
    final alerts = AlertsService.i.items.take(3).toList();
    final district = s.district == null
        ? <NewspaperArticle>[]
        : EditionStore.i.forSection('District').take(4).toList();
    final downloads = DownloadsStore.i.items.take(3).toList();
    final liked = ReactionsStore.i.liked.take(4).toList();
    final playlists = PlaylistsStore.i.all.take(8).toList();

    final children = <Widget>[];

    // ── Alerts ──────────────────────────────────────────────────────────────
    if (s.alertTopics.isEmpty) {
      children.add(_ctaCard(p, Icons.notifications_none_rounded,
          tr(lang, 'alerts_cta'), () => context.push('/alerts')));
    } else {
      children.add(_sectionHeader(p, lang, 'alerts', '/alerts'));
      if (alerts.isEmpty) {
        children.add(_quiet(p, tr(lang, 'alerts_empty')));
      } else {
        for (final a in alerts) {
          children.add(_alertRow(p, lang, a));
        }
      }
      children.add(const SizedBox(height: Gati.s5));
    }

    // ── Continue listening ──────────────────────────────────────────────────
    if (_resume.isNotEmpty) {
      children.add(_sectionHeader(p, lang, 'continue_listening', '/history'));
      for (final m in _resume) {
        children.add(_resumeRow(p, lang, m));
      }
      children.add(const SizedBox(height: Gati.s5));
    }

    // ── Playlists — small tiles, horizontally scrolling ─────────────────────
    if (playlists.isNotEmpty) {
      children.add(_sectionHeader(p, lang, 'playlists', '/playlists'));
      children.add(_playlistTiles(p, playlists));
      children.add(const SizedBox(height: Gati.s5));
    }

    // ── From your district ──────────────────────────────────────────────────
    if (s.district == null) {
      children.add(_ctaCard(p, Icons.location_on_outlined,
          tr(lang, 'set_district_cta'), () => showGatiDistrictSheet(context)));
    } else if (district.isNotEmpty) {
      final d = districtByEn(s.district);
      children.add(GatiSectionLabel(
          '${tr(lang, 'district_stories')} — '
          '${d == null ? s.district! : (lang == 'te' ? d.te : d.en)}'));
      for (final a in district) {
        children.add(_articleRow(p, lang, a));
      }
      children.add(const SizedBox(height: Gati.s5));
    }

    // ── Downloads ───────────────────────────────────────────────────────────
    if (downloads.isNotEmpty) {
      children.add(_sectionHeader(p, lang, 'downloads', '/downloads'));
      for (final r in downloads) {
        children.add(_articleRow(p, lang, r.article,
            note: r.offline ? tr(lang, 'offline') : null));
      }
      children.add(const SizedBox(height: Gati.s5));
    }

    // ── Liked stories ───────────────────────────────────────────────────────
    if (liked.isNotEmpty) {
      children.add(GatiSectionLabel(tr(lang, 'liked_stories')));
      for (final r in liked) {
        children.add(_articleRow(p, lang, r.article));
      }
      children.add(const SizedBox(height: Gati.s5));
    }

    final nothingPersonal = s.alertTopics.isEmpty &&
        _resume.isEmpty &&
        s.district == null &&
        playlists.isEmpty &&
        downloads.isEmpty &&
        liked.isEmpty;
    if (nothingPersonal) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Gati.s5, vertical: Gati.s6),
        child: GatiEmpty(message: tr(lang, 'foryou_empty'), onInk: false),
      ));
    }

    return RefreshIndicator(
      color: Gati.accent,
      onRefresh: () async {
        await Future.wait([
          AlertsService.i.refresh(context.read<SettingsProvider>()),
          _loadResume(),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: Gati.s6),
        children: children,
      ),
    );
  }

  // Section label with a trailing "See all →" that opens the full screen.
  Widget _sectionHeader(
      GatiPalette p, String lang, String key, String route) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gati.s5, 0, Gati.s5, Gati.s3),
      child: Row(children: [
        Expanded(
          child: Text(tr(lang, key),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: p.ink)),
        ),
        InkWell(
          onTap: () => context.push(route),
          child: Text(tr(lang, 'see_all'),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Gati.accent)),
        ),
      ]),
    );
  }

  // Bordered tappable teaser used when a section isn't set up yet.
  Widget _ctaCard(
      GatiPalette p, IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gati.s5, 0, Gati.s5, Gati.s5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: p.surface,
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(icon, size: 20, color: Gati.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13.5, height: 1.35, color: p.ink)),
            ),
            Icon(Icons.chevron_right, size: 18, color: p.muted),
          ]),
        ),
      ),
    );
  }

  Widget _quiet(GatiPalette p, String msg) => Padding(
        padding: const EdgeInsets.fromLTRB(Gati.s5, 0, Gati.s5, Gati.s3),
        child: Text(msg,
            style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.4)),
      );

  Widget _alertRow(GatiPalette p, String lang, AlertItem a) {
    final topic = alertTopicById(a.topic);
    return InkWell(
      onTap: () {
        final uri = Uri.tryParse(a.link);
        if (uri != null) {
          launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: Gati.s5, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              topic == null
                  ? a.topic
                  : (lang == 'te' ? topic.te : topic.en),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Gati.accent)),
          const SizedBox(height: 2),
          Text(a.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, height: 1.35, color: p.ink)),
        ]),
      ),
    );
  }

  Widget _resumeRow(GatiPalette p, String lang, Map<String, dynamic> m) {
    final dur = (m['duration_seconds'] as num?)?.toInt() ?? 0;
    final pos = (m['position_seconds'] as num?)?.toInt() ?? 0;
    final frac = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
    final expiry = _expiryLabel(m);
    return InkWell(
      onTap: () => _resumePlay(m),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: Gati.s5, vertical: 8),
        child: Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m['title'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14, height: 1.35, color: p.ink)),
                  if (expiry != null) ...[
                    const SizedBox(height: 2),
                    Text(expiry,
                        style: const TextStyle(
                            fontSize: 11, color: Gati.accent)),
                  ],
                  if (dur > 0) ...[
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                          value: frac,
                          minHeight: 3,
                          backgroundColor: p.line,
                          color: Gati.accent),
                    ),
                  ],
                ]),
          ),
          const SizedBox(width: Gati.s3),
          const Icon(Icons.play_arrow_rounded, color: Gati.accent, size: 22),
        ]),
      ),
    );
  }

  // Small tiles, side-scrolling — playlists are a browse-and-pick surface,
  // not a read-in-order list, so a horizontal row fits better than rows.
  Widget _playlistTiles(GatiPalette p, List<Playlist> playlists) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gati.s5),
        itemCount: playlists.length,
        separatorBuilder: (_, __) => const SizedBox(width: Gati.s3),
        itemBuilder: (context, i) => _playlistTile(p, playlists[i]),
      ),
    );
  }

  Widget _playlistTile(GatiPalette p, Playlist pl) {
    final count = pl.articles.length;
    return InkWell(
      onTap: () => context.push('/playlists/${pl.id}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 132,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: p.surface,
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.queue_music_rounded,
                color: Gati.accent, size: 20),
            const Spacer(),
            Text(pl.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, height: 1.25, color: p.ink)),
            const SizedBox(height: 2),
            Text('$count ${count == 1 ? 'story' : 'stories'}',
                style: TextStyle(fontSize: 11, color: p.muted)),
          ],
        ),
      ),
    );
  }

  Widget _articleRow(GatiPalette p, String lang, NewspaperArticle a,
      {String? note}) {
    return InkWell(
      onTap: () => PlaybackService.i.playOne(a),
      onLongPress: () {
        final box = context.findRenderObject() as RenderBox?;
        final center = box == null
            ? const Offset(200, 400)
            : box.localToGlobal(box.size.center(Offset.zero));
        showGatiArticleMenu(context, center, a);
      },
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: Gati.s5, vertical: 8),
        child: Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14, height: 1.35, color: p.ink)),
                  const SizedBox(height: 2),
                  Text(
                      '${sectionLabel(a.category, lang)}'
                      '${note != null ? ' · $note' : ''}',
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: Gati.accent)),
                ]),
          ),
          const SizedBox(width: Gati.s3),
          const Icon(Icons.play_arrow_rounded, color: Gati.accent, size: 22),
        ]),
      ),
    );
  }
}
