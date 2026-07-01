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
  /// Returns the current live match (with commentary), or null when nothing is
  /// live / no key is configured. `mock:true` requests the sample match so the
  /// card can be demoed before a key exists.
  Future<CricketMatch?> fetch({bool mock = false}) async {
    final uri = Uri.parse(
        '${ApiConfig.functionsUrl}/cricket-live${mock ? '?mock=1' : ''}');
    try {
      final r = await http.get(uri, headers: ApiConfig.authHeaders);
      if (r.statusCode != 200) return null;
      final d = json.decode(r.body) as Map<String, dynamic>;
      if (d['live'] != true) return null;
      return CricketMatch(
        name: (d['name'] as String?) ?? '',
        teams: ((d['teams'] as List?) ?? const []).map((e) => '$e').toList(),
        status: (d['status'] as String?) ?? '',
        scoreText: (d['scoreText'] as String?) ?? '',
        commentary: (d['commentary'] as String?) ?? '',
        mock: d['mock'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}
