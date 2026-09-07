import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/api_config.dart';
import '../models/newspaper_article.dart';

class AudioDownloadService {
  static final AudioDownloadService _instance = AudioDownloadService._();
  factory AudioDownloadService() => _instance;
  AudioDownloadService._();

  static const bool supportsDownload = !kIsWeb;

  Future<String> downloadArticle(NewspaperArticle article, String voice) async {
    final resp = await http.post(
      Uri.parse(ApiConfig.documentsSynthesizeUrl),
      headers: {
        ...ApiConfig.authHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'text': '${article.title}\n\n${article.content}',
        'language': 'te-IN',
        'speaker': voice,
        'articleId': article.id,
        'surface': article.surface,
      }),
    ).timeout(const Duration(seconds: 120));

    if (resp.statusCode != 200) {
      throw Exception('TTS HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['ok'] != true) throw Exception(data['message'] ?? 'TTS failed');

    final rawUrl = data['audioUrl'] as String?;
    if (rawUrl == null || rawUrl.isEmpty) throw Exception('No audioUrl in response');

    return _saveToDocuments(article.id, voice, rawUrl);
  }

  Future<String> _saveToDocuments(String articleId, String voice, String rawUrl) async {
    final dir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${dir.path}/gativani_audio');
    await audioDir.create(recursive: true);

    final safeName =
        '${articleId}_$voice'.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final file = File('${audioDir.path}/$safeName.wav');

    if (rawUrl.startsWith('data:')) {
      final comma = rawUrl.indexOf(',');
      if (comma < 0) throw Exception('Malformed data URL');
      await file.writeAsBytes(base64Decode(rawUrl.substring(comma + 1)));
    } else {
      final download = await http.get(Uri.parse(rawUrl));
      if (download.statusCode != 200) {
        throw Exception('Audio download failed: ${download.statusCode}');
      }
      await file.writeAsBytes(download.bodyBytes);
    }

    return file.uri.toString(); // file:///...
  }

  Future<void> deleteArticle(String articleId, String voice) async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final safeName =
          '${articleId}_$voice'.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final file = File('${dir.path}/gativani_audio/$safeName.wav');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Returns the local file URI if the article has already been saved to disk.
  Future<String?> cachedUri(String articleId, String voice) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final safeName =
          '${articleId}_$voice'.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final file = File('${dir.path}/gativani_audio/$safeName.wav');
      if (await file.exists()) return file.uri.toString();
    } catch (_) {}
    return null;
  }
}
