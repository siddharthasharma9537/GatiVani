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

// One flattened live match, before it's sent off for Telugu commentary.
class _LiveMatch {
  _LiveMatch({
    required this.name,
    required this.teams,
    required this.matchType,
    required this.status,
    required this.scoreText,
    required this.seriesName,
  });
  final String name;
  final List<String> teams;
  final String matchType;
  final String status;
  final String scoreText;
  final String seriesName;

  bool get isIndia => teams.any((t) => t.toLowerCase() == 'india');
  bool get isT20 => matchType.toUpperCase().contains('T20');
  bool get isWorldCup => seriesName.toLowerCase().contains('world cup');
}

class CricketService {
  // Cricbuzz (via RapidAPI). CricAPI was the original source, but it resets
  // connections from Supabase's Edge Function network (consistent "Connection
  // reset by peer" — a likely datacenter-IP anti-abuse block); Cricbuzz has
  // the same constraint in reverse — RapidAPI keys are meant for direct client
  // calls, so this fetch happens here, not server-side. Free tier, low stakes
  // if it leaks via the compiled JS, unlike every other key in this app.
  static const _rapidApiKey = String.fromEnvironment(
    'CRICBUZZ_API_KEY',
    defaultValue: '9df7631106msh98f8fecedc04941p14846fjsn1d84d0a920e3',
  );
  static const _host = 'cricbuzz-cricket.p.rapidapi.com';

  /// Returns the current live match (with AI Telugu commentary), or null when
  /// nothing is live. `mock:true` requests the sample match so the card can be
  /// demoed without a real one in progress.
  ///
  /// When several matches are live, priority is: an India match first, then
  /// any T20 or World Cup match, then whatever's live.
  Future<CricketMatch?> fetch({bool mock = false}) async {
    if (mock) return _fetchMockMatch();
    try {
      final r = await http.get(
        Uri.parse('https://$_host/matches/v1/live'),
        headers: {'x-rapidapi-host': _host, 'x-rapidapi-key': _rapidApiKey},
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      final d = json.decode(r.body) as Map<String, dynamic>;
      final live = _collectLiveMatches(d);
      if (live.isEmpty) return null;
      final picked = _pickBest(live);
      return _fetchCommentary(
        name: picked.name,
        teams: picked.teams,
        matchType: picked.matchType,
        status: picked.status,
        scoreText: picked.scoreText,
      );
    } catch (_) {
      return null;
    }
  }

  // Cricbuzz nests matches under typeMatches[] (International/League/
  // Domestic/Women) → seriesMatches[] → seriesAdWrapper.matches[] — some
  // seriesMatches entries are ad placeholders with no seriesAdWrapper at all.
  List<_LiveMatch> _collectLiveMatches(Map<String, dynamic> d) {
    final out = <_LiveMatch>[];
    for (final tm in (d['typeMatches'] as List?) ?? const []) {
      final seriesMatches =
          ((tm as Map<String, dynamic>)['seriesMatches'] as List?) ?? const [];
      for (final sm in seriesMatches) {
        final wrapper =
            (sm as Map<String, dynamic>)['seriesAdWrapper'] as Map<String, dynamic>?;
        if (wrapper == null) continue; // ad placeholder
        final seriesName = (wrapper['seriesName'] as String?) ?? '';
        for (final m in (wrapper['matches'] as List?) ?? const []) {
          final info = (m as Map<String, dynamic>)['matchInfo'] as Map<String, dynamic>?;
          if (info == null || info['state'] != 'In Progress') continue;
          final t1 = ((info['team1'] as Map<String, dynamic>?)?['teamName'] as String?) ?? '';
          final t2 = ((info['team2'] as Map<String, dynamic>?)?['teamName'] as String?) ?? '';
          out.add(_LiveMatch(
            name: '${info['matchDesc'] ?? ''}, $seriesName'.trim(),
            teams: [t1, t2],
            matchType: (info['matchFormat'] as String?) ?? '',
            status: (info['status'] as String?) ?? '',
            scoreText: _scoreText(
                (m['matchScore'] as Map<String, dynamic>?) ?? const {}, t1, t2),
            seriesName: seriesName,
          ));
        }
      }
    }
    return out;
  }

  String _scoreText(Map<String, dynamic> matchScore, String t1, String t2) {
    final parts = <String>[];
    void addTeam(String label, String key) {
      final innings = matchScore[key] as Map<String, dynamic>?;
      if (innings == null) return;
      for (final inn in innings.values) {
        final m = inn as Map<String, dynamic>;
        parts.add('$label: ${m['runs'] ?? 0}/${m['wickets'] ?? 0} (${m['overs'] ?? 0} ov)');
      }
    }
    addTeam(t1, 'team1Score');
    addTeam(t2, 'team2Score');
    return parts.join('  ');
  }

  // India first, then T20/World Cup, then whatever's live. Only the top
  // pick is used, so sort stability within a tier doesn't matter.
  _LiveMatch _pickBest(List<_LiveMatch> matches) {
    int tier(_LiveMatch m) {
      if (m.isIndia) return 0;
      if (m.isT20 || m.isWorldCup) return 1;
      return 2;
    }
    final sorted = [...matches]..sort((a, b) => tier(a).compareTo(tier(b)));
    return sorted.first;
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
