import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import '../config/api_config.dart';
import '../models/newspaper_article.dart';

/// App-wide singleton: queue + audio, so playback survives navigation.
/// Bind UI with AnimatedBuilder/ListenableBuilder on PlaybackService.i.
class PlaybackService extends ChangeNotifier {
  PlaybackService._() {
    player.playerStateStream.listen((s) {
      // Only auto-advance on a genuine end-of-track, not the transient
      // "completed" just_audio emits while a new url is being loaded.
      if (s.processingState == ProcessingState.completed && !loading) next();
      notifyListeners();
    });
    player.positionStream.listen((_) => notifyListeners());
  }
  static final PlaybackService i = PlaybackService._();

  final AudioPlayer player = AudioPlayer();
  final List<NewspaperArticle> queue = [];
  int index = -1;
  bool loading = false;
  String? error;

  NewspaperArticle? get current =>
      (index >= 0 && index < queue.length) ? queue[index] : null;
  bool get isPlaying => player.playing;
  Duration get position => player.position;
  Duration get duration => player.duration ?? Duration.zero;

  Future<void> playAll(List<NewspaperArticle> articles, {int start = 0}) async {
    queue
      ..clear()
      ..addAll(articles);
    await _playIndex(start);
  }

  Future<void> playOne(NewspaperArticle a) async {
    final at = queue.indexWhere((x) => x.id == a.id);
    if (at >= 0) return _playIndex(at);
    queue.add(a);
    await _playIndex(queue.length - 1);
  }

  Future<void> next() async {
    if (index + 1 < queue.length) await _playIndex(index + 1);
  }

  Future<void> previous() async {
    if (index > 0) await _playIndex(index - 1);
  }

  void toggle() => player.playing ? player.pause() : player.play();
  void seek(Duration d) => player.seek(d);
  void setSpeed(double s) => player.setSpeed(s);

  /// Fire-and-forget: record into recent_plays so the Today screen can show
  /// recently-played history.
  void _recordPlay(NewspaperArticle a) {
    http
        .post(Uri.parse('${ApiConfig.restUrl}/recent_plays'),
            headers: {...ApiConfig.authHeaders, 'Content-Type': 'application/json'},
            body: json.encode({
              'article_id': a.id,
              'title': a.title,
              'category': a.category,
              'page': a.page,
            }))
        .catchError((_) => http.Response('', 204));
  }

  Future<void> _playIndex(int idx) async {
    index = idx;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final a = queue[idx];
      var url = a.audioUrl;
      if (url == null || !url.startsWith('http')) {
        final r = await http
            .post(Uri.parse(ApiConfig.documentsSynthesizeUrl),
                headers: {
                  ...ApiConfig.authHeaders,
                  'Content-Type': 'application/json'
                },
                body: json.encode({
                  'text': a.content.isNotEmpty ? a.content : a.preview,
                  'language': 'te-IN',
                  'articleId': a.id,
                  if (a.suggestedSpeaker.isNotEmpty) 'speaker': a.suggestedSpeaker,
                  if (a.readingStyle.isNotEmpty) 'readingStyle': a.readingStyle,
                }))
            .timeout(const Duration(seconds: 120));
        final data = json.decode(r.body) as Map<String, dynamic>;
        if (data['ok'] != true) throw Exception(data['message'] ?? 'TTS failed');
        url = data['audioUrl'] as String;
        a.audioUrl = url;
      }
      // Stop the previous track before swapping the source — avoids the web
      // case where a new setUrl is ignored while the old one is still active.
      await player.stop();
      await player.setUrl(url);
      await player.play();
      _recordPlay(a);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
