import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// A live match + its AI-generated Telugu commentary, from the cricket-live
/// edge function (free score facts → Gemini). `mock` is true when the sample
/// match is returned (no CRICKET_API_KEY set yet).
class CricketMatch {
  CricketMatch({
    required this.name,
    required this.teams,
    required this.status,
    required this.scoreText,
    required this.commentary,
    required this.mock,
  });

  final String name;
  final List<String> teams;
  final String status;
  final String scoreText;
  final String commentary;
  final bool mock;
}

class CricketService {
  // CricAPI resets connections from Supabase's Edge Function network
  // (consistent "Connection reset by peer" across retries — a likely
  // datacenter-IP anti-abuse block) but explicitly allows direct browser
  // calls (Access-Control-Allow-Origin: *), so the live-match fetch happens
  // right here instead of server-side. Free tier, 100 req/day, low stakes if
  // it leaks via the compiled JS — unlike every other key in this app, which
  // stays server-side only.
  static const _cricApiKey = String.fromEnvironment(
    'CRICKET_API_KEY',
    defaultValue: '88361b55-0c09-4795-af46-58b8677916d0',
  );

  /// Returns the current live match (with AI Telugu commentary), or null when
  /// nothing is live. `mock:true` requests the sample match so the card can be
  /// demoed without a real one in progress.
  Future<CricketMatch?> fetch({bool mock = false}) async {
    if (mock) return _fetchMockMatch();
    try {
      final r = await http
          .get(Uri.parse(
              'https://api.cricapi.com/v1/currentMatches?apikey=$_cricApiKey&offset=0'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      final d = json.decode(r.body) as Map<String, dynamic>;
      final matches = ((d['data'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      Map<String, dynamic>? live;
      for (final m in matches) {
        if (m['matchStarted'] == true && m['matchEnded'] == false) {
          live = m;
          break;
        }
      }
      if (live == null) return null;
      final scores = ((live['score'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      final scoreText = scores
          .map((s) =>
              '${s['inning'] ?? ''}: ${s['r'] ?? 0}/${s['w'] ?? 0} (${s['o'] ?? 0} ov)'
                  .trim())
          .join('  ');
      return _fetchCommentary(
        name: (live['name'] as String?) ?? '',
        teams: ((live['teams'] as List?) ?? const []).map((e) => '$e').toList(),
        matchType: (live['matchType'] as String?) ?? '',
        status: (live['status'] as String?) ?? '',
        scoreText: scoreText,
      );
    } catch (_) {
      return null;
    }
  }

  Future<CricketMatch?> _fetchMockMatch() async {
    final uri = Uri.parse('${ApiConfig.functionsUrl}/cricket-live?mock=1');
    try {
      final r = await http.get(uri, headers: ApiConfig.authHeaders);
      if (r.statusCode != 200) return null;
      final d = json.decode(r.body) as Map<String, dynamic>;
      if (d['live'] != true) return null;
      return _fromJson(d);
    } catch (_) {
      return null;
    }
  }

  // Sends the client-resolved match facts to the edge function, which turns
  // them into original Telugu commentary via Gemini.
  Future<CricketMatch?> _fetchCommentary({
    required String name,
    required List<String> teams,
    required String matchType,
    required String status,
    required String scoreText,
  }) async {
    final uri = Uri.parse('${ApiConfig.functionsUrl}/cricket-live');
    try {
      final r = await http
          .post(uri,
              headers: {
                ...ApiConfig.authHeaders,
                'Content-Type': 'application/json',
              },
              body: json.encode({
                'name': name,
                'teams': teams,
                'matchType': matchType,
                'status': status,
                'scoreText': scoreText,
              }))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return null;
      final d = json.decode(r.body) as Map<String, dynamic>;
      if (d['live'] != true) return null;
      return _fromJson(d);
    } catch (_) {
      return null;
    }
  }

  CricketMatch _fromJson(Map<String, dynamic> d) => CricketMatch(
        name: (d['name'] as String?) ?? '',
        teams: ((d['teams'] as List?) ?? const []).map((e) => '$e').toList(),
        status: (d['status'] as String?) ?? '',
        scoreText: (d['scoreText'] as String?) ?? '',
        commentary: (d['commentary'] as String?) ?? '',
        mock: d['mock'] == true,
      );
}
