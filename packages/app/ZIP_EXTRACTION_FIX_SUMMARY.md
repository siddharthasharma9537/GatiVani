# ZIP Extraction Fix - Complete Summary

## Problem
The Sarvam AI API was returning output files as ZIP archives (document.zip) containing the actual markdown/text content. The previous implementation was treating the ZIP bytes as text, resulting in corrupted/gibberish characters when displayed.

## Root Cause
The `/doc-digitization/job/v1/{job_id}/download-files` endpoint returns presigned URLs for ZIP archives, not plain text files. When we downloaded and displayed the binary ZIP data as text, it appeared as corrupted gibberish.

## Solution Implemented

### 1. Added Archive Dependency
**File**: `pubspec.yaml`
```yaml
archive: ^3.4.0
```
This provides ZIP/archive extraction capabilities.

### 2. Import Archive Library
**File**: `lib/services/sarvam_ai_service.dart`
```dart
import 'package:archive/archive.dart';
```

### 3. ZIP Detection in Download
Modified `_downloadAndExtractText()` method to detect ZIP files by checking the PK magic bytes (0x50 0x4B):

```dart
// Check if the downloaded file is a ZIP archive
final contentBytes = textResponse.bodyBytes;

// ZIP files start with PK magic bytes (0x50 0x4B)
if (contentBytes.length >= 2 && contentBytes[0] == 0x50 && contentBytes[1] == 0x4B) {
  print('[OCR API] ✓ Downloaded file is a ZIP archive (${contentBytes.length} bytes)');
  return _extractTextFromZip(contentBytes);
}
```

### 4. New ZIP Extraction Method
Added `_extractTextFromZip()` method that:
- Decodes the ZIP archive using `ZipDecoder()`
- Lists all files in the archive
- Prioritizes `.md` (markdown) files first, then `.txt`, then any readable file
- Extracts the file content as UTF-8 text
- Returns the actual readable text content

```dart
String _extractTextFromZip(Uint8List zipBytes) {
  try {
    print('[OCR API] Extracting text from ZIP archive...');
    
    // Decode the ZIP archive
    final archive = ZipDecoder().decodeBytes(zipBytes);
    
    print('[OCR API] ZIP contains ${archive.files.length} file(s):');
    
    // List all files
    for (var file in archive.files) {
      print('[OCR API]  - ${file.name} (${file.size} bytes)');
    }
    
    // Find .md or .txt files and extract content
    ArchiveFile? targetFile;
    
    // Prefer .md files first
    for (var file in archive.files) {
      if (!file.isFile) continue;
      if (file.name.endsWith('.md')) {
        targetFile = file;
        print('[OCR API] ✓ Found markdown file: ${file.name}');
        break;
      }
    }
    
    // ... (fallback logic for .txt and other files)
    
    // Extract file content as UTF-8 text
    final fileContent = utf8.decode(targetFile.content as List<int>);
    
    print('[OCR API] ✓ Extracted ${fileContent.length} characters from ${targetFile.name}');
    return fileContent;
  } catch (e) {
    print('[OCR API] ✗ ZIP extraction error: $e');
    rethrow;
  }
}
```

## How It Works

### Complete OCR Workflow (Fixed)
1. **Create Job** (POST `/doc-digitization/job/v1`)
   - Request: language='te-IN', output_format='md'
   - Response: 202 Accepted with job_id

2. **Upload File** (POST `/doc-digitization/job/v1/upload-files`)
   - Get presigned Azure URLs
   - PUT image to presigned URL with x-ms-blob-type header
   - Response: 201 Created

3. **Start Processing** (POST `/doc-digitization/job/v1/{jobId}/start`)
   - Response: 202 Accepted

4. **Poll Status** (GET `/doc-digitization/job/v1/{jobId}/status`)
   - Wait for job_state = 'Completed' or 'PartiallyCompleted'
   - Polling interval: 1 second
   - Max retries: 120 (2 minutes)

5. **Download & Extract** (NEW LOGIC)
   - Request download URLs: POST `/doc-digitization/job/v1/{jobId}/download-files`
   - Download presigned ZIP file
   - **Detect ZIP** by checking PK magic bytes
   - **Extract ZIP** to get markdown/text content
   - Return readable text (not binary gibberish!)

## Expected Log Output

```
[OCR API] Requesting download URLs for job: <jobId>
[OCR API] Download URLs response: 200
[OCR API] Download URLs body length: ...
[OCR API] Selected file: document.zip
[OCR API] Text download response: 200
[OCR API] Downloaded content length: 113152 bytes
[OCR API] ✓ Downloaded file is a ZIP archive (113152 bytes)
[OCR API] Extracting text from ZIP archive...
[OCR API] ZIP contains 1 file(s):
[OCR API]  - document.md (45678 bytes)
[OCR API] ✓ Found markdown file: document.md
[OCR API] ✓ Extracted 45678 characters from document.md
[OCR API] First 200 chars: # Newspaper Title

[News Article Content...
```

## Testing
Run the build commands:
```bash
cd ~/Projects/gativani-app && \
flutter clean && \
flutter pub get && \
flutter build apk --debug && \
adb install -r build/app/outputs/flutter-apk/app-debug.apk && \
adb logcat -c
```

Then:
1. Open GatiVani app on device
2. Go to "Upload Content"
3. Select a newspaper image
4. Watch terminal for OCR logs
5. Check if extracted text is readable (not corrupted)

## Files Modified
- `pubspec.yaml` - Added archive dependency
- `lib/services/sarvam_ai_service.dart`:
  - Imported `package:archive/archive.dart`
  - Modified `_downloadAndExtractText()` to detect ZIP
  - Added new `_extractTextFromZip()` method

## Success Criteria
- ✓ ZIP archive is detected from downloaded bytes
- ✓ Archive is decoded without errors
- ✓ Markdown/text files are extracted correctly
- ✓ Content is returned as readable text
- ✓ OCR extraction works end-to-end
- ✓ Text can be used for TTS without corruption

## Next Steps (If Needed)
1. Test with various newspaper images (Telugu, English, mixed)
2. Verify extracted text quality
3. Test TTS generation from extracted text
4. Verify text highlighting during audio playback
5. Handle edge cases (corrupt ZIP, missing files, etc.)
