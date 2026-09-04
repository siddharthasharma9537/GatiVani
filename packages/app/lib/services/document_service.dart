import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/api_config.dart';
import '../models/article.dart';
import '../models/newspaper_article.dart';
import 'news_feed_service.dart';

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
  // Start the ingest pipeline, then poll it until the edition is ready.

  Future<EditionJob> startEdition({
    required String filePath,
    required String filename,
    Uint8List? fileBytes,
    void Function(double progress)? onProgress,
  }) async {
    final bytes = fileBytes;
    if (bytes == null) throw Exception('Could not read file bytes.');

    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : 'pdf';
    final mime = ext == 'png'
        ? 'image/png'
        : (ext == 'jpg' || ext == 'jpeg')
            ? 'image/jpeg'
            : 'application/pdf';
    final safe = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path = 'editions/${DateTime.now().millisecondsSinceEpoch}_$safe';

    // 1. Heavy leg: upload bytes straight to Supabase Storage (not via the edge
    //    function). dio reports real byte progress (XHR upload events on web).
    final storageBase =
        ApiConfig.restUrl.replaceFirst('/rest/v1', '/storage/v1/object');
    final dio = Dio();
    final up = await dio.post<dynamic>(
      '$storageBase/uploads/$path',
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {
          ...ApiConfig.authHeaders,
          'content-type': mime,
          'content-length': bytes.length,
        },
        contentType: mime,
        sendTimeout: const Duration(minutes: 10),
        receiveTimeout: const Duration(minutes: 10),
        validateStatus: (s) => s != null && s < 500,
      ),
      onSendProgress: (sent, total) {
        final t = total > 0 ? total : bytes.length;
        onProgress?.call(sent / t);
      },
    );
    if (up.statusCode != 200 && up.statusCode != 201) {
      throw Exception('Upload failed (${up.statusCode}). Check your connection.');
    }

    // 2. Light leg: start the job from the stored path (returns in seconds).
    // Signed-in callers send their own JWT so the job is attributed to them
    // and shows up under their uploads; anonymous ones fall back to the anon
    // key and rely on the job id as their handle.
    final r = await http
        .post(Uri.parse(ApiConfig.pipelineStartUrl),
            headers: {
              ...ApiConfig.userAuthHeaders,
              'Content-Type': 'application/json',
            },
            body: json.encode({'sourcePath': path, 'filename': filename}))
        .timeout(const Duration(seconds: 120));
    final data = json.decode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200 || data['ok'] != true) {
      final msg = data['error'] == 'gemini_key_required'
          ? 'Add your Gemini API key in Settings to process an edition.'
          : (data['message'] ?? 'Edition start failed (${r.statusCode})');
      throw Exception(msg);
    }
    return EditionJob(
      jobId: data['jobId'] as String,
      newspaperId: data['newspaperId'] as String,
      totalPages: data['totalPages'] as int,
      pubDate: data['pubDate'] as String?,
    );
  }

  /// Progress for a running edition.
  ///
  /// Read through the pipeline-status function rather than straight from the
  /// table: the ingest tables are RLS-scoped to their owner, and an edition can
  /// be uploaded without signing in. The job id is the capability — an
  /// unguessable uuid handed only to whoever started the job.
  Future<EditionJobStatus> pollEdition(String jobId) async {
    final r = await http.get(
      Uri.parse('${ApiConfig.pipelineStatusUrl}?jobId=$jobId'),
      headers: ApiConfig.userAuthHeaders,
    ).timeout(const Duration(seconds: 20));
    final j = json.decode(r.body) as Map<String, dynamic>;
    if (j['ok'] != true) {
      throw Exception(j['message'] ?? j['error'] ?? 'Job not found');
    }
    return EditionJobStatus(
      status: j['status'] as String? ?? 'queued',
      donePages: (j['donePages'] as num?)?.toInt() ?? 0,
      totalPages: (j['totalPages'] as num?)?.toInt() ?? 0,
      articleCount: (j['articleCount'] as num?)?.toInt() ?? 0,
      failedPages: (j['failedPages'] as num?)?.toInt() ?? 0,
      dedupedPages: (j['dedupedPages'] as num?)?.toInt() ?? 0,
      error: j['error'] as String?,
    );
  }

  /// Vāni, the grounded assistant: ask about an article. Edition articles are
  /// grounded server-side from the DB; for web stories / podcasts (not in the
  /// DB) pass [articleText] + [articleTitle] so Vāni grounds on those instead.
  Future<String> ask(String articleId, String question,
      {String? articleText, String? articleTitle, bool general = false}) async {
    final r = await http
        .post(Uri.parse('${ApiConfig.functionsUrl}/documents-ask'),
            headers: {...ApiConfig.authHeaders, 'Content-Type': 'application/json'},
            body: json.encode({
              'articleId': articleId,
              'question': question,
              if (articleText != null && articleText.trim().isNotEmpty)
                'articleText': articleText,
              if (articleTitle != null) 'articleTitle': articleTitle,
              if (general) 'mode': 'general',
            }))
        .timeout(const Duration(seconds: 45));
    final data = json.decode(r.body) as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw Exception(data['message'] ?? 'Assistant unavailable');
    }
    return data['answer'] as String? ?? '—';
  }

  /// Edition to open the app onto: the most recently processed one with
  /// articles, falling back to the pinned featured/demo edition. This makes a
  /// fresh upload become the home edition automatically.
  Future<({String title, String id, String? pubDate, List<NewspaperArticle> articles})?>
      fetchFeaturedEdition() async {
    final r = await http.get(
      Uri.parse('${ApiConfig.restUrl}/newspapers'
          '?select=id,title,publication_date,featured&order=created_at.desc&limit=6'),
      headers: ApiConfig.authHeaders,
    );
    final rows = (json.decode(r.body) as List<dynamic>).cast<Map<String, dynamic>>();
    // Newest first (query already ordered): return the first edition that
    // actually has articles.
    for (final n in rows) {
      final arts = await fetchEditionArticles(n['id'] as String);
      if (arts.isNotEmpty) {
        return (
          title: n['title'] as String,
          id: n['id'] as String,
          pubDate: n['publication_date'] as String?,
          articles: arts,
        );
      }
    }
    return null;
  }

  /// A single article by its DB id — lets surfaces like "Recently played" play
  /// an item without depending on the currently-loaded edition list.
  /// Gated to processing_status=ready — same bar as fetchEditionArticles, so a
  /// flagged article can't be reached indirectly (e.g. via History) even
  /// though it was never offered in a listing.
  Future<NewspaperArticle?> fetchArticleById(String id) async {
    final r = await http.get(
      Uri.parse('${ApiConfig.restUrl}/articles?id=eq.$id&processing_status=eq.ready'
          '&select=id,title,content_preview,full_content,section,page_number,audio_url,summary_audio_url&limit=1'),
      headers: ApiConfig.authHeaders,
    );
    final rows = json.decode(r.body) as List<dynamic>;
    if (rows.isEmpty) return null;
    final m = rows.first as Map<String, dynamic>;
    return NewspaperArticle.fromJson({
      'id': m['id'],
      'title': m['title'],
      'preview': m['content_preview'] ?? '',
      'content': m['full_content'] ?? '',
      'category': m['section'] ?? 'News',
      'page': m['page_number'] ?? 1,
      'audioUrl': m['audio_url'],
      'summaryAudioUrl': m['summary_audio_url'],
    }, imageUrl: '');
  }

  /// Articles of a processed edition, in page order, mapped to the same JSON
  /// shape that processNewspaper feeds into NewspaperArticle.fromJson.
  /// Only processing_status=ready — the extraction pipeline flags articles it
  /// isn't confident about (missing headline, low OCR coverage, fused
  /// articles, mid-sentence cutoffs) as "review" instead, and until now that
  /// signal was computed but never actually used: flagged articles reached
  /// users identically to clean ones. This is the gate that makes the flag
  /// mean something.
  Future<List<NewspaperArticle>> fetchEditionArticles(
      String newspaperId) async {
    final r = await http.get(
      Uri.parse('${ApiConfig.restUrl}/articles?newspaper_id=eq.$newspaperId'
          '&processing_status=eq.ready'
          '&select=id,title,content_preview,full_content,section,page_number,audio_url,summary_audio_url'
          '&order=page_number,created_at'),
      headers: ApiConfig.authHeaders,
    );
    final rows = json.decode(r.body) as List<dynamic>;
    final all = rows.map((row) {
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
        'summaryAudioUrl': m['summary_audio_url'],
      }, imageUrl: '');
    }).toList();
    return _dedupe(all);
  }

  /// Collapse the duplicates a newspaper naturally produces: a front-page teaser
  /// and the full story carry the same headline, and cross-page continuations
  /// land as headline-less fragments. Keep the longest version per headline (so
  /// the teaser yields to the full article) in page order, and drop fragments
  /// that have no headline of their own.
  List<NewspaperArticle> _dedupe(List<NewspaperArticle> all) {
    final byTitle = <String, int>{}; // title → index in out
    final out = <NewspaperArticle>[];
    for (final a in all) {
      final key = a.title.trim();
      if (key.isEmpty) continue; // continuation fragment, not its own article
      final at = byTitle[key];
      if (at == null) {
        byTitle[key] = out.length;
        out.add(a);
      } else if (a.content.length > out[at].content.length) {
        out[at] = a; // replace the teaser with the fuller story, keep position
      }
    }
    return out;
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
  final String? pubDate;
  EditionJob({
    required this.jobId,
    required this.newspaperId,
    required this.totalPages,
    this.pubDate,
  });
}

class EditionJobStatus {
  /// queued | splitting | pages | stitching | ready | failed
  final String status;
  final int donePages;
  final int totalPages;
  final int articleCount;
  final int failedPages;

  /// Pages served from an earlier upload of the same physical page, costing
  /// no OCR and no model calls.
  final int dedupedPages;
  final String? error;

  EditionJobStatus({
    required this.status,
    required this.donePages,
    required this.totalPages,
    required this.articleCount,
    required this.failedPages,
    this.dedupedPages = 0,
    this.error,
  });

  bool get isDone => status == 'ready' || status == 'failed';
  bool get failed => status == 'failed';
  double get progress => totalPages == 0 ? 0 : donePages / totalPages;
}

/// Small bag of fields common to both shapes callers need a played article
/// resolved into (NewspaperArticle for playback, WebArticle for the reader).
class _ResolvedContent {
  _ResolvedContent(this.id, this.title, this.body, this.preview,
      this.category, this.language);
  final String id, title, body, preview, category, language;
}

/// Resolve a `recent_plays` row back to its full article content, in order:
/// (1) the row's own 24h content snapshot, if not expired — this is what
/// makes a Live article resumable at all once it's scrolled out of the
/// in-memory feed pool; (2) that in-memory pool itself, as a same-session
/// fallback; (3) the permanent Paper articles table. Null if genuinely
/// unavailable. An expired-but-still-populated snapshot is nulled out
/// best-effort when found (lazy cleanup — nothing does this proactively).
Future<_ResolvedContent?> _resolvePlayedContent(Map<String, dynamic> m) async {
  final id = m['article_id'] as String?;
  if (id == null) return null;
  final content = m['content'] as String?;
  final expiresAt =
      DateTime.tryParse(m['content_expires_at'] as String? ?? '');
  if (content != null && content.isNotEmpty) {
    if (expiresAt != null && expiresAt.isAfter(DateTime.now().toUtc())) {
      return _ResolvedContent(
        id,
        m['title'] as String? ?? '',
        content,
        m['preview'] as String? ?? '',
        m['category'] as String? ?? 'News',
        m['language'] as String? ?? 'te',
      );
    }
    unawaited(_expireContentSnapshot(id));
  }
  final live = liveArticleById(id);
  if (live != null) {
    return _ResolvedContent(
        live.id, live.title, live.body, live.summary, live.source,
        live.language);
  }
  final a = await DocumentService().fetchArticleById(id);
  if (a == null) return null;
  return _ResolvedContent(
      a.id, a.title, a.content, a.preview, a.category, a.language);
}

Future<void> _expireContentSnapshot(String articleId) async {
  try {
    await http.patch(
      Uri.parse('${ApiConfig.restUrl}/recent_plays?article_id=eq.$articleId'),
      headers: {
        // recent_plays is scoped per user (RLS checks auth.uid()).
        ...ApiConfig.userAuthHeaders,
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'content': null,
        'preview': null,
        'language': null,
        'content_expires_at': null,
      }),
    );
  } catch (_) {
    // Best-effort — a leftover expired snapshot is harmless clutter, not a
    // correctness problem (it's never read once past its own expiry check).
  }
}

/// For resume/direct-play call sites (History's resume icon, For You's
/// Continue-listening row).
Future<NewspaperArticle?> resolvePlayedArticle(Map<String, dynamic> m) async {
  final c = await _resolvePlayedContent(m);
  if (c == null) return null;
  return NewspaperArticle(
    id: c.id,
    title: c.title,
    content: c.body,
    preview: c.preview,
    category: c.category,
    estimatedDurationSeconds: NewspaperArticle.estimateDuration(c.body),
    readingStyle: 'news_anchor',
    language: c.language,
  );
}

/// For History's row tap, which opens the Reader (same split-tap convention
/// as everywhere else in the app).
Future<WebArticle?> resolvePlayedWebArticle(Map<String, dynamic> m) async {
  final c = await _resolvePlayedContent(m);
  if (c == null) return null;
  return WebArticle(
    id: c.id,
    title: c.title,
    link: '',
    source: c.category,
    pubDate: '',
    summary: c.preview,
    body: c.body,
    language: c.language,
  );
}
