# Sarvam AI API - Complete Correction Guide

## CRITICAL FINDINGS FROM OFFICIAL DOCUMENTATION

Your current implementation has **fundamental endpoint errors**. Below is the exact, correct API structure from official Sarvam AI documentation.

---

## 1. DOCUMENT INTELLIGENCE (OCR) API

### ❌ WRONG ENDPOINTS (Current Implementation)
```
POST /document-intelligence/jobs
POST /document-intelligence/jobs/{jobId}/upload
POST /document-intelligence/jobs/{jobId}/start
GET /document-intelligence/jobs/{jobId}
GET /document-intelligence/jobs/{jobId}/output
```

### ✅ CORRECT ENDPOINTS (Official Docs)
```
POST /doc-digitization/job/v1
POST /doc-digitization/job/v1/upload-files
POST /doc-digitization/job/v1/{job_id}/start
GET /doc-digitization/job/v1/{job_id}/status
POST /doc-digitization/job/v1/{job_id}/download-files
```

### ✅ CORRECT WORKFLOW (5 Steps)

#### Step 1: Create Job
```bash
POST https://api.sarvam.ai/doc-digitization/job/v1
Header: api-subscription-key: YOUR_KEY
Content-Type: application/json

{
  "language": "te-IN"  # NOTE: Must be "te-IN", not "te"!
  "output_format": "md"  # or "html" or "json"
}

Response (202):
{
  "job_id": "uuid-string",
  "job_state": "Accepted"
}
```

#### Step 2: Get Upload URLs & Upload File
```bash
POST https://api.sarvam.ai/doc-digitization/job/v1/upload-files
Header: api-subscription-key: YOUR_KEY
Content-Type: application/json

{
  "job_id": "uuid-from-step1",
  "files": ["document.jpg"]  # Must be exactly 1 file
}

Response (200):
{
  "job_id": "uuid",
  "upload_urls": {
    "document.jpg": {
      "file_url": "https://presigned-url...",
      "request_headers": {...}
    }
  }
}

# Then PUT your file content to the presigned URL
PUT https://presigned-url (from response)
Content-Type: image/jpeg
[binary file data]
```

#### Step 3: Start Processing
```bash
POST https://api.sarvam.ai/doc-digitization/job/v1/{job_id}/start
Header: api-subscription-key: YOUR_KEY
Content-Type: application/json
{}

Response (202):
{
  "job_id": "uuid",
  "job_state": "Accepted",
  "job_details": [...]
}
```

#### Step 4: Poll Job Status
```bash
GET https://api.sarvam.ai/doc-digitization/job/v1/{job_id}/status
Header: api-subscription-key: YOUR_KEY

Response (200):
{
  "job_id": "uuid",
  "job_state": "Completed",  # Can be: Accepted, Pending, Running, Completed, PartiallyCompleted, Failed
  "job_details": [
    {
      "state": "Completed",
      "total_pages": 5,
      "pages_processed": 5,
      "pages_succeeded": 5,
      "pages_failed": 0
    }
  ]
}
```

#### Step 5: Download Results
```bash
POST https://api.sarvam.ai/doc-digitization/job/v1/{job_id}/download-files
Header: api-subscription-key: YOUR_KEY
Content-Type: application/json
{}

Response (200):
{
  "job_id": "uuid",
  "download_urls": {
    "document_output.md": {
      "file_url": "https://presigned-download-url...",
      "file_metadata": {
        "contentType": "text/markdown",
        "fileSizeBytes": 1024
      }
    }
  }
}

# Then GET the file from the presigned URL
GET https://presigned-download-url
# Returns the actual text content
```

---

## 2. TEXT-TO-SPEECH API

### ✅ CORRECT ENDPOINT
```
POST https://api.sarvam.ai/text-to-speech
Header: api-subscription-key: YOUR_KEY
Content-Type: application/json

Request:
{
  "text": "Your text here",
  "target_language_code": "en-IN",  # en-IN, hi-IN, te-IN, etc.
  "speaker": "shubh",              # 30+ speaker options
  "model": "bulbul:v3",            # Latest model
  "pace": 1.0,                     # 0.5 to 2.0 for v3
  "temperature": 0.6,              # 0.01 to 2.0
  "speech_sample_rate": 24000      # or 32000, 44100, 48000
}

Response (200):
{
  "request_id": "uuid",
  "audios": [
    "base64-encoded-audio-data"
  ]
}
```

### ❌ KEY DIFFERENCE FROM YOUR CODE
- Language code must be exact format: `en-IN`, `hi-IN`, `te-IN`, etc.
- For Telugu speech: use `te-IN` in both Document Intelligence AND Text-to-Speech
- No `text-to-speech/convert` endpoint - just `/text-to-speech`

---

## 3. AUTHENTICATION - SINGLE API KEY FOR ALL SERVICES

### ✅ API KEY USAGE
**ONE API KEY works for ALL services:**
- Document Intelligence ✓
- Text-to-Speech ✓  
- Speech-to-Text ✓
- All other Sarvam APIs ✓

**Header Format (Same for all):**
```
api-subscription-key: YOUR_SINGLE_API_KEY
```

**NO different keys needed** - all services share the same authentication.

---

## 4. LANGUAGE CODES (BCP-47 Format)

### For Document Intelligence (OCR):
```
hi-IN   - Hindi
en-IN   - English
bn-IN   - Bengali
te-IN   - Telugu ← YOUR CASE
ta-IN   - Tamil
kn-IN   - Kannada
ml-IN   - Malayalam
mr-IN   - Marathi
gu-IN   - Gujarati
pa-IN   - Punjabi
ur-IN   - Urdu
as-IN   - Assamese
[+ 11 more Indian languages]
```

### For Text-to-Speech:
```
Same as above (11 languages total)
```

---

## 5. KEY CONSTRAINTS TO REMEMBER

### Document Intelligence:
- **Max file size:** 200 MB
- **Supported formats:** PDF, JPEG, PNG, ZIP (with images)
- **Max pages:** 10
- **Presigned URL valid for:** Limited time (use immediately)
- **Job states:** Accepted → Pending → Running → Completed

### Text-to-Speech (bulbul:v3):
- **Max text:** 2500 characters (NOT 1500!)
- **Supported output formats:** WAV, MP3, Linear16, Mulaw, Alaw, Opus, FLAC, AAC
- **Default:** WAV, 24kHz, base64-encoded in response
- **Speaker count:** 30+ voices (both male and female)

---

## 6. CRITICAL IMPLEMENTATION CHANGES NEEDED

### File Upload Change (Step 2 is DIFFERENT):
**OLD (WRONG):**
```dart
// Direct multipart upload - WRONG!
var request = http.MultipartRequest(
  'POST',
  Uri.parse('$_baseUrl/document-intelligence/jobs/$jobId/upload'),
);
request.files.add(http.MultipartFile.fromBytes('file', imageBytes));
```

**NEW (CORRECT):**
```dart
// Step 1: Get presigned URLs
final uploadResponse = await http.post(
  Uri.parse('$_baseUrl/doc-digitization/job/v1/upload-files'),
  headers: {'api-subscription-key': _apiKey, 'Content-Type': 'application/json'},
  body: jsonEncode({'job_id': jobId, 'files': ['document.jpg']}),
);

final uploadUrls = jsonDecode(uploadResponse.body)['upload_urls'];
final presignedUrl = uploadUrls['document.jpg']['file_url'];

// Step 2: Upload to presigned URL
final putResponse = await http.put(
  Uri.parse(presignedUrl),
  headers: {'Content-Type': 'image/jpeg'},
  body: imageBytes,
);
```

### Status Polling Change:
**OLD (WRONG):**
```dart
final response = await http.get(
  Uri.parse('$_baseUrl/document-intelligence/jobs/$jobId'),
  headers: {'api-subscription-key': _apiKey},
);
final state = data['job_state'] ?? data['state'] ?? 'processing';
```

**NEW (CORRECT):**
```dart
final response = await http.get(
  Uri.parse('$_baseUrl/doc-digitization/job/v1/$jobId/status'),
  headers: {'api-subscription-key': _apiKey},
);
final state = data['job_state'];  // Only one field name
if (state == 'Completed' || state == 'PartiallyCompleted') {
  // Job done - now get download URLs
}
```

### Text Extraction Change:
**OLD (WRONG):**
```dart
// Tried to get text directly - WRONG!
final response = await http.get(
  Uri.parse('$_baseUrl/document-intelligence/jobs/$jobId/output'),
);
```

**NEW (CORRECT):**
```dart
// Step 1: Get download URLs
final downloadResponse = await http.post(
  Uri.parse('$_baseUrl/doc-digitization/job/v1/$jobId/download-files'),
  headers: {'api-subscription-key': _apiKey, 'Content-Type': 'application/json'},
  body: jsonEncode({}),
);

// Step 2: Download from presigned URLs
final downloadUrls = jsonDecode(downloadResponse.body)['download_urls'];
final outputUrl = downloadUrls['document_output.md']['file_url'];  // or .json/.html

final textResponse = await http.get(Uri.parse(outputUrl));
final extractedText = textResponse.body;  // This is the actual text content
```

---

## 7. SOURCES

- [Sarvam Vision Documentation](https://docs.sarvam.ai/api-reference-docs/getting-started/models/sarvam-vision)
- [Create Document Intelligence Job](https://docs.sarvam.ai/api-reference-docs/document-intelligence/initialise)
- [Get Document Intelligence Upload URLs](https://docs.sarvam.ai/api-reference-docs/document-intelligence/get-upload-links)
- [Start Document Intelligence Job](https://docs.sarvam.ai/api-reference-docs/document-intelligence/start)
- [Get Document Intelligence Job Status](https://docs.sarvam.ai/api-reference-docs/document-intelligence/get-status)
- [Get Document Intelligence Download URLs](https://docs.sarvam.ai/api-reference-docs/document-intelligence/get-download-links)
- [Text-to-Speech REST API](https://docs.sarvam.ai/api-reference-docs/api-guides-tutorials/text-to-speech/rest-api)
- [Text-to-Speech Endpoint](https://docs.sarvam.ai/api-reference-docs/text-to-speech/convert)
- [Authentication Guide](https://docs.sarvam.ai/api-reference-docs/authentication)

---

## SUMMARY: What Was Wrong

| Aspect | Your Implementation | Correct Implementation |
|--------|-------------------|----------------------|
| **Create Job Endpoint** | `/document-intelligence/jobs` | `/doc-digitization/job/v1` |
| **Upload Endpoint** | `/document-intelligence/jobs/{id}/upload` | `/doc-digitization/job/v1/upload-files` |
| **Status Endpoint** | `/document-intelligence/jobs/{id}` | `/doc-digitization/job/v1/{id}/status` |
| **Language Code** | `'te'` | `'te-IN'` |
| **Text Extraction** | Direct from status | Via presigned download URLs |
| **File Upload Method** | Multipart POST | Presigned URL PUT |
| **API Keys** | Assumed different | Same key for all services |

