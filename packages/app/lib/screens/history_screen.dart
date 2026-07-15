import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../design/components/gati_states.dart';
import '../design/tokens.dart';
import '../l10n/strings.dart';
import '../services/document_service.dart';
import '../services/news_feed_service.dart';
import '../services/playback_service.dart';
import '../services/playlists_store.dart';
import '../services/settings_provider.dart';
import '../widgets/gati_puck.dart';

/// Listening history (menu → History): everything played, newest first,
/// with progress — tap to resume where it left off.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

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
            padding:
                const EdgeInsets.fromLTRB(Gati.s3, Gati.s2, Gati.s5, Gati.s2),
            child: Row(children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: p.ink),
                onPressed: () => context.pop(),
              ),
              Text(tr(lang, 'history'),
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: p.ink)),
            ]),
          ),
          const Expanded(child: HistoryBody()),
        ]),
        ),
        const GatiPuck(),
      ]),
    );
  }
}

/// The history list alone — shared by the /history route and the shell's
/// right-edge "Recent" drawer.
class HistoryBody extends StatefulWidget {
  const HistoryBody({super.key});

  @override
  State<HistoryBody> createState() => _HistoryBodyState();
}

class _HistoryBodyState extends State<HistoryBody> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    PlaylistsStore.i.ensureLoaded();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await http.get(
        Uri.parse('${ApiConfig.restUrl}/recent_plays'
            '?select=article_id,title,category,position_seconds,duration_seconds,'
            'completed,played_at,content_expires_at'
            '&order=played_at.desc&limit=50'),
        headers: ApiConfig.authHeaders,
      );
      final rows = (json.decode(r.body) as List).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Row tap: open the full story text, same as everywhere else in the app
  // (Live/Paper/Playlist all split tap this way — text opens the reader,
  // a separate ▶/resume icon plays directly). resolvePlayedWebArticle checks
  // the 24h content snapshot, then the in-memory Live pool, then the
  // permanent Paper table, in that order.
  Future<void> _openReader(Map<String, dynamic> m) async {
    final a = await resolvePlayedWebArticle(m);
    if (a == null) {
      if (mounted) gatiSnack(context, 'This article is no longer available.');
      return;
    }
    ReaderStore.i.current = a;
    if (mounted) context.push('/reader');
  }

  // Resume button: play directly in the mini-player from the saved spot,
  // bypassing the reader.
  Future<void> _resume(Map<String, dynamic> m) async {
    final a = await resolvePlayedArticle(m);
    if (a == null) {
      if (mounted) {
        gatiSnack(context, 'This article is no longer available to resume.');
      }
      return;
    }
    final pos = (m['position_seconds'] as num?)?.toInt() ?? 0;
    final done = m['completed'] == true;
    await PlaybackService.i.playOne(a,
        resumeAt: done ? null : Duration(seconds: pos));
  }

  // "Available for ~Xh more" — only shown while the 24h temporary content
  // snapshot is what's actually keeping this resumable (a playlist save
  // makes it permanent through a separate mechanism; an already-expired or
  // never-set snapshot just shows nothing rather than a stale warning).
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
    final lang = context.watch<SettingsProvider>().lang;
    return _loading
        ? const Center(
            child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Gati.accent)))
        : _rows.isEmpty
            ? GatiEmpty(message: tr(lang, 'history_empty'), onInk: false)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                    Gati.s5, Gati.s2, Gati.s5, Gati.s6),
                itemCount: _rows.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: p.line),
                itemBuilder: (_, i) => _row(p, lang, _rows[i]),
              );
  }

  Widget _row(GatiPalette p, String lang, Map<String, dynamic> m) {
    final dur = (m['duration_seconds'] as num?)?.toInt() ?? 0;
    final pos = (m['position_seconds'] as num?)?.toInt() ?? 0;
    final done = m['completed'] == true;
    final frac = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
    final expiry = _expiryLabel(m);
    // Split tap, same convention as Live/Paper/Playlist rows elsewhere: the
    // text opens the reader (with a Resume/Replay/Listen button that reads
    // this same saved progress), the trailing icon resumes/replays directly
    // in the mini-player without leaving History.
    return InkWell(
      onTap: () => _openReader(m),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gati.s3),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m['title'] as String? ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14.5, height: 1.35, color: p.ink)),
                const SizedBox(height: 4),
                Text(
                    '${m['category'] ?? ''}'
                    '${dur > 0 && !done ? ' · ${((1 - frac) * dur / 60).ceil()} ${tr(lang, 'min')}' : ''}'
                    '${expiry != null ? ' · $expiry' : ''}',
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Gati.accent)),
                if (dur > 0 && !done) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 3,
                        backgroundColor: p.line,
                        color: Gati.accent),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Gati.s3),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _resume(m),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(done ? Icons.replay_rounded : Icons.play_arrow_rounded,
                  color: Gati.accent, size: 22),
            ),
          ),
        ]),
      ),
    );
  }
}
