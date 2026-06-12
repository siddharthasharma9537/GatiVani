import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/api_config.dart';
import '../models/article.dart';
import '../models/newspaper_article.dart';

class DocumentService {
  final String _endpoint = ApiConfig.documentsProcessUrl;

  // ── New: multi-article newspaper flow ──────────────────────────────────────

  Future<NewspaperResult> processNewspaper({
    required String filePath,
    required String filename,
    Uint8List? fileBytes,
    String tier = 'free',
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(_endpoint));
    request.headers.addAll(ApiConfig.authHeaders);
    request.headers['X-Subscription-Tier'] = tier;

    await _attachFile(request, filePath, filename, fileBytes);

    final streamed = await request.send().timeout(
      const Duration(seconds: 300),
      onTimeout: () => throw Exception('Request timed out after 5 minutes.'),
    );
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      String message = 'Server error ${response.statusCode}';
      try {
        final err = json.decode(response.body) as Map<String, dynamic>;
        if (err['message'] != null) message = err['message'] as String;
      } catch (_) {}
      if (response.statusCode == 413) throw Exception('File too large. Maximum 25 MB.');
      if (response.statusCode == 402) throw Exception('Subscription inactive.');
      throw Exception(message);
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw Exception(data['message'] ?? 'Backend returned ok=false');
    }

    final newspaper = data['newspaper'] as Map<String, dynamic>? ?? {};
    final rawArticles = data['articles'] as List<dynamic>? ?? [];
    final limits = data['limits'] as Map<String, dynamic>? ?? {};
    final subscription = data['subscription'] as Map<String, dynamic>? ?? {};

    final storageUrlForArticles = newspaper['storageUrl'] as String? ?? '';
    final articles = rawArticles
        .map((a) => NewspaperArticle.fromJson(
              a as Map<String, dynamic>,
              imageUrl: storageUrlForArticles,
            ))
        .toList();

    return NewspaperResult(
      id: newspaper['id'] as String? ?? '',
      title: newspaper['title'] as String? ?? filename,
      date: newspaper['date'] as String? ?? '',
      storageUrl: newspaper['storageUrl'] as String? ?? '',
      articles: articles,
      tier: subscription['tier'] as String? ?? tier,
      truncated: limits['truncated'] == true,
      totalPages: limits['totalPages'] as int? ?? 1,
      processedPages: limits['processedPages'] as int? ?? 1,
    );
  }

  // ── Multi-page edition flow (async job) ────────────────────────────────────
  // POST the full PDF → job starts server-side, one page per invocation.
  // Poll processing_jobs until completed, then fetch articles via REST.

  Future<EditionJob> startEdition({
    required String filePath,
    required String filename,
    Uint8List? fileBytes,
  }) async {
    final request = http.MultipartRequest(
        'POST', Uri.parse(ApiConfig.documentsProcessEditionUrl));
    request.headers.addAll(ApiConfig.authHeaders);
    await _attachFile(request, filePath, filename, fileBytes);

    final response = await http.Response.fromStream(await request.send()
        .timeout(const Duration(seconds: 90)));
    final data = json.decode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['message'] ?? 'Edition upload failed '
          '(${response.statusCode})');
    }
    return EditionJob(
      jobId: data['jobId'] as String,
      newspaperId: data['newspaperId'] as String,
      totalPages: data['totalPages'] as int,
    );
  }

  Future<EditionJobStatus> pollEdition(String jobId) async {
    final r = await http.get(
      Uri.parse('${ApiConfig.restUrl}/processing_jobs?id=eq.$jobId'
          '&select=status,done_pages,total_pages,article_count,failed_pages'),
      headers: ApiConfig.authHeaders,
    );
    final rows = json.decode(r.body) as List<dynamic>;
    if (rows.isEmpty) throw Exception('Job not found');
    final j = rows.first as Map<String, dynamic>;
    return EditionJobStatus(
      status: j['status'] as String,
      donePages: j['done_pages'] as int,
      totalPages: j['total_pages'] as int,
      articleCount: j['article_count'] as int,
      failedPages: (j['failed_pages'] as List<dynamic>).length,
    );
  }

  /// Articles of a processed edition, in page order, mapped to the same JSON
  /// shape that processNewspaper feeds into NewspaperArticle.fromJson.
  Future<List<NewspaperArticle>> fetchEditionArticles(
      String newspaperId) async {
    final r = await http.get(
      Uri.parse('${ApiConfig.restUrl}/articles?newspaper_id=eq.$newspaperId'
          '&select=id,title,content_preview,full_content,section,page_number,audio_url'
          '&order=page_number,created_at'),
      headers: ApiConfig.authHeaders,
    );
    final rows = json.decode(r.body) as List<dynamic>;
    return rows.map((row) {
      final m = row as Map<String, dynamic>;
      return NewspaperArticle.fromJson({
        'id': m['id'],
        'dbId': m['id'],
        'title': m['title'],
        'preview': m['content_preview'] ?? '',
        'content': m['full_content'] ?? '',
        'category': m['section'] ?? 'News',
        'page': m['page_number'] ?? 1,
        'audioUrl': m['audio_url'],
      }, imageUrl: '');
    }).toList();
  }

  // ── Legacy: single-article flow (ReviewScreen / PlayerScreen) ─────────────

  Future<UploadedArticle> processUploadedContent({
    required String filePath,
    required String source,
    required String filename,
    Uint8List? fileBytes,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(_endpoint));
    request.headers.addAll(ApiConfig.authHeaders);
    request.headers['X-Subscription-Tier'] = ApiConfig.subscriptionTier;

    await _attachFile(request, filePath, filename, fileBytes);

    final streamed = await request.send().timeout(
      const Duration(seconds: 300),
      onTimeout: () => throw Exception(
          'Request timed out. The server is taking too long to process your file. Please try again.'),
    );
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['message'] ?? 'Backend returned ok=false');

      final newspaper = data['newspaper'] as Map<String, dynamic>?;
      final articles = data['articles'] as List<dynamic>? ?? [];
      final limits = data['limits'] as Map<String, dynamic>? ?? {};
      final subscription = data['subscription'] as Map<String, dynamic>? ?? {};

      final truncated = limits['truncated'] == true;
      final processedPages = limits['processedPages'] as int? ?? 1;
      final totalPages = limits['totalPages'] as int? ?? 1;

      if (truncated) {
        debugPrint('[DocumentService] truncated — $processedPages/$totalPages pages processed');
      }

      final firstArticle = articles.isNotEmpty ? articles.first as Map<String, dynamic> : null;
      final title = (firstArticle?['title'] as String?) ?? (newspaper?['title'] as String?) ?? filename;
      final preview = (firstArticle?['preview'] as String?) ?? '';
      final audioUrl = (firstArticle?['audioUrl'] as String?) ?? '';
      final storageUrl = (newspaper?['storageUrl'] as String?) ?? '';

      return UploadedArticle(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        content: preview,
        source: source,
        storageUrl: storageUrl,
        category: (firstArticle?['category'] as String?) ?? 'News',
        audioUrl: audioUrl,
        extractedAt: DateTime.now(),
        truncated: truncated,
        totalPages: totalPages,
        processedPages: processedPages,
        tier: (subscription['tier'] ?? ApiConfig.subscriptionTier) as String,
      );
    } else {
      String message = 'Server error ${response.statusCode}';
      try {
        final err = json.decode(response.body) as Map<String, dynamic>;
        if (err['message'] != null) message = err['message'] as String;
      } catch (_) {}
      if (response.statusCode == 402) throw Exception('Subscription inactive. Please renew your plan.');
      if (response.statusCode == 413) throw Exception('File too large. Maximum size is 25 MB.');
      throw Exception(message);
    }
  }

  // ── Shared file-attachment helper ──────────────────────────────────────────

  Future<void> _attachFile(
    http.MultipartRequest request,
    String filePath,
    String filename,
    Uint8List? fileBytes,
  ) async {
    if (fileBytes != null) {
      final ext = filename.split('.').last.toLowerCase();
      String mime = 'image/jpeg';
      if (ext == 'png') mime = 'image/png';
      if (ext == 'pdf') mime = 'application/pdf';
      final parts = mime.split('/');
      request.files.add(http.MultipartFile.fromBytes(
        'document',
        fileBytes,
        filename: filename,
        contentType: MediaType(parts[0], parts[1]),
      ));
    } else {
      request.files.add(await http.MultipartFile.fromPath(
        'document',
        filePath,
        filename: filename,
      ));
    }
  }
}

/// Handle returned by startEdition — poll with pollEdition(jobId).
class EditionJob {
  final String jobId;
  final String newspaperId;
  final int totalPages;
  EditionJob({required this.jobId, required this.newspaperId, required this.totalPages});
}

class EditionJobStatus {
  final String status; // pending | processing | completed | failed
  final int donePages;
  final int totalPages;
  final int articleCount;
  final int failedPages;
  EditionJobStatus({
    required this.status,
    required this.donePages,
    required this.totalPages,
    required this.articleCount,
    required this.failedPages,
  });
  bool get isDone => status == 'completed' || status == 'failed';
  double get progress => totalPages == 0 ? 0 : donePages / totalPages;
}
