import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' as io;
import 'dart:math' as Math;
import 'package:archive/archive.dart';

/// SarvamAI service for OCR extraction and Text-to-Speech
/// Based on official Sarvam AI API documentation
class SarvamAIService {
  static const String _baseUrl = 'https://api.sarvam.ai';
  static const String _apiKey = 'sk_xqudb0jx_2dQeYl1Q4K1BbhGDTLTeRIrH'; // Replace with actual key

  /// Extract text from image using Sarvam AI OCR API (Document Intelligence)
  /// Falls back to editable template if API unavailable
  Future<String> extractTextFromImage(String filePath) async {
    try {
      print('[OCR] Starting OCR for: $filePath');

      // Verify file exists
      final imageFile = io.File(filePath);
      if (!imageFile.existsSync()) {
        throw Exception('File not found: $filePath');
      }

      final imageBytes = await imageFile.readAsBytes();
      print('[OCR] Image size: ${imageBytes.length} bytes');

      // Try Sarvam AI OCR API
      print('[OCR] Attempting Sarvam AI Document Intelligence service...');
      try {
        final extractedText = await _callSarvamAIOcr(imageBytes);
        print('[OCR] Success! Extracted ${extractedText.length} characters');
        return extractedText;
      } catch (apiError) {
        print('[OCR] ❌ Sarvam AI API failed!');
        print('[OCR] Error type: ${apiError.runtimeType}');
        print('[OCR] Error message: $apiError');
        print('[OCR] Stack trace: ${apiError}');
        print('[OCR] Providing editable template for manual entry...');

        // Fall back to template with helpful instructions
        return _generateEditableTemplate();
      }
    } catch (e) {
      print('[OCR] ❌ Critical error: $e');
      print('[OCR] Error type: ${e.runtimeType}');
      return _generateEditableTemplate();
    }
  }

  /// Call Sarvam AI Document Intelligence API
  /// Uses the CORRECT REST API structure from official Sarvam AI documentation
  /// https://docs.sarvam.ai/api-reference-docs/document-intelligence
  Future<String> _callSarvamAIOcr(Uint8List imageBytes) async {
    try {
      print('[OCR] Starting Sarvam AI Document Intelligence workflow...');

      // Step 1: Create a document intelligence job
      print('[OCR] Step 1: Creating job...');
      final jobId = await _createDocumentJob();
      print('[OCR] Job created: $jobId');

      // Step 2: Get presigned upload URLs and upload file
      print('[OCR] Step 2: Getting upload URLs and uploading document...');
      await _uploadDocumentFileWithPresignedUrl(jobId, imageBytes);
      print('[OCR] Document uploaded via presigned URL');

      // Step 3: Start processing
      print('[OCR] Step 3: Starting job processing...');
      await _startDocumentJob(jobId);
      print('[OCR] Job started');

      // Step 4: Wait for completion
      print('[OCR] Step 4: Waiting for processing to complete...');
      await _waitForJobCompletion(jobId);
      print('[OCR] Job completed');

      // Step 5: Download and extract text from output
      print('[OCR] Step 5: Downloading and extracting text from results...');
      final extractedText = await _downloadAndExtractText(jobId);
      print('[OCR] Text extraction complete: ${extractedText.length} characters');

      return extractedText;
    } catch (e) {
      print('[OCR] Error in document intelligence workflow: $e');
      rethrow;
    }
  }

  /// Step 1: Create a document intelligence job
  /// Endpoint: POST /doc-digitization/job/v1
  Future<String> _createDocumentJob() async {
    final response = await http.post(
      Uri.parse('$_baseUrl/doc-digitization/job/v1'),
      headers: {
        'Content-Type': 'application/json',
        'api-subscription-key': _apiKey,
      },
      body: jsonEncode({
        'job_parameters': {
          'language': 'te-IN', // CRITICAL: BCP-47 format! Must be 'te-IN' for Telugu
          'output_format': 'md', // Using markdown for now (JSON debugging needed)
        },
      }),
    ).timeout(const Duration(seconds: 30));

    print('[OCR API] Create job response: ${response.statusCode}');
    print('[OCR API] Response body: ${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 202) {
      final data = jsonDecode(response.body);
      final jobId = data['job_id'];
      if (jobId != null) {
        return jobId.toString();
      }
    }

    throw Exception('Failed to create job: ${response.statusCode} - ${response.body}');
  }

  /// Step 2: Get presigned upload URLs and upload document file
  /// Endpoint: POST /doc-digitization/job/v1/upload-files
  Future<void> _uploadDocumentFileWithPresignedUrl(String jobId, Uint8List imageBytes) async {
    try {
      // Try multipart form data upload first (may be more reliable than presigned URLs)
      print('[OCR API] Attempting MULTIPART upload directly to Sarvam...');

      final multipartRequest = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/doc-digitization/job/v1/$jobId/upload'),
      );

      multipartRequest.headers['api-subscription-key'] = _apiKey;
      multipartRequest.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: 'document.jpg',
        ),
      );

      try {
        final streamedResponse = await multipartRequest.send().timeout(const Duration(seconds: 60));
        final multipartResponse = await http.Response.fromStream(streamedResponse);

        print('[OCR API] Multipart response: ${multipartResponse.statusCode}');
        print('[OCR API] Multipart body: ${multipartResponse.body}');

        if (multipartResponse.statusCode == 200 || multipartResponse.statusCode == 201 || multipartResponse.statusCode == 202) {
          print('[OCR API] ✓ Multipart upload successful!');
          return;
        }
      } catch (multipartError) {
        print('[OCR API] Multipart upload failed: $multipartError');
      }

      // Fallback to presigned URL approach if multipart fails
      print('[OCR API] Fallback: Trying presigned URL upload...');

      final uploadUrlsResponse = await http.post(
        Uri.parse('$_baseUrl/doc-digitization/job/v1/upload-files'),
        headers: {
          'Content-Type': 'application/json',
          'api-subscription-key': _apiKey,
        },
        body: jsonEncode({
          'job_id': jobId,
          'files': ['document.jpg'],
        }),
      ).timeout(const Duration(seconds: 30));

      print('[OCR API] Upload URLs response: ${uploadUrlsResponse.statusCode}');

      if (uploadUrlsResponse.statusCode != 200) {
        throw Exception('Failed to get upload URLs: ${uploadUrlsResponse.statusCode}');
      }

      final urlsData = jsonDecode(uploadUrlsResponse.body);
      final uploadUrls = urlsData['upload_urls'] as Map<String, dynamic>;
      final documentUrl = uploadUrls['document.jpg'] as Map<String, dynamic>;
      final presignedUrl = documentUrl['file_url'] as String;

      print('[OCR API] Got presigned URL, uploading to Azure...');

      // Azure Blob Storage REQUIRES x-ms-blob-type header for presigned URLs
      final putResponse = await http.put(
        Uri.parse(presignedUrl),
        headers: {
          'x-ms-blob-type': 'BlockBlob', // CRITICAL: Azure requires this!
        },
        body: imageBytes,
      ).timeout(const Duration(seconds: 60));

      print('[OCR API] Presigned upload response: ${putResponse.statusCode}');

      if (putResponse.statusCode == 200 || putResponse.statusCode == 201) {
        print('[OCR API] ✓ Presigned upload successful!');
        return;
      }

      // Log full Azure error response
      print('[OCR API] --- AZURE ERROR (Full Response) ---');
      print('[OCR API] Response bytes length: ${putResponse.bodyBytes.length}');
      print('[OCR API] Response text length: ${putResponse.body.length}');

      // Print line by line
      final lines = putResponse.body.split('\n');
      for (int i = 0; i < lines.length; i++) {
        print('[OCR API] Line $i: ${lines[i]}');
      }

      print('[OCR API] --- END AZURE ERROR ---');
      print('[OCR API] Full body: ${putResponse.body}');

      throw Exception('Presigned URL upload failed with 400');
    } catch (e) {
      print('[OCR API] Upload error: $e');
      rethrow;
    }
  }

  /// Step 3: Start document processing
  /// Endpoint: POST /doc-digitization/job/v1/{job_id}/start
  Future<void> _startDocumentJob(String jobId) async {
    try {
      print('[OCR API] Starting job processing for job: $jobId');
      final response = await http.post(
        Uri.parse('$_baseUrl/doc-digitization/job/v1/$jobId/start'),
        headers: {
          'Content-Type': 'application/json',
          'api-subscription-key': _apiKey,
        },
        body: jsonEncode({}),
      ).timeout(const Duration(seconds: 30));

      print('[OCR API] Start job response: ${response.statusCode}');
      print('[OCR API] Start job body: ${response.body}');

      if (response.statusCode != 200 && response.statusCode != 201 && response.statusCode != 202) {
        throw Exception('Failed to start job: ${response.statusCode} - ${response.body}');
      }

      final data = jsonDecode(response.body);
      final jobState = data['job_state'];
      print('[OCR API] Job state after start: $jobState');
    } catch (e) {
      print('[OCR API] Error starting job: $e');
      rethrow;
    }
  }

  /// Step 4: Wait for job completion with polling
  /// Endpoint: GET /doc-digitization/job/v1/{job_id}/status
  Future<void> _waitForJobCompletion(String jobId) async {
    const maxRetries = 120; // 2 minutes max
    const pollInterval = Duration(seconds: 1);

    print('[OCR API] Starting job completion polling (max $maxRetries retries, interval ${pollInterval.inSeconds}s)');

    for (int i = 0; i < maxRetries; i++) {
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/doc-digitization/job/v1/$jobId/status'),
          headers: {
            'api-subscription-key': _apiKey,
          },
        ).timeout(const Duration(seconds: 10));

        print('[OCR API] Poll attempt ${i + 1}/$maxRetries: Status ${response.statusCode}');

        if (response.statusCode == 200) {
          try {
            final data = jsonDecode(response.body);
            final state = data['job_state']; // CRITICAL: Only 'job_state', not 'state'
            print('[OCR API] Job state: $state');
            print('[OCR API] Full status response: ${response.body}');

            // Job states: Accepted, Pending, Running, Completed, PartiallyCompleted, Failed
            if (state == 'Completed' || state == 'PartiallyCompleted') {
              print('[OCR API] ✓ Job processing complete!');
              final jobDetails = data['job_details'] as List?;
              if (jobDetails != null && jobDetails.isNotEmpty) {
                final details = jobDetails[0] as Map<String, dynamic>;
                print('[OCR API] Job details: ${details['state']} - ${details['pages_processed']}/${details['total_pages']} pages');
              }
              return;
            } else if (state == 'Failed') {
              final errorMsg = data['error_message'] ?? data['error'] ?? 'Unknown error';
              final jobDetails = data['job_details'];
              throw Exception('Job failed: $errorMsg | Details: $jobDetails');
            }
            // For Accepted, Pending, Running - continue polling
          } catch (parseError) {
            if (parseError is FormatException) {
              throw Exception('Failed to parse status response: ${response.body}');
            }
            rethrow;
          }
        } else if (response.statusCode == 404) {
          throw Exception('Job not found (404): ${response.body}');
        } else {
          print('[OCR API] ⚠ Unexpected status: ${response.statusCode}');
          print('[OCR API] Response: ${response.body}');
        }

        await Future.delayed(pollInterval);
      } catch (e) {
        print('[OCR API] Poll error at attempt ${i + 1}: $e');
        if (i == maxRetries - 1) {
          throw Exception('Job completion polling timeout after $maxRetries retries: $e');
        }
        await Future.delayed(pollInterval);
      }
    }

    throw Exception('Job processing timeout after ${maxRetries}s');
  }

  /// Step 5: Download output files and extract text
  /// Endpoint: POST /doc-digitization/job/v1/{job_id}/download-files
  Future<String> _downloadAndExtractText(String jobId) async {
    try {
      print('[OCR API] Requesting download URLs for job: $jobId');

      // Get download URLs
      final downloadUrlsResponse = await http.post(
        Uri.parse('$_baseUrl/doc-digitization/job/v1/$jobId/download-files'),
        headers: {
          'Content-Type': 'application/json',
          'api-subscription-key': _apiKey,
        },
        body: jsonEncode({}),
      ).timeout(const Duration(seconds: 30));

      print('[OCR API] Download URLs response: ${downloadUrlsResponse.statusCode}');
      print('[OCR API] Download URLs body length: ${downloadUrlsResponse.body.length}');
      print('[OCR API] Download URLs body: ${downloadUrlsResponse.body}');

      if (downloadUrlsResponse.statusCode != 200) {
        throw Exception('Failed to get download URLs: ${downloadUrlsResponse.statusCode} - ${downloadUrlsResponse.body}');
      }

      Map<String, dynamic> downloadData;
      try {
        downloadData = jsonDecode(downloadUrlsResponse.body);
      } catch (parseError) {
        throw Exception('Failed to parse download URLs response: $parseError | Body: ${downloadUrlsResponse.body}');
      }

      final downloadUrls = downloadData['download_urls'] as Map<String, dynamic>?;

      if (downloadUrls == null) {
        throw Exception('Missing download_urls in response. Available keys: ${downloadData.keys.toList()}');
      }

      if (downloadUrls.isEmpty) {
        throw Exception('No output files available in download_urls');
      }

      print('[OCR API] Found ${downloadUrls.length} output file(s)');

      // Find the markdown or text output file
      String? outputUrl;
      String? selectedFilename;

      for (final filename in downloadUrls.keys) {
        print('[OCR API]  - Available output: $filename');
        if (filename.endsWith('.md') || filename.endsWith('.txt')) {
          try {
            final fileData = downloadUrls[filename] as Map<String, dynamic>?;
            if (fileData != null) {
              outputUrl = fileData['file_url'] as String?;
              if (outputUrl != null && outputUrl.isNotEmpty) {
                selectedFilename = filename;
                print('[OCR API] ✓ Selected: $filename');
                break;
              }
            }
          } catch (e) {
            print('[OCR API] ⚠ Error processing $filename: $e');
          }
        }
      }

      if (outputUrl == null) {
        print('[OCR API] No .md/.txt file found. Using first available file...');
        try {
          final firstEntry = downloadUrls.entries.first;
          final firstFile = firstEntry.value as Map<String, dynamic>?;
          if (firstFile != null) {
            outputUrl = firstFile['file_url'] as String?;
            selectedFilename = firstEntry.key;
            print('[OCR API] Using: $selectedFilename');
          }
        } catch (e) {
          throw Exception('Failed to extract first file URL: $e');
        }
      }

      if (outputUrl == null || outputUrl.isEmpty) {
        throw Exception('Could not find valid download URL from files: ${downloadUrls.keys.toList()}');
      }

      print('[OCR API] Downloading from: $outputUrl');
      print('[OCR API] Selected file: $selectedFilename');

      // Download the actual text content
      final textResponse = await http.get(
        Uri.parse(outputUrl),
      ).timeout(const Duration(seconds: 30));

      print('[OCR API] Text download response: ${textResponse.statusCode}');
      print('[OCR API] Content-Type header: ${textResponse.headers['content-type']}');
      print('[OCR API] Downloaded content length: ${textResponse.bodyBytes.length} bytes');

      if (textResponse.statusCode == 200) {
        // Check if the downloaded file is a ZIP archive
        final contentBytes = textResponse.bodyBytes;

        // ZIP files start with PK magic bytes (0x50 0x4B)
        if (contentBytes.length >= 2 && contentBytes[0] == 0x50 && contentBytes[1] == 0x4B) {
          print('[OCR API] ✓ Downloaded file is a ZIP archive (${contentBytes.length} bytes)');
          return _extractTextFromZip(contentBytes);
        }

        // Not a ZIP, try to treat as text
        var extractedText = textResponse.body;
        if (extractedText.isEmpty) {
          throw Exception('Downloaded file is empty');
        }

        // Check if response looks like valid text or if it's corrupted
        if (extractedText.startsWith('<?xml') || extractedText.startsWith('{') || extractedText.contains('Error')) {
          print('[OCR API] ⚠ Response looks like error XML or JSON, not text content');
        }

        print('[OCR API] ✓ Successfully extracted ${extractedText.length} characters');
        return extractedText;
      } else if (textResponse.statusCode == 404) {
        throw Exception('Download file not found (404): $outputUrl');
      } else {
        throw Exception('Failed to download text: ${textResponse.statusCode} - ${textResponse.body}');
      }
    } catch (e) {
      print('[OCR API] ✗ Text download error: $e');
      rethrow;
    }
  }

  /// Clean markdown content to extract plain text only
  /// Removes: markdown formatting, base64 images, links, code blocks, etc.
  /// Preserves: actual text content and basic structure
  String _cleanMarkdownToPlainText(String markdownContent) {
    try {
      print('[OCR API] Cleaning markdown content...');

      var cleaned = markdownContent;

      // 1. Remove base64 image blocks: ![Image](data:image/jpeg;base64,...)
      cleaned = cleaned.replaceAll(
        RegExp(r'!\[Image\]\(data:image\/[^)]+\)', multiLine: true),
        ''
      );

      // 2. Remove markdown links but keep text: [text](url) → text
      cleaned = cleaned.replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'$1');

      // 3. Remove code blocks (``` ... ```)
      cleaned = cleaned.replaceAll(RegExp(r'```[^`]*```', multiLine: true), '');

      // 4. Remove inline code markers but keep content: `text` → text
      cleaned = cleaned.replaceAll(RegExp(r'`([^`]+)`'), r'$1');

      // 5. Remove markdown headers (##, ###, etc.) but keep the text
      cleaned = cleaned.replaceAll(RegExp(r'^#+\s+', multiLine: true), '');

      // 6. Remove markdown bold/italic but keep text
      // **bold** or __bold__ → bold
      cleaned = cleaned.replaceAll(RegExp(r'\*\*([^\*]+)\*\*'), r'$1');
      cleaned = cleaned.replaceAll(RegExp(r'__([^_]+)__'), r'$1');

      // *italic* or _italic_ → italic
      cleaned = cleaned.replaceAll(RegExp(r'\*([^\*]+)\*'), r'$1');
      cleaned = cleaned.replaceAll(RegExp(r'_([^_]+)_'), r'$1');

      // 6b. Remove markdown footnote references: [^1], [^2], etc.
      cleaned = cleaned.replaceAll(RegExp(r'\[\^[\w]+\]'), '');

      // 6c. Remove footnote definitions: [^1]: content
      cleaned = cleaned.replaceAll(RegExp(r'^\[\^[\w]+\]:\s+.+$', multiLine: true), '');

      // 7. Remove strikethrough: ~~text~~ → text
      cleaned = cleaned.replaceAll(RegExp(r'~~([^~]+)~~'), r'$1');

      // 8. Remove horizontal rules but preserve spacing
      cleaned = cleaned.replaceAll(RegExp(r'^[-*_]{3,}', multiLine: true), '\n');

      // 9. Clean up list markers but keep content
      // - item → item
      // * item → item
      // + item → item
      // 1. item → item
      cleaned = cleaned.replaceAll(RegExp(r'^[\s]*[-*+]\s+', multiLine: true), '');
      cleaned = cleaned.replaceAll(RegExp(r'^[\s]*\d+\.\s+', multiLine: true), '');

      // 10. Clean table formatting but preserve content
      // Remove table header/divider rows (lines with mostly |, -, :)
      final lines = cleaned.split('\n');
      final cleanedLines = <String>[];

      for (final line in lines) {
        // Skip table divider rows (e.g., |---|---|)
        if (RegExp(r'^[\s|:\-]*$').hasMatch(line)) {
          continue;
        }
        // Remove pipe characters from table cells but keep the content
        var cleanedLine = line.replaceAll(RegExp(r'\|\s*'), ' ').trim();

        // Remove any remaining markdown special characters
        cleanedLine = cleanedLine
            .replaceAll(RegExp(r'[\$\^\&\~\`]'), '')  // Remove $, ^, &, ~, `
            .replaceAll(RegExp(r':\s*[a-z]+:\s*'), ' ')  // Remove emoji codes like :smile:
            .replaceAll(RegExp(r'<!.*?>', multiLine: true), '');  // Remove HTML comments

        if (cleanedLine.isNotEmpty) {
          cleanedLines.add(cleanedLine);
        }
      }

      cleaned = cleanedLines.join('\n');

      // 11. Handle paragraph breaks and line continuity
      // First, identify real paragraph breaks (2+ newlines)
      final paragraphs = cleaned.split(RegExp(r'\n\n+'));

      // For each paragraph, join broken lines with spaces
      final cleanedParagraphs = paragraphs.map((para) {
        // Replace single newlines with spaces (join broken lines)
        return para
            .replaceAll(RegExp(r'\n'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')  // Collapse multiple spaces
            .trim();
      }).toList();

      // Join paragraphs back with double newlines
      cleaned = cleanedParagraphs
          .where((p) => p.isNotEmpty)
          .join('\n\n');

      // Final cleanup: remove leading/trailing whitespace
      cleaned = cleaned.trim();

      print('[OCR API] ✓ Markdown cleaned. Final length: ${cleaned.length} characters');
      print('[OCR API] Reduction: ${markdownContent.length} → ${cleaned.length} chars');

      return cleaned;
    } catch (e) {
      print('[OCR API] ⚠ Error cleaning markdown: $e');
      // Return original if parsing fails
      return markdownContent;
    }
  }

  /// Extract text from JSON document format (no embedded images)
  String _extractTextFromJson(String jsonContent) {
    try {
      print('[OCR API] Parsing JSON format...');

      final jsonData = jsonDecode(jsonContent);

      List<String> textSegments = [];

      // Handle different JSON structures from Sarvam
      if (jsonData is Map<String, dynamic>) {
        // Try extracting from 'pages' array
        if (jsonData['pages'] is List) {
          final pages = jsonData['pages'] as List;
          for (var page in pages) {
            if (page is Map<String, dynamic>) {
              // Extract from 'text' field
              if (page['text'] is String) {
                textSegments.add(page['text']);
              }
              // Extract from 'blocks'
              if (page['blocks'] is List) {
                final blocks = page['blocks'] as List;
                for (var block in blocks) {
                  if (block is Map<String, dynamic> && block['text'] is String) {
                    textSegments.add(block['text']);
                  }
                }
              }
            }
          }
        }

        // Fallback: try 'content' field
        if (textSegments.isEmpty && jsonData['content'] is String) {
          textSegments.add(jsonData['content']);
        }

        // Fallback: try 'text' field
        if (textSegments.isEmpty && jsonData['text'] is String) {
          textSegments.add(jsonData['text']);
        }
      }

      if (textSegments.isEmpty) {
        throw Exception('No text content found in JSON: ${jsonData.keys}');
      }

      final extractedText = textSegments.join('\n\n');

      print('[OCR API] ✓ Extracted ${extractedText.length} characters from JSON');
      print('[OCR API] First 300 chars: ${extractedText.substring(0, (extractedText.length < 300 ? extractedText.length : 300))}');

      return extractedText;
    } catch (e) {
      print('[OCR API] ❌ JSON parsing failed: $e');
      rethrow;
    }
  }

  /// Extract text content from a ZIP archive
  /// Sarvam API returns output files as ZIP archives containing JSON/markdown/text files
  String _extractTextFromZip(Uint8List zipBytes) {
    try {
      print('[OCR API] Extracting text from ZIP archive (${zipBytes.length} bytes)...');

      // Decode the ZIP archive
      final archive = ZipDecoder().decodeBytes(zipBytes);
      print('[OCR API] ✓ ZIP decoded successfully');

      print('[OCR API] ZIP contains ${archive.files.length} file(s):');

      // List all files in the archive
      for (var file in archive.files) {
        print('[OCR API]  - ${file.name} (${file.size} bytes, isFile: ${file.isFile})');
      }

      // Find JSON, text, or markdown files (prefer JSON to avoid embedded images)
      ArchiveFile? targetFile;

      // Prefer .json files first (no embedded images = lower cost!)
      print('[OCR API] Looking for .json files (preferred - no embedded images)...');
      for (var file in archive.files) {
        if (!file.isFile) continue;
        if (file.name.endsWith('.json') && !file.name.contains('metadata')) {
          targetFile = file;
          print('[OCR API] ✓ Found JSON file: ${file.name}');
          break;
        }
      }

      // Fallback to .txt files
      if (targetFile == null) {
        print('[OCR API] No JSON files found, looking for .txt files...');
        for (var file in archive.files) {
          if (!file.isFile) continue;
          if (file.name.endsWith('.txt')) {
            targetFile = file;
            print('[OCR API] ✓ Found text file: ${file.name}');
            break;
          }
        }
      }

      // Fallback to .md files
      if (targetFile == null) {
        print('[OCR API] No .txt files found, looking for .md files...');
        for (var file in archive.files) {
          if (!file.isFile) continue;
          if (file.name.endsWith('.md')) {
            targetFile = file;
            print('[OCR API] ✓ Found markdown file: ${file.name}');
            break;
          }
        }
      }

      // If still no file found, use the first file that looks like content
      if (targetFile == null) {
        print('[OCR API] Using first available file...');
        for (var file in archive.files) {
          if (!file.isFile) continue;
          if (file.name.startsWith('__') || file.name.startsWith('.')) continue;
          targetFile = file;
          print('[OCR API] ✓ Using: ${file.name}');
          break;
        }
      }

      if (targetFile == null) {
        throw Exception('No readable files in ZIP. Contents: ${archive.files.map((f) => f.name).toList()}');
      }

      print('[OCR API] Decoding ${targetFile.name}...');
      final fileContent = utf8.decode(targetFile.content as List<int>);

      if (fileContent.isEmpty) {
        throw Exception('File is empty: ${targetFile.name}');
      }

      print('[OCR API] ✓ File decoded (${fileContent.length} bytes)');

      // Parse based on file type
      String cleanedContent = fileContent;

      if (targetFile.name.endsWith('.json')) {
        print('[OCR API] Processing JSON format...');
        cleanedContent = _extractTextFromJson(fileContent);
      } else if (targetFile.name.endsWith('.md')) {
        print('[OCR API] Processing Markdown format...');
        cleanedContent = _cleanMarkdownToPlainText(fileContent);
      }

      print('[OCR API] ✓ Final content: ${cleanedContent.length} characters');
      print('[OCR API] Preview: ${cleanedContent.substring(0, (cleanedContent.length < 300 ? cleanedContent.length : 300))}');

      return cleanedContent;
    } catch (e) {
      print('[OCR API] ❌ ZIP extraction FAILED!');
      print('[OCR API] Error: $e');
      rethrow;
    }
  }

  /// Generate an editable template for manual text entry
  String _generateEditableTemplate() {
    return '''📰 Document Text

[Please paste or type your document text here]

HOW TO USE:
1. If OCR failed, you can manually type or paste your text here
2. Edit and correct the text as needed
3. Tap "Save & Play" to generate audio
4. Audio will play with synchronized text highlighting

FEATURES AVAILABLE:
✓ Text-to-Speech audio generation
✓ Synchronized text highlighting
✓ Text editing and customization
✓ Audio playback controls

NOTE: Real OCR extraction requires:
• Active internet connection
• Valid Sarvam AI API access
• Clear, printed document

This template allows you to still enjoy the audio playback feature while working on OCR functionality.''';
  }

  /// Convert text to speech using Sarvam AI TTS with retry logic
  /// Uses official Sarvam AI Bulbul v3 TTS API
  /// Endpoint: POST /text-to-speech
  Future<String> generateAudioFromText(String text, {String language = 'en-IN'}) async {
    try {
      print('=== SARVAM AI TTS START ===');
      print('Text length: ${text.length}');
      print('Language: $language');

      // Attempt real API with retries
      final audioPath = await _attemptRealTTS(text, language);
      print('=== SARVAM AI TTS END (SUCCESS) ===');
      return audioPath;
    } catch (e) {
      print('[TTS] Real API failed: $e');
      print('[TTS] Falling back to test audio...');

      try {
        // Fallback: generate test audio
        final audioBytes = _generateTestAudioWav();
        final tempDir = await _getTempDir();

        if (kIsWeb) {
          // For web, create data URL for fallback audio
          final base64Audio = base64Encode(audioBytes);
          final url = 'data:audio/wav;base64,$base64Audio';
          print('[TTS] Fallback test audio created as data URL');
          print('=== SARVAM AI TTS END (FALLBACK) ===');
          return url;
        } else {
          // For mobile/desktop, write to file system
          final audioFile = io.File('${tempDir.path}/fallback_audio_${DateTime.now().millisecondsSinceEpoch}.wav');
          await audioFile.writeAsBytes(audioBytes);
          print('[TTS] Fallback test audio created at: ${audioFile.path}');
          print('=== SARVAM AI TTS END (FALLBACK) ===');
          return audioFile.path;
        }
      } catch (fallbackError) {
        print('[TTS] Fallback failed: $fallbackError');
        print('=== SARVAM AI TTS END (ERROR) ===');
        throw Exception('TTS unavailable: $e');
      }
    }
  }

  /// Attempt to generate audio using real Sarvam AI TTS API with retries
  Future<String> _attemptRealTTS(String text, String language, {int maxRetries = 3}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('[TTS] Attempt $attempt/$maxRetries...');

        // Validate text length (max 2500 for bulbul:v3)
        var textToSend = text;
        if (textToSend.length > 2500) {
          print('[TTS] Text exceeds 2500 characters. Truncating to 2500.');
          textToSend = textToSend.substring(0, 2500);
        }

        final requestBody = {
          'text': textToSend,
          'target_language_code': language,
          'speaker': 'shubh',
          'model': 'bulbul:v3',
          'pace': 1.0,
          'temperature': 0.6,
        };

        print('[TTS] Calling API: $_baseUrl/text-to-speech');
        print('[TTS] Text length: ${textToSend.length}, Language: $language');

        final response = await http
            .post(
              Uri.parse('$_baseUrl/text-to-speech'),
              headers: {
                'Content-Type': 'application/json',
                'api-subscription-key': _apiKey,
              },
              body: jsonEncode(requestBody),
            )
            .timeout(const Duration(seconds: 45));

        print('[TTS] Response status: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          if (data['audios'] != null && data['audios'] is List && (data['audios'] as List).isNotEmpty) {
            final audioBase64 = data['audios'][0] as String;
            print('[TTS] Received audio (${audioBase64.length} bytes base64)');

            final audioBytes = base64Decode(audioBase64);
            final tempDir = await _getTempDir();

            if (kIsWeb) {
              // For web, we can't write files directly, so we'll create a data URL
              final base64Audio = base64Encode(audioBytes);
              final url = 'data:audio/wav;base64,$base64Audio';
              print('[TTS] Created data URL for web');
              return url;
            } else {
              // For mobile/desktop, write to file system
              final audioFile = io.File('${tempDir.path}/tts_audio_${DateTime.now().millisecondsSinceEpoch}.wav');
              await audioFile.writeAsBytes(audioBytes);
              print('[TTS] Saved to: ${audioFile.path}');
              return audioFile.path;
            }
          } else {
            throw Exception('Response missing audios array: ${response.body}');
          }
        } else if (response.statusCode == 429) {
          throw Exception('Rate limited (429). Retry in a moment.');
        } else if (response.statusCode == 500 || response.statusCode == 503) {
          throw Exception('Server error (${response.statusCode}). Server may be unavailable.');
        } else {
          throw Exception('API error ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        print('[TTS] Attempt $attempt failed: $e');

        if (attempt == maxRetries) {
          // Last attempt failed
          rethrow;
        }

        // Wait before retry (exponential backoff)
        final delaySeconds = attempt * 2;
        print('[TTS] Retrying in ${delaySeconds}s...');
        await Future.delayed(Duration(seconds: delaySeconds));
      }
    }

    throw Exception('All TTS attempts failed');
  }

  /// Get temporary directory with platform-specific handling
  /// For web, returns a dummy directory since file system access is restricted
  Future<io.Directory> _getTempDir() async {
    if (kIsWeb) {
      // For web, we can't access the real file system
      // Return a temporary directory that will work with web-compatible storage
      // In practice, for web TTS we might want to use blob URLs instead of files
      // But for compatibility with existing code, we'll return a temp directory
      // and handle file writing appropriately elsewhere if needed
      try {
        // Try to get temporary directory anyway - some web implementations may work
        return await getTemporaryDirectory();
      } catch (e) {
        // If that fails, create a dummy directory path
        // Note: This won't actually work for file writing on web,
        // but prevents the MissingPluginException
        return io.Directory('/tmp');
      }
    } else {
      // For mobile/desktop, use the real path_provider
      return await getTemporaryDirectory();
    }
  }

  /// Generate a test WAV file with a simple sine wave tone (440 Hz)
  /// Returns a 3-second mono WAV file at 44.1kHz, 16-bit
  Uint8List _generateTestAudioWav() {
    const sampleRate = 44100;
    const duration = 3; // 3 seconds
    const frequency = 440.0; // 440 Hz (A4 note)
    final numSamples = sampleRate * duration;

    // Create sample data (16-bit PCM)
    final samples = Uint8List(numSamples * 2);
    final samplesView = samples.buffer.asByteData();

    for (int i = 0; i < numSamples; i++) {
      // Generate sine wave
      final angle = 2.0 * 3.14159265359 * frequency * i / sampleRate;
      final sample = (32767 * 0.3 * Math.sin(angle)).toInt(); // 0.3 amplitude to avoid clipping

      // Write as 16-bit little-endian
      samplesView.setInt16(i * 2, sample, Endian.little);
    }

    // Create WAV file structure
    final audioData = Uint8List(44 + samples.length);

    // WAV header
    int offset = 0;

    // "RIFF" chunk descriptor
    audioData[offset++] = 82; // R
    audioData[offset++] = 73; // I
    audioData[offset++] = 70; // F
    audioData[offset++] = 70; // F

    // File size - 8
    final fileSize = 36 + samples.length;
    audioData[offset++] = fileSize & 0xFF;
    audioData[offset++] = (fileSize >> 8) & 0xFF;
    audioData[offset++] = (fileSize >> 16) & 0xFF;
    audioData[offset++] = (fileSize >> 24) & 0xFF;

    // "WAVE"
    audioData[offset++] = 87; // W
    audioData[offset++] = 65; // A
    audioData[offset++] = 86; // V
    audioData[offset++] = 69; // E

    // "fmt " subchunk
    audioData[offset++] = 102; // f
    audioData[offset++] = 109; // m
    audioData[offset++] = 116; // t
    audioData[offset++] = 32; // (space)

    // Subchunk1Size (16 for PCM)
    audioData[offset++] = 16;
    audioData[offset++] = 0;
    audioData[offset++] = 0;
    audioData[offset++] = 0;

    // AudioFormat (1 for PCM)
    audioData[offset++] = 1;
    audioData[offset++] = 0;

    // NumChannels (1 for mono)
    audioData[offset++] = 1;
    audioData[offset++] = 0;

    // SampleRate
    audioData[offset++] = sampleRate & 0xFF;
    audioData[offset++] = (sampleRate >> 8) & 0xFF;
    audioData[offset++] = (sampleRate >> 16) & 0xFF;
    audioData[offset++] = (sampleRate >> 24) & 0xFF;

    // ByteRate
    final byteRate = sampleRate * 2; // sampleRate * numChannels * bytesPerSample
    audioData[offset++] = byteRate & 0xFF;
    audioData[offset++] = (byteRate >> 8) & 0xFF;
    audioData[offset++] = (byteRate >> 16) & 0xFF;
    audioData[offset++] = (byteRate >> 24) & 0xFF;

    // BlockAlign (numChannels * bytesPerSample)
    audioData[offset++] = 2;
    audioData[offset++] = 0;

    // BitsPerSample
    audioData[offset++] = 16;
    audioData[offset++] = 0;

    // "data" subchunk
    audioData[offset++] = 100; // d
    audioData[offset++] = 97; // a
    audioData[offset++] = 116; // t
    audioData[offset++] = 97; // a

    // Subchunk2Size
    audioData[offset++] = samples.length & 0xFF;
    audioData[offset++] = (samples.length >> 8) & 0xFF;
    audioData[offset++] = (samples.length >> 16) & 0xFF;
    audioData[offset++] = (samples.length >> 24) & 0xFF;

    // Copy audio data
    audioData.setRange(offset, offset + samples.length, samples);

    return audioData;
  }
}
