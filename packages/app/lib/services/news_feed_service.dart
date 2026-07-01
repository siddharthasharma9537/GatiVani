import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// One headline from the feeds-news edge function (Google News Telugu RSS).
class NewsItem {
  NewsItem({
    required this.title,
    required this.link,
    required this.source,
    required this.pubDate,
  });

  final String title;
  final String link;
  final String source;
  final String pubDate; // RFC822, e.g. "Tue, 30 Jun 2026 18:50:51 GMT"

  factory NewsItem.fromJson(Map<String, dynamic> j) => NewsItem(
        title: (j['title'] as String?) ?? '',
        link: (j['link'] as String?) ?? '',
        source: (j['source'] as String?) ?? '',
        pubDate: (j['pubDate'] as String?) ?? '',
      );
}

/// A full web article (from feeds-articles) — carries the whole body so the
/// reader renders + narrates it without a second fetch.
class WebArticle {
  WebArticle({
    required this.id,
    required this.title,
    required this.link,
    required this.source,
    required this.pubDate,
    required this.summary,
    required this.body,
  });

  final String id; // stable uuid (used as the TTS cache key)
  final String title;
  final String link;
  final String source;
  final String pubDate;
  final String summary;
  final String body;

  factory WebArticle.fromJson(Map<String, dynamic> j) => WebArticle(
        id: (j['id'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        link: (j['link'] as String?) ?? '',
        source: (j['source'] as String?) ?? '',
        pubDate: (j['pubDate'] as String?) ?? '',
        summary: (j['summary'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
      );
}

/// A market ticker item (index or metal) from feeds-markets. `value` is index
/// points for nifty/sensex, ₹/10g for gold, ₹/kg for silver.
class MarketItem {
  MarketItem({required this.key, required this.value, required this.changePct});
  final String key; // nifty | sensex | gold | silver
  final double value;
  final double changePct;

  factory MarketItem.fromJson(Map<String, dynamic> j) => MarketItem(
        key: (j['key'] as String?) ?? '',
        value: (j['value'] as num?)?.toDouble() ?? 0,
        changePct: (j['changePct'] as num?)?.toDouble() ?? 0,
      );
}

/// Fetches Telugu news from the feeds edge functions. Both do the cross-origin
/// fetch + RSS parse server-side, so the web app never hits a CORS wall.
class NewsFeedService {
  /// Live market ticker (Nifty, Sensex, gold ₹/10g, silver ₹/kg).
  Future<List<MarketItem>> fetchMarkets() async {
    final uri = Uri.parse('${ApiConfig.functionsUrl}/feeds-markets');
    try {
      final r = await http.get(uri, headers: ApiConfig.authHeaders);
      if (r.statusCode != 200) return [];
      final d = json.decode(r.body) as Map<String, dynamic>;
      final items = (d['items'] as List?) ?? const [];
      return items
          .map((e) => MarketItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Headlines only (Google News, diverse) — for the marquee.
  Future<List<NewsItem>> fetch({String topic = 'top', int limit = 12}) async {
    final uri = Uri.parse(
        '${ApiConfig.functionsUrl}/feeds-news?topic=$topic&limit=$limit');
    try {
      final r = await http.get(uri, headers: ApiConfig.authHeaders);
      if (r.statusCode != 200) return [];
      final d = json.decode(r.body) as Map<String, dynamic>;
      final items = (d['items'] as List?) ?? const [];
      return items
          .map((e) => NewsItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Full articles (publisher feeds with <content:encoded>) — readable +
  /// narratable in-app.
  Future<List<WebArticle>> fetchArticles({int limit = 20}) async {
    final uri =
        Uri.parse('${ApiConfig.functionsUrl}/feeds-articles?limit=$limit');
    try {
      final r = await http.get(uri, headers: ApiConfig.authHeaders);
      if (r.statusCode != 200) return [];
      final d = json.decode(r.body) as Map<String, dynamic>;
      final items = (d['items'] as List?) ?? const [];
      return items
          .map((e) => WebArticle.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

/// Holds the article the /reader route is showing. go_router `extra` is lost on
/// browser Back, so — like EditionStore — the data lives here and the route
/// reads it (falling back to home if empty on a cold deep-link).
class ReaderStore {
  ReaderStore._();
  static final ReaderStore i = ReaderStore._();
  WebArticle? current;
}

const _months = <String, int>{
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
};

/// Parse an RFC822 pubDate ("Tue, 30 Jun 2026 18:50:51 GMT") to UTC. dart:io's
/// HttpDate isn't available on web, so parse the fixed shape directly.
DateTime? parseRfc822(String s) {
  final m =
      RegExp(r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2})').firstMatch(s);
  if (m == null) return null;
  final mon = _months[m.group(2)];
  if (mon == null) return null;
  return DateTime.utc(
    int.parse(m.group(3)!),
    mon,
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6)!),
  );
}

/// Compact relative age badge, e.g. "5m" / "2h" / "1d".
String relativeAge(String pubDate, String lang) {
  final dt = parseRfc822(pubDate);
  if (dt == null) return '';
  final diff = DateTime.now().toUtc().difference(dt);
  if (diff.inMinutes < 1) return lang == 'te' ? 'ఇప్పుడే' : 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  return '${diff.inDays}d';
}
