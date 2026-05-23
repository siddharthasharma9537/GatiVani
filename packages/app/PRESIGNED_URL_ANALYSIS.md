# Azure Blob Storage Presigned URL Upload - Analysis

## Current Failure: 400 Bad Request
The presigned URL upload is failing with a 400 error from Azure Blob Storage.

## What's Happening:
1. ✅ **Create Job** (POST /doc-digitization/job/v1) → 202 Accepted
2. ✅ **Get Upload URLs** (POST /doc-digitization/job/v1/upload-files) → 200 OK (returns presigned URL)
3. ❌ **Upload to Presigned URL** (PUT <presigned-url>) → 400 Bad Request ← **PROBLEM HERE**

## Current Request Headers:
```dart
headers: {
  'Content-Type': 'image/jpeg',
  'Content-Length': imageBytes.length.toString(),
  'x-ms-blob-type': 'BlockBlob',
}
```

## Potential Issues from Azure Docs:

### Issue 1: Excessive Headers
Azure Blob Storage presigned URLs are typically **restrictive** about which headers you can send. 
The presigned URL might only allow specific headers that were included during URL generation.

**Solution**: Try removing extra headers. The response from `/upload-files` might specify allowed headers in the `request_headers` field.

Currently we're ignoring `request_headers` from the response!

### Issue 2: Case Sensitivity
Azure header names might be case-sensitive or have specific format requirements.
- ✗ `x-ms-blob-type` (current)
- ✓ Could need different casing or removal

### Issue 3: Missing Required Header from Response
The `/upload-files` response includes:
```json
"upload_urls": {
  "document.jpg": {
    "file_url": "...",
    "request_headers": {...}  ← WE'RE NOT USING THESE!
  }
}
```

**This is likely the issue!** The `request_headers` from the response specify exactly which headers to send with the PUT request.

### Issue 4: Content-Length Format
Azure might require `Content-Length` in a specific format or it might be pre-set in the presigned URL.

## IMMEDIATE FIX (High Probability):

Use the `request_headers` from the response instead of hardcoding headers:

```dart
// Step 1: Get presigned URLs
final urlsData = jsonDecode(uploadUrlsResponse.body);
final uploadUrls = urlsData['upload_urls'] as Map<String, dynamic>;
final documentUrl = uploadUrls['document.jpg'] as Map<String, dynamic>;

// ← NEW: Get the request headers from the response
final requestHeaders = documentUrl['request_headers'] as Map<String, dynamic>;
final presignedUrl = documentUrl['file_url'] as String;

// Step 2: Use the provided headers
final putResponse = await http.put(
  Uri.parse(presignedUrl),
  headers: {
    ...?requestHeaders,  // Use headers from response
    'Content-Type': 'image/jpeg',
    'Content-Length': imageBytes.length.toString(),
  },
  body: imageBytes,
).timeout(const Duration(seconds: 60));
```

## What the Sarvam API Documentation Says:
From the official docs, the upload workflow is:
1. POST /doc-digitization/job/v1/upload-files with { job_id, files: ["document.jpg"] }
2. Response includes presigned URLs WITH request_headers
3. Use those exact headers when PUTting to the presigned URL

**We were using custom headers instead of the API-provided headers!**

## Test Plan:
1. Rebuild with enhanced logging
2. Capture the `request_headers` value from the upload-files response
3. Use those headers in the PUT request
4. Test again

This is likely a 5-minute fix once we see what headers are being provided.
