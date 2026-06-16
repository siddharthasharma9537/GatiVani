import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import '../config/api_config.dart';
import '../models/newspaper_article.dart';

/// App-wide singleton: queue + audio, so playback survives navigation.
/// Bind UI with ListenableBuilder on PlaybackService.i.
class PlaybackService extends ChangeNotifier {
  PlaybackService._() {
    player.playerStateStream.listen((s) {
      // Auto-advance only on a real end-of-track, not the transient "completed"
      // just_audio emits while a new url is loading.
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
  double get speed => player.speed;
  Duration get position => player.position;
  // Only report a duration once a real track is loaded (avoids a stale/zero
  // duration making the lyric highlight race).
  Duration get duration =>
      player.processingState == ProcessingState.idle ? Duration.zero : (player.duration ?? Duration.zero);

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
                  'text': a.spokenText,
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
      // setUrl completes when the clip is loaded (duration available). Clear the
      // loading state THEN start playback — play()'s future only completes at
      // end-of-track, so it must NOT be awaited.
      await player.setUrl(url);
      _recordPlay(a);
      loading = false;
      notifyListeners();
      unawaited(player.play());
    } catch (e) {
      error = e.toString();
      loading = false;
      notifyListeners();
    }
  }
}
