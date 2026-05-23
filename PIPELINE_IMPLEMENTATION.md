# GatiVani 3-Stage Processing Pipeline - Implementation Complete

## Overview
The document processing pipeline has been fully implemented with three stages:
1. **Stage 1**: Pre-Processing (Layout analysis & content extraction)
2. **Stage 2**: Data Cleaning & Reformatting (Image & text optimization)
3. **Stage 3**: Post-Processing & Verification (Quality assurance & audio generation)

## Architecture

```
User Upload (Image/PDF)
    ↓
Stage 1: Pre-Processing (stage1-preprocessing.js)
├── preprocessDocument() - Gemini Vision layout analysis
│   ├── Article boundary detection
│   ├── Advertisement detection
│   ├── Cover image identification
│   └── Quality metrics (readability, clarity)
├── extractArticleContent() - Text extraction
│   ├── Main article body extraction
│   ├── Original language preservation
│   └── Metadata extraction (publication, date, author)
    ↓
Stage 2: Data Cleaning & Reformatting (stage2-datacleaning.js)
├── processArticleImage() - Image quality analysis
│   ├── Blur detection
│   ├── Readability assessment
│   ├── Format & compression recommendations
│   └── Resolution optimization
├── cleanArticleText() - Text cleaning
│   ├── OCR error correction via Gemini
│   ├── Paragraph structure preservation
│   ├── Whitespace normalization
│   └── Artifact removal ([Image N], metadata pipes, etc.)
└── enhanceTextForReadability() - Text enhancement
    ├── Punctuation normalization
    ├── Format consistency
    ├── Section breaks
    └── Original content preservation
    ↓
Stage 3: Post-Processing & Verification (stage3-postprocessing.js)
├── verifyTextQuality() - Text verification
│   ├── Completeness check
│   ├── Readability scoring
│   ├── OCR artifact detection
│   ├── Structure assessment
│   └── Quality verdict (pass|review|fail)
├── verifyImageQuality() - Image verification
│   ├── File size check
│   ├── Resolution validation
│   ├── Blur assessment
│   ├── Contrast evaluation
│   └── Quality verdict
├── generateArticleAudio() - TTS audio generation
│   ├── Azure Text-to-Speech integration
│   ├── Natural voice selection (te-IN-NireshaNormal)
│   ├── Base64 data URL generation
│   └── Audio validation
└── calculateFinalQualityScore() - Quality aggregation
    ├── Text score (50% weight)
    ├── Image score (30% weight)
    ├── Audio score (20% weight)
    ├── Final verdict
    └── Ready for user flag
    ↓
Final Output
├── Article text (enhanced)
├── Article image
├── Natural audio (data URL)
├── Quality metrics
└── Processing metadata
```

## Service Files

### Stage 1: Pre-Processing
**File**: `packages/core/src/services/stage1-preprocessing.js`

**Functions**:
- `preprocessDocument(fileBuffer, mimeType, filename)`: Analyzes document layout using Gemini Vision
  - Returns: JSON analysis with hasCoverImage, adSpaces, articleBoundaries, quality, metadata
  - Gemini Vision analyzes the visual layout to identify content structure
  - Includes: publication name, date, author detection

- `extractArticleContent(stage1Result)`: Extracts article text
  - Returns: Article text with metadata and quality indicators
  - Explicitly preserves original language without translation
  - Maintains punctuation, formatting, and paragraph structure

**Example Response**:
```json
{
  "success": true,
  "analysis": {
    "hasCoverImage": true,
    "coverImageLocation": "top",
    "adSpaces": [{ "location": "right", "type": "classified" }],
    "articleBoundaries": { "startLine": 5, "endLine": 45 },
    "quality": {
      "readability": "good",
      "imageQuality": "high",
      "textClarity": "clear"
    },
    "metadata": {
      "publication": "Eenadu",
      "date": "2026-05-23",
      "author": "Some Author"
    }
  },
  "articleContent": {
    "success": true,
    "articleText": "Full extracted article text...",
    "metadata": { "publication": "Eenadu", ... },
    "quality": { "readability": "good", ... }
  }
}
```

### Stage 2: Data Cleaning & Reformatting
**File**: `packages/core/src/services/stage2-datacleaning.js`

**Functions**:
- `processArticleImage(imageBuffer, quality)`: Analyzes image for optimization
  - Returns: Quality analysis with blur assessment, format recommendations
  - Uses Gemini Vision to detect blur level and readability
  - Recommends compression format (JPEG vs WebP) and level

- `cleanArticleText(articleText)`: Cleans OCR errors while preserving structure
  - Removes OCR artifacts and markers
  - Normalizes whitespace (preserves paragraph breaks)
  - Uses Gemini for intelligent OCR error correction
  - Returns: Original length, cleaned length, cleaned text

- `enhanceTextForReadability(text, fontFamily)`: Enhances text for display
  - Fixes punctuation spacing
  - Ensures consistent quote marks
  - Adds logical section breaks
  - Returns: Enhanced text maintaining 100% fidelity to original content

**Example Response**:
```json
{
  "success": true,
  "stage2": {
    "image": {
      "analysis": {
        "clarity": "clear",
        "readability": "good",
        "recommendedFormat": "jpeg",
        "compressionLevel": 7,
        "isOptimizable": true
      },
      "sizeBytes": 125000
    },
    "text": {
      "original": "Original extracted text...",
      "cleaned": "Cleaned text without OCR errors...",
      "enhanced": "Enhanced text for readability...",
      "originalLength": 5000,
      "cleanedLength": 4950,
      "enhancedLength": 4950
    },
    "quality": {
      "imageReadability": "good",
      "textCleaned": true,
      "textEnhanced": true
    }
  }
}
```

### Stage 3: Post-Processing & Verification
**File**: `packages/core/src/services/stage3-postprocessing.js`

**Functions**:
- `verifyTextQuality(text)`: Verifies text quality
  - Returns: Completeness, readability, OCR artifacts, structure scores
  - Verdict: pass | review | fail
  - Quality score: 0-100

- `verifyImageQuality(imageBuffer)`: Verifies image quality
  - Returns: File size check, resolution, blur assessment, contrast evaluation
  - Verdict: pass | review | fail
  - Quality score: 0-100

- `generateArticleAudio(text, language)`: Generates natural audio
  - Uses Azure Text-to-Speech with natural voices
  - Returns: Data URL with base64-encoded MP3 audio
  - Language support: te-IN (Telugu), hi-IN (Hindi), en-IN (English)

- `calculateFinalQualityScore(textVerif, imageVerif, audioSuccess)`: Aggregates quality
  - Text score (50% weight)
  - Image score (30% weight)
  - Audio score (20% weight)
  - Final score: 0-100, Verdict: pass | review | fail

**Example Response**:
```json
{
  "success": true,
  "stage3": {
    "textVerification": {
      "isComplete": true,
      "completenessScore": 95,
      "readabilityScore": 92,
      "hasOCRArtifacts": false,
      "structureScore": 90,
      "hasContentGaps": false,
      "overallQualityScore": 92,
      "verdict": "pass"
    },
    "imageVerification": {
      "sizeBytes": 125000,
      "sizeOK": true,
      "resolution": "high",
      "resolutionOK": true,
      "isSharp": true,
      "contrast": "good",
      "overallScore": 95,
      "verdict": "pass"
    },
    "audio": {
      "success": true,
      "audioUrl": "data:audio/mpeg;base64,//NExAA..."
    },
    "qualityScore": {
      "textScore": 92,
      "imageScore": 95,
      "audioScore": 100,
      "finalScore": 94,
      "verdict": "pass",
      "readyForUser": true
    }
  }
}
```

## API Endpoint: `/api/documents/process`

### Request
```bash
POST /api/documents/process
Content-Type: multipart/form-data
X-Subscription-Tier: premium

{
  "document": <file>
}
```

### Response (Backward Compatible)
```json
{
  "ok": true,
  "title": "Article Title",
  "summary": "First part of enhanced article text...",
  "category": "News",
  "storageUrl": "https://backend/uploads/timestamp_filename.pdf",
  "audioUrl": "data:audio/mpeg;base64,//NExAA...",
  "model": "gemini-2.0-flash-thinking-exp-01-21",
  "subscription": { "tier": "premium", "active": true },
  "limits": { "maxPages": 50, "totalPages": 1, "processedPages": 1, "truncated": false },
  "pipeline": {
    "stage1": {
      "success": true,
      "analysis": { "hasCoverImage": true, ... },
      "metadata": { "publication": "Eenadu", ... }
    },
    "stage2": {
      "success": true,
      "qualityMetrics": { "imageReadability": "good", ... }
    },
    "stage3": {
      "success": true,
      "qualityScore": { "finalScore": 94, "verdict": "pass", ... }
    }
  }
}
```

## Key Features

### 1. Language Preservation
- All stages explicitly preserve original language (Telugu, Hindi, etc.)
- No translation or rewriting of content
- Original punctuation and formatting maintained
- Cultural and linguistic nuances preserved

### 2. OCR Error Handling
- Stage 1: Initial extraction with Gemini Vision
- Stage 2: Intelligent OCR error correction using Gemini
- Stage 3: Verification to ensure no remaining artifacts
- Three-layer quality assurance

### 3. Image Processing
- Gemini Vision-based analysis (no local image processing needed)
- Blur detection and clarity assessment
- Format and compression recommendations
- Quality scoring for optimization

### 4. Quality Scoring
- Multi-factor scoring system
- Text quality: Completeness, readability, structure
- Image quality: Size, resolution, clarity
- Audio quality: Successful generation
- Weighted aggregation: Text (50%) + Image (30%) + Audio (20%)
- Ready-for-user flag based on thresholds

### 5. Audio Generation
- Azure Text-to-Speech integration
- Natural voices (te-IN-NireshaNormal for Telugu)
- Base64 data URL for direct embedding
- Automatic caching via Azure TTS backend

### 6. Error Handling
- Graceful fallbacks at each stage
- Comprehensive error logging
- Returns partial results when individual stages fail
- Never blocks user from accessing extracted content

## Performance Considerations

### Processing Time
- Stage 1: 2-5 seconds (Gemini Vision API calls)
- Stage 2: 3-8 seconds (Text cleaning via Gemini)
- Stage 3: 4-10 seconds (Verification + audio generation)
- **Total**: ~10-25 seconds for typical article

### Optimization Strategies
1. **Parallel Processing**: Stages can be optimized to run in parallel where possible
2. **Caching**: Azure TTS results cached automatically
3. **Gemini Batching**: Multiple analyses batched in single API call
4. **Regional Endpoints**: Azure TTS uses region-specific endpoints (Central India)

## Configuration

### Environment Variables
```bash
# Gemini API
GEMINI_API_KEY=your-key
GEMINI_MODEL=gemini-2.0-flash-thinking-exp-01-21

# Azure TTS
AZURE_TTS_KEY=your-key
AZURE_TTS_REGION=centralindia

# Backend
PUBLIC_ORIGIN=http://localhost:8788
```

### Subscription Tiers
- **Free**: 5 pages/month
- **Standard**: 50 pages/month
- **Premium**: 500 pages/month (unlimited daily)

## Testing

### Test with Local File
```bash
curl -X POST http://localhost:8788/api/documents/process \
  -F "document=@sample.pdf" \
  -H "X-Subscription-Tier: premium"
```

### Test with Image
```bash
curl -X POST http://localhost:8788/api/documents/process \
  -F "document=@article.jpg" \
  -H "X-Subscription-Tier: premium"
```

## Monitoring & Debugging

### Console Logs
Each stage logs progress with `[Stage1]`, `[Stage2]`, `[Stage3]` prefixes:
```
[process] ▶ Stage 1: Pre-Processing
[Stage1] Analyzing document layout and separating content...
[Stage1] Layout analysis complete: {...}
[Stage1] Extracting article content...
[process] ▶ Stage 2: Data Cleaning
[Stage2] Processing article image...
[Stage2] Image quality analysis: {...}
[process] ▶ Stage 3: Post-Processing
[Stage3] Verifying text quality...
[Stage3] Final quality score: {...}
```

### Quality Score Interpretation
- **80-100**: Pass - Ready for user
- **60-79**: Review - May need manual verification
- **< 60**: Fail - Recommend manual review or reprocessing

## Future Enhancements

### Phase 2
- [ ] Local image processing with Sharp library (resizing, optimization)
- [ ] Caching layer for repeated documents
- [ ] Batch processing for multiple documents
- [ ] Custom quality thresholds per subscription tier

### Phase 3
- [ ] Multi-language support with language detection
- [ ] Custom font rendering for Mallanna and other scripts
- [ ] Document type classification (news, legal, technical, etc.)
- [ ] Specialized processing pipelines by document type

### Phase 4
- [ ] User feedback integration for quality improvement
- [ ] ML-based OCR error prediction and correction
- [ ] Advanced audio generation (speaker selection, emotion detection)
- [ ] Document versioning and history tracking

## Backward Compatibility

The updated `/api/documents/process` endpoint maintains backward compatibility:
- All original response fields are preserved
- New `audioUrl` field added (may be empty if audio generation fails)
- New `pipeline` field added (optional detailed metrics)
- Mobile app continues to work without changes
- Existing clients can ignore new fields

## Migration Guide

### For Mobile App
No changes required. The app will automatically benefit from:
1. Better text cleaning and paragraph preservation
2. Natural audio via Azure TTS
3. Enhanced article content
4. Quality metrics in response

### For API Consumers
Optional: Check `pipeline.*.success` fields to understand processing status.
```dart
final response = await http.post(...);
final data = json.decode(response.body);

// Old way (still works)
final audioUrl = data['audioUrl'];

// New way (with details)
final pipelineSuccess = data['pipeline']['stage3']['success'];
final qualityScore = data['pipeline']['stage3']['qualityScore'];
```
