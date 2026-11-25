import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'paper_audio_models.dart';

/// Owner-only. Rows come through the signed-in client (RLS lets only `story_publishers` read them);
/// bytes come only from the playback Worker with the user's access token. There is no bucket URL.
class PaperAudioRepository {
  PaperAudioRepository({
    SupabaseClient? client,
    http.Client? httpClient,
    String? workerUrl,
    String? Function()? accessToken,
  })  : _client = client,
        _http = httpClient ?? http.Client(),
        workerUrl = (workerUrl ?? '').replaceAll(RegExp(r'/+$'), ''),
        _token = accessToken;

  final SupabaseClient? _client;
  final http.Client _http;
  final String? Function()? _token;

  /// Base of the Worker, for example `https://gativani.sohum.cc`. Empty means the feature is off.
  final String workerUrl;

  bool get configured => workerUrl.isNotEmpty;
  SupabaseClient get client => _client ?? Supabase.instance.client;
  String? get token {
    final provider = _token;
    return provider != null
        ? provider()
        : client.auth.currentSession?.accessToken;
  }

  /// Newest day's playlist for an edition, or empty (not signed in, not the owner, nothing published).
  Future<PaperAudioPlaylist> playlist(String edition, String isoDate) async {
    final rows = await client
        .from('paper_story_audio')
        .select()
        .eq('edition', edition)
        .eq('source_date', isoDate)
        .order('rank');
    return PaperAudioPlaylist(rows.map(PaperAudioStory.fromJson));
  }

  Uri uriFor(PaperAudioStory story) =>
      Uri.parse('$workerUrl/paper-audio/${story.workerPath}');

  Map<String, String> get headers {
    final t = token;
    if (t == null || t.isEmpty) throw StateError('Not signed in');
    return {'Authorization': 'Bearer $t'};
  }

  /// Whole file with the bearer token (web playback cannot send headers from an audio element).
  Future<Uint8List> fetchBytes(PaperAudioStory story) async {
    final response = await _http.get(uriFor(story), headers: headers);
    if (response.statusCode != 200) {
      throw http.ClientException(
          'Audio unavailable (HTTP ${response.statusCode})');
    }
    return response.bodyBytes;
  }
}
