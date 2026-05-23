# Sarvam AI Integration - Technical Details

## Overview
Complete replacement of Gemini Vision and TTS with Sarvam AI services, providing Indian language optimization and significantly reduced costs.

## Service Architecture

### Document Processing Pipeline

```
Document Upload
     ↓
[Stage 1: Pre-Processing]
   ├─ Sarvam OCR (text extraction)
   └─ Returns: extracted text, confidence score
     ↓
[Stage 2: Data Cleaning]
   ├─ Text cleaning & normalization
   ├─ Image analysis
   └─ Text enhancement
     ↓
[Stage 3: Post-Processing]
   ├─ Quality verification
   ├─ Sarvam TTS (audio generation)
   └─ Returns: audio data URL
     ↓
Response with audio + metadata
```

## Service Implementations

### 1. Sarvam Vision (OCR)

**File**: `packages/core/src/services/sarvam-vision-service.js`

```javascript
import { SarvamAIClient } from "sarvamai";

export async function performOCR(imageBuffer, language = "te") {
  const client = new SarvamAIClient({
    apiSubscriptionKey: process.env.SARVAM_API_KEY,
  });

  // Create OCR job
  const job = await client.documentIntelligence.createJob({
    language: languageToSarvamCode(language),
    outputFormat: "md", // Markdown format
  });

  // Upload file and process
  await job.uploadFile(tempFilePath);
  await job.start();
  const status = await job.waitUntilComplete();

  // Download and extract results
  const downloadLinks = await job.getDownloadLinks();
  // Extract ZIP file and read markdown content
  // Returns: { success, text, confidence, language }
}
```

**Supported Languages**:
- `te` → `te-IN` (Telugu) - 48000 Hz
- `hi` → `hi-IN` (Hindi) - 22050 Hz
- `en` → `en-IN` (English) - 22050 Hz
- `ta` → `ta-IN` (Tamil) - 22050 Hz
- `ka` → `ka-IN` (Kannada) - 22050 Hz
- `ml` → `ml-IN` (Malayalam) - 22050 Hz
- `bn` → `bn-IN` (Bengali) - 22050 Hz

**Output Format**:
- Sarvam returns results as ZIP file containing:
  - `document.md` - Extracted text in Markdown format
  - `metadata/` - Page metadata and processing details

### 2. Sarvam TTS (Text-to-Speech)

**File**: `packages/core/src/services/sarvam-tts-service.js`

```javascript
const TELUGU_VOICES = {
  shubh: { name: "Shubh", gender: "male", description: "Natural male voice" },
  shreya: { name: "Shreya", gender: "female", description: "Natural female voice" },
  anushka: { name: "Anushka", gender: "female", description: "Professional female voice" },
  vidya: { name: "Vidya", gender: "female", description: "Warm female voice" },
  manisha: { name: "Manisha", gender: "female", description: "Clear female voice" },
  arya: { name: "Arya", gender: "male", description: "Calm male voice" },
};

const LANGUAGE_CONFIG = {
  te: {
    language_code: "te-IN",
    sample_rate: 48000, // CRITICAL: Telugu requires 48000 Hz
    voices: TELUGU_VOICES,
    defaultVoice: "shubh",
  },
  // ... Hindi, English configs with 22050 Hz
};

export async function generateSarvamAudio(text, language = "te", speaker = null) {
  const config = LANGUAGE_CONFIG[language];
  const selectedSpeaker = speaker || config.defaultVoice;

  const response = await client.textToSpeech.convert({
    text: text,
    target_language_code: config.language_code,
    speaker: selectedSpeaker,
    pace: 1.1,
    speech_sample_rate: config.sample_rate,
    enable_preprocessing: true,
    model: "bulbul:v3",
  });

  // Response format: { request_id, audios: [base64_audio] }
  return response.audios[0]; // Returns base64 audio data
}
```

**Key Parameters**:
- `text` - Input text (will be preprocessed by Sarvam)
- `language` - Target language code (te, hi, en, etc.)
- `speaker` - Voice speaker name (optional)
- `pace` - Speech speed (1.1 = 10% faster)
- `model` - TTS model (bulbul:v3 = latest)
- `speech_sample_rate` - Sample rate in Hz (language-dependent)

**Telugu Voice Selection**:

```javascript
// Get all available Telugu voices (for UI)
import { getTeluguVoices } from "./sarvam-tts-service.js";

const voices = getTeluguVoices();
// Returns:
// {
//   voices: { shubh, shreya, anushka, vidya, manisha, arya },
//   defaultVoice: "shubh",
//   language: "te-IN",
//   sampleRate: 48000,
//   model: "bulbul:v3"
// }

// Generate audio with specific voice
const audioUrl = await generateSarvamAudioDataUrl(text, "te", "shreya");
```

### 3. TTS Fallback Service

**File**: `packages/core/src/services/tts-fallback-service.js`

```javascript
export async function generateAudioWithFallback(text, language = 'te', speaker = null) {
  const providers = getTTSProviderOrder();
  // Primary: Sarvam, Fallback: Azure

  for (const provider of providers) {
    try {
      if (provider === 'sarvam') {
        return await sarvamGenerateAudio(text, language, speaker);
      } else if (provider === 'azure') {
        return await azureGenerateAudio(text, language);
      }
    } catch (error) {
      // Try next provider
    }
  }
}

function getTTSProviderOrder() {
  const primary = process.env.TTS_PROVIDER || 'azure';
  const fallbackEnabled = process.env.ENABLE_TTS_FALLBACK === 'true';

  switch (primary) {
    case 'sarvam':
      return fallbackEnabled ? ['sarvam', 'azure'] : ['sarvam'];
    case 'fallback':
      return ['azure', 'sarvam']; // Reverse order
    default:
      return fallbackEnabled ? ['azure', 'sarvam'] : ['azure'];
  }
}
```

## API Response Formats

### Document Processing Response

```json
{
  "ok": true,
  "newspaper": {
    "id": "newspaper_1779546876732",
    "title": "telugu_test.pdf",
    "date": "2026-05-23",
    "storageUrl": "http://localhost:8788/uploads/..."
  },
  "articles": [
    {
      "id": "article_1",
      "title": "TELUGU TELANGANA (CODE - 089)",
      "section": "Education",
      "preview": "First 200 characters of extracted text...",
      "audioUrl": "data:audio/mpeg;base64,UklGRi...[base64 audio]...",
      "qualityScore": 75,
      "status": "completed"
    }
  ],
  "models": {
    "ocr": "sarvam-ocr",
    "tts": "sarvam-tts"
  },
  "summary": {
    "totalArticles": 1,
    "processedArticles": 1,
    "failedArticles": 0,
    "processingTime": 35
  },
  "subscription": {
    "tier": "free",
    "active": true
  },
  "limits": {
    "maxPages": 10,
    "totalPages": 1,
    "processedPages": 1,
    "truncated": false
  }
}
```

### TTS Direct Response

```json
{
  "ok": true,
  "audioUrl": "data:audio/mpeg;base64,UklGRiQ6BABXQVZFZm10...[base64 audio]...",
  "provider": "sarvam"
}
```

## Flutter App Integration

### 1. Update API Endpoint

**File**: `packages/app/lib/services/document_service.dart`

```dart
class DocumentService {
  static const String _apiBaseUrl = 'http://your-razorhost-domain.com:8788';

  Future<Document> processDocument(File file) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_apiBaseUrl/api/documents/process'),
    );

    request.headers['X-Subscription-Tier'] = 'free'; // or premium/standard
    request.files.add(
      http.MultipartFile.fromBytes(
        'document',
        file.readAsBytesSync(),
        filename: 'document.pdf',
      ),
    );

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    final jsonData = json.decode(responseBody);

    // Parse response
    return Document.fromJson(jsonData);
  }
}
```

### 2. Voice Selection UI

**File**: `packages/app/lib/screens/voice_selection_screen.dart`

```dart
import 'package:http/http.dart' as http;

class VoiceSelectionScreen extends StatefulWidget {
  @override
  State<VoiceSelectionScreen> createState() => _VoiceSelectionScreenState();
}

class _VoiceSelectionScreenState extends State<VoiceSelectionScreen> {
  List<TeluguVoice> _teluguVoices = [];
  String _selectedVoice = 'shubh';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTeluguVoices();
  }

  Future<void> _loadTeluguVoices() async {
    try {
      // Call backend to get available voices
      final response = await http.get(
        Uri.parse('${DocumentService._apiBaseUrl}/api/voices/telugu'),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        // Expected format:
        // {
        //   "voices": {
        //     "shubh": { "name": "Shubh", "gender": "male", ... },
        //     "shreya": { "name": "Shreya", "gender": "female", ... },
        //     ...
        //   },
        //   "defaultVoice": "shubh"
        // }

        setState(() {
          _selectedVoice = jsonData['defaultVoice'] ?? 'shubh';
          _teluguVoices = (jsonData['voices'] as Map).entries
              .map((e) => TeluguVoice.fromJson(e.key, e.value))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading voices: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Select Voice')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Select Telugu Voice')),
      body: ListView.builder(
        itemCount: _teluguVoices.length,
        itemBuilder: (context, index) {
          final voice = _teluguVoices[index];
          final isSelected = _selectedVoice == voice.id;

          return ListTile(
            title: Text(voice.name),
            subtitle: Text('${voice.gender} - ${voice.description}'),
            trailing: isSelected
                ? Icon(Icons.check, color: Colors.green)
                : null,
            selected: isSelected,
            onTap: () {
              setState(() => _selectedVoice = voice.id);
              // Save to preferences or pass to document processor
              _processWithSelectedVoice();
            },
          );
        },
      ),
    );
  }

  Future<void> _processWithSelectedVoice() async {
    // Pass selected voice to document processing
    final doc = await DocumentService.instance.processDocument(
      selectedFile,
      preferredVoice: _selectedVoice, // Send voice preference
    );
    // Use doc.articles[0].audioUrl for playback
  }
}

class TeluguVoice {
  final String id;
  final String name;
  final String gender;
  final String description;

  TeluguVoice({
    required this.id,
    required this.name,
    required this.gender,
    required this.description,
  });

  factory TeluguVoice.fromJson(String id, Map<String, dynamic> json) {
    return TeluguVoice(
      id: id,
      name: json['name'] ?? '',
      gender: json['gender'] ?? '',
      description: json['description'] ?? '',
    );
  }
}
```

### 3. Updated Document Service with Voice Support

```dart
class DocumentService {
  static const String _apiBaseUrl = 'http://your-razorhost-domain.com:8788';

  Future<Document> processDocument(
    File file, {
    String preferredVoice = 'shubh',
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_apiBaseUrl/api/documents/process'),
    );

    request.headers['X-Subscription-Tier'] = 'premium'; // Include tier
    request.fields['preferredVoice'] = preferredVoice; // Add voice parameter

    request.files.add(
      http.MultipartFile.fromBytes(
        'document',
        file.readAsBytesSync(),
        filename: 'document.pdf',
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body);
      return Document.fromJson(jsonData);
    } else {
      throw Exception('Failed to process document: ${response.body}');
    }
  }

  // Direct text-to-speech endpoint (for testing voices)
  Future<String> synthesizeText(
    String text, {
    String language = 'te-IN',
    String voice = 'shubh',
  }) async {
    final response = await http.post(
      Uri.parse('$_apiBaseUrl/api/documents/synthesize'),
      headers: {
        'Content-Type': 'application/json',
        'X-Subscription-Tier': 'free',
      },
      body: json.encode({
        'text': text,
        'language': language,
        'speaker': voice,
      }),
    );

    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body);
      return jsonData['audioUrl']; // data:audio/mpeg;base64,...
    } else {
      throw Exception('Failed to synthesize text');
    }
  }
}
```

## Cost Comparison

### Before (Gemini)
- Gemini Vision per page: $0.0025 (expensive for bulk processing)
- Gemini 2.5 Flash: $0.075 per 1M tokens
- **Est. cost for 100-page newspaper**: $3-5 per document

### After (Sarvam)
- Sarvam OCR per document: ~$0.01-0.02
- Sarvam TTS per minute: ~$0.01
- **Est. cost for 100-page newspaper**: $0.05-0.15 per document
- **Savings**: 95-98% reduction

## Configuration Reference

### Environment Variables
```bash
# Required
SARVAM_API_KEY=sk_...

# Optional
TTS_PROVIDER=sarvam              # Primary provider
ENABLE_TTS_FALLBACK=true         # Enable Azure fallback
AZURE_TTS_KEY=...                # Azure credentials
AZURE_TTS_REGION=centralindia    # Azure region
```

### Language-Specific Settings
```javascript
// All values optimized for Indian language processing
{
  te: { language_code: "te-IN", sample_rate: 48000 },  // Telugu
  hi: { language_code: "hi-IN", sample_rate: 22050 },  // Hindi
  en: { language_code: "en-IN", sample_rate: 22050 },  // English
  ta: { language_code: "ta-IN", sample_rate: 22050 },  // Tamil
  ka: { language_code: "ka-IN", sample_rate: 22050 },  // Kannada
  ml: { language_code: "ml-IN", sample_rate: 22050 },  // Malayalam
  bn: { language_code: "bn-IN", sample_rate: 22050 },  // Bengali
}
```

## Troubleshooting & Common Issues

### Issue: "Speaker 'xyz' not recognized"
**Cause**: Using wrong speaker name for the language/model
**Solution**: Use one of: shubh, shreya, anushka, vidya, manisha, arya (for Telugu)

### Issue: "Invalid target_language_code"
**Cause**: Using language code without region (e.g., 'te' instead of 'te-IN')
**Solution**: Always use full language codes like 'te-IN', 'hi-IN'

### Issue: Audio quality issues or mismatched sample rate
**Cause**: Using wrong sample rate for language
**Solution**: Telugu = 48000 Hz, others = 22050 Hz

### Issue: ZIP extraction fails in OCR
**Cause**: Missing unzipper package
**Solution**: `npm install unzipper`

## Testing

### Test OCR Only
```bash
node --input-type=module -e "
import { performOCR } from './src/services/sarvam-vision-service.js';
import * as fs from 'fs';

const buffer = fs.readFileSync('./test.pdf');
const result = await performOCR(buffer, 'te');
console.log('Text extracted:', result.text.substring(0, 200));
"
```

### Test TTS Only
```bash
curl -X POST http://localhost:8788/api/documents/synthesize \
  -H "Content-Type: application/json" \
  -H "X-Subscription-Tier: free" \
  -d '{
    "text": "నమస్కారం సర్వం",
    "language": "te-IN"
  }' | jq '.audioUrl | .[0:100]'
```

### Test Full Pipeline
```bash
curl -X POST http://localhost:8788/api/documents/process \
  -H "X-Subscription-Tier: free" \
  -F "document=@sample.pdf" | jq '.articles[0] | {title, audioUrl: (.audioUrl | .[0:80])}'
```

---

**Version**: 1.0.0
**Last Updated**: 2026-05-23
**Status**: ✅ Production Ready
