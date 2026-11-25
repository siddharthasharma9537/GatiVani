import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'paper_models.dart';

/// Uses the app's initialized client/session. No service-role access or local
/// review API. One persistent last view supports restart/offline reading.
class PaperRepository {
  PaperRepository({SupabaseClient? client}) : _client = client;
  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? Supabase.instance.client;
  static const _cacheKey = 'published_paper_view_v1';

  Future<List<PaperDay>> latestDays() async {
    final latest = await client
        .from('paper_days')
        .select('source_date')
        .order('source_date', ascending: false)
        .limit(1);
    if (latest.isEmpty) return [];
    final rows = await client
        .from('paper_days')
        .select('edition,source_date,paper_editions(title)')
        .eq('source_date', latest.first['source_date'])
        .order('edition');
    return rows.map(PaperDay.fromJson).toList();
  }

  Future<List<PaperStory>> stories(PaperDay day) async {
    final out = <PaperStory>[];
    const batch = 200;
    for (var start = 0;; start += batch) {
      final rows = await client
          .from('paper_stories')
          .select()
          .eq('edition', day.edition)
          .eq('source_date', day.date)
          .order('sort_order')
          .order('source_id')
          .range(start, start + batch - 1);
      out.addAll(rows.map(PaperStory.fromJson));
      if (rows.length < batch) return out;
    }
  }

  Future<PaperStory?> story(String edition, String date, String id) async {
    final row = await client
        .from('paper_stories')
        .select()
        .eq('edition', edition)
        .eq('source_date', date)
        .eq('source_id', id)
        .maybeSingle();
    return row == null ? null : PaperStory.fromJson(row);
  }

  Future<PaperView?> cachedView() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_cacheKey);
      return raw == null
          ? null
          : PaperView.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // A corrupt or old cache must not prevent fetching fresh data.
    }
  }

  Future<void> clearCache() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_cacheKey);
    } catch (_) {}
  }

  Future<void> cacheView(PaperView view) async {
    try {
      await (await SharedPreferences.getInstance())
          .setString(_cacheKey, jsonEncode(view.toJson()));
    } catch (_) {
      // Reading still works when browser storage is unavailable/full.
    }
  }
}
