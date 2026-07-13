import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/newspaper_article.dart';

/// One saved download: the article (so it can be read and replayed without a
/// network round-trip) plus where its audio lives — a local file URI on
/// native, the cached Storage URL on web.
class DownloadRecord {
  DownloadRecord({required this.article, required this.savedAt});

  final NewspaperArticle article;
  final DateTime savedAt;

  /// Audio saved to the device (a file:// URI) — playable with no network.
  bool get offline => (article.audioUrl ?? '').startsWith('file:');

  Map<String, dynamic> toJson() => {
        'id': article.id,
        'title': article.title,
        'content': article.content,
        'preview': article.preview,
        'category': article.category,
        'estimatedDurationSeconds': article.estimatedDurationSeconds,
        'documentType': article.documentType,
        'readingStyle': article.readingStyle,
        'suggestedSpeaker': article.suggestedSpeaker,
        'imageUrl': article.imageUrl,
        'audioUrl': article.audioUrl,
        'savedAt': savedAt.toIso8601String(),
      };

  factory DownloadRecord.fromJson(Map<String, dynamic> j) => DownloadRecord(
        article: NewspaperArticle.fromJson(j),
        savedAt:
            DateTime.tryParse(j['savedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// What "Download" actually keeps. PlaybackService.preload only warms the
/// in-memory audioUrl, which vanished on restart and left nothing to browse —
/// this store persists the article + audio so Menu → Downloads has real
/// content. Newest first, deduped by article id.
class DownloadsStore extends ChangeNotifier {
  DownloadsStore._();
  static final DownloadsStore i = DownloadsStore._();

  static const _prefsKey = 'downloads_v1';
  static const _maxRecords = 100;

  final List<DownloadRecord> _items = [];
  bool _loaded = false;

  List<DownloadRecord> get items => List.unmodifiable(_items);
  bool contains(String id) => _items.any((r) => r.article.id == id);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final list = (json.decode(raw) as List).cast<Map<String, dynamic>>();
      _items
        ..clear()
        ..addAll(list.map(DownloadRecord.fromJson));
      notifyListeners();
    } catch (_) {}
  }

  /// Record a completed download. Call after preload succeeds, when
  /// [a.audioUrl] holds the synthesized audio (Storage URL or data: URI).
  Future<void> add(NewspaperArticle a) async {
    await ensureLoaded();
    final audioUrl = await _persistAudio(a);
    final keep = a.copyWith()..audioUrl = audioUrl;
    _items.removeWhere((r) => r.article.id == a.id);
    _items.insert(0, DownloadRecord(article: keep, savedAt: DateTime.now()));
    while (_items.length > _maxRecords) {
      await _deleteLocalAudio(_items.removeLast().article);
    }
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    await ensureLoaded();
    final at = _items.indexWhere((r) => r.article.id == id);
    if (at < 0) return;
    await _deleteLocalAudio(_items.removeAt(at).article);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, json.encode(_items.map((r) => r.toJson()).toList()));
    } catch (_) {}
  }

  // On native, pull the audio onto disk so the download survives offline; on
  // web keep the Storage URL. data: URIs never go into prefs (megabytes of
  // base64 would blow the localStorage quota) — decode them to a file on
  // native, drop them on web (playback re-synthesizes; the server caches by
  // articleId so that replay is instant and free).
  Future<String?> _persistAudio(NewspaperArticle a) async {
    final url = a.audioUrl;
    if (url == null || url.isEmpty) return null;
    if (kIsWeb) return url.startsWith('data:') ? null : url;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${dir.path}/gativani_audio');
      await audioDir.create(recursive: true);
      final safe = a.id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final file = File('${audioDir.path}/dl_$safe.wav');
      if (url.startsWith('data:')) {
        final comma = url.indexOf(',');
        if (comma < 0) return null;
        await file.writeAsBytes(base64Decode(url.substring(comma + 1)));
      } else {
        final resp = await http.get(Uri.parse(url));
        if (resp.statusCode != 200) return url; // keep streaming URL
        await file.writeAsBytes(resp.bodyBytes);
      }
      return file.uri.toString();
    } catch (_) {
      return url.startsWith('data:') ? null : url;
    }
  }

  Future<void> _deleteLocalAudio(NewspaperArticle a) async {
    final url = a.audioUrl ?? '';
    if (kIsWeb || !url.startsWith('file:')) return;
    try {
      final f = File.fromUri(Uri.parse(url));
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
