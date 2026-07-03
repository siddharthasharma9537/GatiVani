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
import '../services/playback_service.dart';
import '../services/settings_provider.dart';
import '../widgets/mini_player.dart';

/// Listening history (menu → History): everything played, newest first,
/// with progress — tap to resume where it left off.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await http.get(
        Uri.parse('${ApiConfig.restUrl}/recent_plays'
            '?select=article_id,title,category,position_seconds,duration_seconds,completed,played_at'
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

  // Resume: refetch the article by id and play from the saved spot.
  Future<void> _resume(Map<String, dynamic> m) async {
    final id = m['article_id'] as String?;
    if (id == null) return;
    final a = await DocumentService().fetchArticleById(id);
    if (a == null) return;
    final pos = (m['position_seconds'] as num?)?.toInt() ?? 0;
    final done = m['completed'] == true;
    await PlaybackService.i.playOne(a,
        resumeAt: done ? null : Duration(seconds: pos));
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final lang = context.watch<SettingsProvider>().lang;
    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gati.s3, Gati.s2, Gati.s5, Gati.s2),
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
          Expanded(
            child: _loading
                ? const Center(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Gati.accent)))
                : _rows.isEmpty
                    ? GatiEmpty(
                        message: tr(lang, 'history_empty'), onInk: false)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                            Gati.s5, Gati.s2, Gati.s5, Gati.s6),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: p.line),
                        itemBuilder: (_, i) => _row(p, lang, _rows[i]),
                      ),
          ),
          MiniPlayer(onExpand: () => context.push('/player')),
        ]),
      ),
    );
  }

  Widget _row(GatiPalette p, String lang, Map<String, dynamic> m) {
    final dur = (m['duration_seconds'] as num?)?.toInt() ?? 0;
    final pos = (m['position_seconds'] as num?)?.toInt() ?? 0;
    final done = m['completed'] == true;
    final frac = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
    return InkWell(
      onTap: () => _resume(m),
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
                    '${dur > 0 && !done ? ' · ${((1 - frac) * dur / 60).ceil()} ${tr(lang, 'min')}' : ''}',
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
          Icon(done ? Icons.replay_rounded : Icons.play_arrow_rounded,
              color: Gati.accent, size: 22),
        ]),
      ),
    );
  }
}
