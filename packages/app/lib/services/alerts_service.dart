import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'settings_provider.dart';

/// One announcement from feeds-alerts: a release-shaped headline (result
/// declared, notification out, admit card up…) for a watched topic.
class AlertItem {
  AlertItem({
    required this.topic,
    required this.title,
    required this.link,
    required this.source,
    required this.date,
  });

  final String topic;
  final String title;
  final String link;
  final String source;
  final DateTime? date;

  factory AlertItem.fromJson(Map<String, dynamic> j) => AlertItem(
        topic: (j['topic'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        link: (j['link'] as String?) ?? '',
        source: (j['source'] as String?) ?? '',
        date: _parseRfc822((j['pubDate'] as String?) ?? ''),
      );

  // "Tue, 30 Jun 2026 18:50:51 GMT" — DateTime.parse can't read RFC822.
  static DateTime? _parseRfc822(String s) {
    final m = RegExp(
            r'(\d{1,2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{4}) (\d{2}):(\d{2}):(\d{2})')
        .firstMatch(s);
    if (m == null) return null;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return DateTime.utc(
      int.parse(m.group(3)!),
      months.indexOf(m.group(2)!) + 1,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }
}

/// App-wide alerts cache: fetches feeds-alerts for the user's watched topics,
/// keeps the result for the session, and derives the unread count for the
/// menu badge (items newer than SettingsProvider.alertsSeenAt). Bind UI with
/// ListenableBuilder on AlertsService.i.
class AlertsService extends ChangeNotifier {
  AlertsService._();
  static final AlertsService i = AlertsService._();

  List<AlertItem> items = [];
  bool loading = false;
  bool failed = false;
  DateTime? _fetchedAt;
  DateTime? _seenAt; // mirrored from settings on each refresh

  int get unread {
    if (_seenAt == null) return items.length;
    return items.where((a) => a.date != null && a.date!.isAfter(_seenAt!)).length;
  }

  /// Refresh at most every 10 minutes (matches the edge cache) — safe to call
  /// from build methods like the menu row: the fetch (and its
  /// notifyListeners) is deferred past the current build frame.
  void refreshIfStale(SettingsProvider settings) {
    final fresh = _fetchedAt != null &&
        DateTime.now().difference(_fetchedAt!) < const Duration(minutes: 10);
    _seenAt = settings.alertsSeenAt;
    if (fresh || loading) return;
    loading = true; // claim now so overlapping build calls don't double-fetch
    scheduleMicrotask(() => refresh(settings));
  }

  Future<void> refresh(SettingsProvider settings) async {
    final topics = settings.alertTopics;
    _seenAt = settings.alertsSeenAt;
    if (topics.isEmpty) {
      items = [];
      _fetchedAt = DateTime.now();
      failed = false;
      loading = false;
      notifyListeners();
      return;
    }
    loading = true;
    failed = false;
    notifyListeners();
    try {
      final r = await http.get(
        Uri.parse('${ApiConfig.functionsUrl}/feeds-alerts'
            '?topics=${topics.join(",")}'),
        headers: ApiConfig.authHeaders,
      ).timeout(const Duration(seconds: 25));
      final data = json.decode(r.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        items = ((data['items'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(AlertItem.fromJson)
            .toList();
        _fetchedAt = DateTime.now();
      } else {
        failed = true;
      }
    } catch (_) {
      failed = true;
    }
    loading = false;
    notifyListeners();
  }
}
