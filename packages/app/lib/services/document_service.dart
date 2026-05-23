import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/api_config.dart';
import '../models/article.dart';

/// Sends a document to gativani-core for Gemini processing.
///
/// Backend response shape (v2):
/// {
///   ok: true,
///   title: string,
///   summary: string,
///   category: string,
///   storageUrl: string,
///   model: string,
///   subscription: { tier, active },
///   limits: { maxPages, totalPages, processedPages, truncated }
/// }
/// Sends a document to gativani-core and returns an [UploadedArticle].
///
/// Canonical name: document_service.dart
/// (uploaded_content_service.dart is a backward-compat re-export)
class DocumentService {
  final String _endpoint = ApiConfig.documentsProcessUrl;

  Future<UploadedArticle> processUploadedContent({
    required String filePath,
    required String source,
    required String filename,
    Uint8List? fileBytes,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(_endpoint));

    // Subscription tier header — accepted when TRUST_CLIENT_TIER_HEADERS=true on backend
    request.headers['X-Subscription-Tier'] = ApiConfig.subscriptionTier;

    // Attach file
    if (kIsWeb && fileBytes != null) {
      final ext = filename.split('.').last.toLowerCase();
      final subtype = ext == 'png' ? 'png' : 'jpeg';
      request.files.add(http.MultipartFile.fromBytes(
        'document',
        fileBytes,
        filename: filename,
        contentType: MediaType('image', subtype),
      ));
    } else if (fileBytes != null) {
      final ext = filename.split('.').last.toLowerCase();
      String mimeType = 'image/jpeg';
      if (ext == 'png') mimeType = 'image/png';
      if (ext == 'pdf') mimeType = 'application/pdf';
      final parts = mimeType.split('/');
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

    final streamed = await request.send().timeout(
      const Duration(seconds: 300),
      onTimeout: () => throw Exception(
          'Request timed out. The server is taking too long to process your file. Please try again.'),
    );
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;

      if (data['ok'] != true) {
        throw Exception(data['message'] ?? 'Backend returned ok=false');
      }

      // Handle new response format (v2 multi-stage pipeline)
      final newspaper = data['newspaper'] as Map<String, dynamic>?;
      final articles = data['articles'] as List<dynamic>? ?? [];
      final limits = data['limits'] as Map<String, dynamic>? ?? {};
      final subscription = data['subscription'] as Map<String, dynamic>? ?? {};

      final truncated = limits['truncated'] == true;
      final processedPages = limits['processedPages'] as int? ?? 1;
      final totalPages = limits['totalPages'] as int? ?? 1;

      if (truncated) {
        debugPrint(
            '[UploadService] Warning: truncated — $processedPages/$totalPages pages processed');
      }

      // Use the first article if available, otherwise use newspaper metadata
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
        category: (firstArticle?['section'] as String?) ?? 'News',
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

      if (response.statusCode == 402) {
        throw Exception('Subscription inactive. Please renew your plan.');
      }
      if (response.statusCode == 413) {
        throw Exception('File too large. Maximum size is 25 MB.');
      }
      throw Exception(message);
    }
  }
}
