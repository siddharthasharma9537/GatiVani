import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'playback_service.dart';

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
  Future<List<MarketItem>> fetchMarkets({String? city}) async {
    final uri = Uri.parse('${ApiConfig.functionsUrl}/feeds-markets'
        '${city != null && city.isNotEmpty ? '?city=$city' : ''}');
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

  /// Real podcast episodes (direct MP3, no TTS) — for the Podcasts grid.
  Future<List<PodcastEpisode>> fetchPodcasts() async {
    final uri = Uri.parse('${ApiConfig.functionsUrl}/feeds-podcasts');
    try {
      final r = await http.get(uri, headers: ApiConfig.authHeaders);
      if (r.statusCode != 200) return [];
      final d = json.decode(r.body) as Map<String, dynamic>;
      final items = (d['items'] as List?) ?? const [];
      return items
          .map((e) => PodcastEpisode.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// The full Mann Ki Baat archive (Part-1, Oct 2014 → latest), recent→oldest.
  /// Titles/dates only — no audio URL yet, each episode is resolved lazily via
  /// [resolveMkbEpisode] only when actually tapped to play.
  Future<List<MkbEpisode>> fetchMkbPlaylist() async {
    final uri = Uri.parse('${ApiConfig.functionsUrl}/feeds-mkb-playlist');
    try {
      final r = await http.get(uri, headers: ApiConfig.authHeaders)
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return [];
      final d = json.decode(r.body) as Map<String, dynamic>;
      final items = (d['items'] as List?) ?? const [];
      return items
          .map((e) => MkbEpisode.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Resolves one Mann Ki Baat episode's real audio URL — scrapes
  /// pmonradio.nic.in on demand (lazy: only called when an episode is tapped).
  Future<({String audioUrl, int durationSeconds})?> resolveMkbEpisode(
      String divId) async {
    final uri = Uri.parse(
        '${ApiConfig.functionsUrl}/feeds-mkb-playlist?resolve=$divId');
    try {
      final r = await http.get(uri, headers: ApiConfig.authHeaders)
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return null;
      final d = json.decode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) return null;
      return (
        audioUrl: d['audioUrl'] as String,
        durationSeconds: (d['durationSeconds'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// "GatiVani Take" — the weight-to-article pick: the single most newsworthy
  /// national/international headline right now, with an ORIGINAL Telugu
  /// title + explainer synthesized from independently-corroborated facts
  /// (never a translation of any one publisher's wording).
  Future<Explainer?> fetchExplainer() async {
    final uri = Uri.parse('${ApiConfig.functionsUrl}/feeds-explains');
    try {
      final r = await http.get(uri, headers: ApiConfig.authHeaders)
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return null;
      final d = json.decode(r.body) as Map<String, dynamic>;
      if (d['available'] != true) return null;
      return Explainer.fromJson(d);
    } catch (_) {
      return null;
    }
  }
}

/// The "GatiVani Take" pick — an original Telugu title + explainer for the
/// day's highest-weighted national/international headline, from
/// feeds-explains (weight-to-article scoring → Gemini synthesis over
/// corroborated facts only).
class Explainer {
  Explainer({
    required this.title,
    required this.commentary,
    required this.category,
    required this.sourceCount,
    required this.sources,
  });

  final String title;
  final String commentary;
  final String category; // "national" | "international"
  final int sourceCount;
  final List<String> sources;

  factory Explainer.fromJson(Map<String, dynamic> j) => Explainer(
        title: (j['title'] as String?) ?? '',
        commentary: (j['commentary'] as String?) ?? '',
        category: (j['category'] as String?) ?? '',
        sourceCount: (j['sourceCount'] as num?)?.toInt() ?? 0,
        sources: ((j['sources'] as List?) ?? const [])
            .map((e) => '$e')
            .toSet() // sources[] can repeat the same publisher
            .toList(),
      );
}

/// A real podcast episode (from feeds-podcasts) — carries a direct MP3 URL, so
/// the player can skip TTS entirely and just play it.
class PodcastEpisode {
  PodcastEpisode({
    required this.key,
    required this.title,
    required this.episodeTitle,
    required this.audioUrl,
    required this.durationSeconds,
    required this.pubDate,
  });

  final String key; // show id, e.g. "bhagavad_gita"
  final String title; // show name
  final String episodeTitle;
  final String audioUrl;
  final int durationSeconds;
  final String pubDate;

  factory PodcastEpisode.fromJson(Map<String, dynamic> j) => PodcastEpisode(
        key: (j['key'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        episodeTitle: (j['episodeTitle'] as String?) ?? '',
        audioUrl: (j['audioUrl'] as String?) ?? '',
        durationSeconds: (j['durationSeconds'] as num?)?.toInt() ?? 0,
        pubDate: (j['pubDate'] as String?) ?? '',
      );
}

/// One Mann Ki Baat archive entry (from feeds-mkb-playlist). `id` is the
/// site's own div id (e.g. "div135") — also the key passed to
/// `resolveMkbEpisode` when the episode is actually tapped to play.
class MkbEpisode {
  MkbEpisode({required this.id, required this.title, required this.pubDate});

  final String id;
  final String title;
  final String pubDate;

  factory MkbEpisode.fromJson(Map<String, dynamic> j) => MkbEpisode(
        id: (j['id'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        pubDate: (j['pubDate'] as String?) ?? '',
      );
}

/// Holds the article the /reader route is showing. go_router `extra` is lost on
/// browser Back, so — like EditionStore — the data lives here and the route
/// reads it (falling back to home if empty on a cold deep-link).
class ReaderStore {
  ReaderStore._();
  static final ReaderStore i = ReaderStore._();
  WebArticle? current;
  // The full pool the current article was drawn from (Latest stories) — lets
  // the reader and player surface "Related articles" from the same source.
  List<WebArticle> all = [];
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

/// Resolves (if needed) and plays a Mann Ki Baat entry already sitting in
/// PlaybackService's queue at [i]. The shared player treats a null audioUrl
/// as "needs TTS synthesis" (see PlaybackService._playIndex), which is wrong
/// for MKB rows — a real archive episode always needs a URL fetched first.
/// Already-resolved rows (the one the playlist opened with) just play.
Future<void> playMkbQueueEntry(int i) async {
  final q = PlaybackService.i.queue;
  if (i < 0 || i >= q.length) return;
  final art = q[i];
  if (art.audioUrl == null) {
    final resolved = await NewsFeedService().resolveMkbEpisode(art.id);
    if (resolved == null) return;
    art.audioUrl = resolved.audioUrl;
  }
  await PlaybackService.i.playAt(i);
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
