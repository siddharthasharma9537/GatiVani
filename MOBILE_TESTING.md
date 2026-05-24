# 📱 Mobile Testing Guide - GatiVani Flutter App

## Quick Setup for Local Testing

### Your Development Setup
- **Mac IP Address**: `192.168.31.118`
- **Backend Port**: `8788`
- **API URL**: `http://192.168.31.118:8788`

### Prerequisites
- ✅ Android phone on same WiFi network as Mac
- ✅ Node.js backend running on Mac (`npm start`)
- ✅ Flutter app installed on Android phone (or can build from source)

---

## Step 1: Update Flutter App API Endpoint

### Option A: Update in Code (For Development)

**File**: `packages/app/lib/services/document_service.dart`

```dart
class DocumentService {
  // Change this line:
  static const String _apiBaseUrl = 'http://192.168.31.118:8788';
  
  // Or for production:
  // static const String _apiBaseUrl = 'https://your-razorhost-domain.com';
}
```

### Option B: Use Environment Variables (Better)

Create a config file that switches based on environment:

**File**: `packages/app/lib/config/api_config.dart`

```dart
class ApiConfig {
  static String getBaseUrl() {
    const String env = String.fromEnvironment('API_ENV', defaultValue: 'development');
    
    if (env == 'production') {
      return 'https://your-razorhost-domain.com';
    } else {
      // Development (local Mac)
      return 'http://192.168.31.118:8788';
    }
  }
}
```

Then update `document_service.dart`:
```dart
import 'package:gativani/config/api_config.dart';

class DocumentService {
  static final String _apiBaseUrl = ApiConfig.getBaseUrl();
}
```

---

## Step 2: Build & Deploy Flutter App

### Option A: Run from Mac (Recommended for Testing)

```bash
cd packages/app

# Build for Android (debug)
flutter build apk --debug

# Install on connected device
flutter install

# Or run directly
flutter run
```

### Option B: If App Already Installed

Just update the API endpoint in the code and rebuild:

```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

---

## Step 3: Test on Android Phone

### Verify Network Connection
1. Make sure your phone is on the **same WiFi network** as your Mac
2. Open phone settings → WiFi → Connected to same network ✅

### Test Health Endpoint

From your phone's browser, try:
```
http://192.168.31.118:8788/health
```

You should see:
```json
{
  "ok": true,
  "service": "voxnews-node-core",
  "env": "development"
}
```

### Test Document Processing

#### Using the Flutter App UI:
1. Open GatiVani app on phone
2. Select a PDF document (use test PDFs if available)
3. Tap "Process Document"
4. Wait ~30 seconds for processing
5. Listen to generated audio

#### Using curl from Mac (to simulate phone request):
```bash
curl -X POST http://192.168.31.118:8788/api/documents/process \
  -H "X-Subscription-Tier: free" \
  -F "document=@telugu_test.pdf"
```

---

## Step 4: Troubleshooting Mobile Connection

### Problem: "Connection Refused"
**Symptom**: Phone can't reach the Mac backend

**Solutions**:
1. ✅ Check Mac and phone are on same WiFi network
2. ✅ Get correct Mac IP: `ifconfig | grep "inet "`
3. ✅ Verify server is running: `curl http://localhost:8788/health`
4. ✅ Check firewall: System Preferences → Security & Privacy → Firewall Options
   - Allow Node.js/npm through firewall (or disable for testing)

### Problem: "Timeout Error"
**Symptom**: Request takes too long or times out

**Solutions**:
1. Check processing is working on Mac:
   ```bash
   curl -X POST http://localhost:8788/api/documents/process \
     -H "X-Subscription-Tier: free" \
     -F "document=@telugu_test.pdf"
   ```
2. Increase timeout in Flutter code (default: 120 seconds):
   ```dart
   final response = await http.post(
     uri,
     headers: headers,
   ).timeout(Duration(minutes: 5)); // Increase timeout
   ```

### Problem: "Wrong Document Title"
**Symptom**: Getting placeholder text instead of OCR content

**Solution**: This was fixed! The OCR now properly extracts ZIP files. If you're seeing "Document processed" placeholder:
1. Make sure you're using latest code from main branch
2. Clear app cache: Settings → Apps → GatiVani → Storage → Clear Cache
3. Rebuild and reinstall app

### Problem: "No Audio Generated"
**Symptom**: Processing completes but no audio in response

**Solutions**:
1. Check backend logs:
   ```bash
   tail -50 /tmp/server.log | grep -i "sarvam\|tts\|error"
   ```
2. Verify SARVAM_API_KEY is set:
   ```bash
   cat packages/core/.env | grep SARVAM_API_KEY
   ```
3. Test TTS directly:
   ```bash
   curl -X POST http://localhost:8788/api/documents/synthesize \
     -H "Content-Type: application/json" \
     -H "X-Subscription-Tier: free" \
     -d '{"text": "నమస్కారం", "language": "te-IN"}'
   ```

---

## Step 5: Monitor Backend During Testing

### Watch Server Logs in Real-Time

```bash
# Terminal 1: Watch server logs
tail -f /tmp/server.log

# Terminal 2: Run another command or test
```

### Check for Errors

```bash
# Show only errors
tail -50 /tmp/server.log | grep -i "error\|fail"

# Show Sarvam service logs
tail -50 /tmp/server.log | grep -i "sarvam"

# Show TTS logs
tail -50 /tmp/server.log | grep -i "tts"
```

---

## Step 6: Test Different Scenarios

### Test 1: Small Document
- Use: `telugu_test.pdf` (existing)
- Expected: ~30 seconds processing
- Verify: Title, preview, audio generated

### Test 2: Text-Only Processing
In Flutter app, test `/api/documents/synthesize`:

```dart
final response = await http.post(
  Uri.parse('http://192.168.31.118:8788/api/documents/synthesize'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'text': 'నమస్కారం సర్వం',
    'language': 'te-IN',
  }),
);
```

### Test 3: Different Languages
```dart
// Hindi
'text': 'नमस्ते सर्वम'
'language': 'hi-IN'

// English
'text': 'Hello Sarvam'
'language': 'en-IN'
```

### Test 4: Voice Selection
```dart
// Add voice parameter
'speaker': 'shreya'  // or 'anushka', 'vidya', etc.
```

---

## Step 7: Performance Testing on Mobile

### Measure Response Times

Add timing to Flutter app:
```dart
final startTime = DateTime.now();

final response = await http.post(
  uri,
  headers: headers,
  body: body,
);

final duration = DateTime.now().difference(startTime);
print('API Response Time: ${duration.inSeconds}s');
```

**Expected Times**:
- Health check: < 1 second
- TTS generation: 1-2 seconds
- Document processing: 20-40 seconds

### Monitor Network Usage

On Mac:
```bash
# Real-time network stats
nettop -l 1

# Or use Activity Monitor
open -a "Activity Monitor"
```

---

## Step 8: Debug Network Issues

### Test Connectivity from Phone
```bash
# On Mac, create a simple test endpoint
# Or use curl from Mac to test:
curl -v http://192.168.31.118:8788/health
```

### Check Port Accessibility
```bash
# Is port 8788 open?
lsof -i :8788

# If not running:
cd packages/core && npm start
```

### Verify CORS Headers
```bash
curl -i http://192.168.31.118:8788/health | head -20
```

Should show:
```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
```

---

## Full Testing Workflow

```
1. Start server on Mac
   └─ npm start in packages/core/

2. Update Flutter app
   └─ Change API_BASE_URL to 192.168.31.118:8788

3. Build Flutter app
   └─ flutter run on Android phone

4. Test features in order:
   ├─ Health endpoint (verify connection)
   ├─ TTS endpoint (test text-to-speech)
   ├─ Document upload (test file handling)
   ├─ OCR extraction (verify text extraction)
   ├─ Audio generation (verify TTS output)
   └─ UI playback (test audio playback)

5. Monitor backend logs
   └─ tail -f /tmp/server.log

6. Debug issues
   └─ Check error logs, test endpoints with curl

7. Ready for production
   └─ Change endpoint to Razorhost domain
```

---

## Production Deployment Checklist

Once testing is complete and working on mobile:

- [ ] Backend deployed to Razorhost
- [ ] Update API endpoint to production domain
- [ ] Test on mobile with production endpoint
- [ ] Build release APK: `flutter build apk --release`
- [ ] Test release build on phone
- [ ] Deploy to Play Store (if needed)

---

## Quick Reference: API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Check server status |
| `/api/documents/process` | POST | Process document (OCR + TTS) |
| `/api/documents/synthesize` | POST | Generate audio from text |
| `/uploads/<filename>` | GET | Download uploaded file |

---

## Example: Complete Test Flow in Flutter

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';

class MobileTestHelper {
  static const String API_URL = 'http://192.168.31.118:8788';

  // Test 1: Health check
  static Future<void> testHealth() async {
    try {
      final response = await http.get(Uri.parse('$API_URL/health'));
      print('Health: ${response.statusCode}');
      print(jsonDecode(response.body));
    } catch (e) {
      print('Error: $e');
    }
  }

  // Test 2: TTS
  static Future<void> testTTS() async {
    try {
      final response = await http.post(
        Uri.parse('$API_URL/api/documents/synthesize'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'text': 'నమస్కారం',
          'language': 'te-IN',
        }),
      );
      print('TTS: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Audio generated: ${data['audioUrl'].length} bytes');
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  // Test 3: Document Processing
  static Future<void> testDocumentProcessing(File file) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$API_URL/api/documents/process'),
      );

      request.headers['X-Subscription-Tier'] = 'free';
      request.files.add(
        http.MultipartFile.fromBytes(
          'document',
          file.readAsBytesSync(),
          filename: file.path.split('/').last,
        ),
      );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      print('Document Processing: ${response.statusCode}');
      final data = jsonDecode(responseBody);
      print('Title: ${data['articles'][0]['title']}');
      print('Audio URL: ${data['articles'][0]['audioUrl'].substring(0, 100)}...');
    } catch (e) {
      print('Error: $e');
    }
  }
}

// Usage in your app:
// MobileTestHelper.testHealth();
// MobileTestHelper.testTTS();
// MobileTestHelper.testDocumentProcessing(pdfFile);
```

---

## Support & Debugging

If you encounter issues:

1. **Check server is running**: `curl http://localhost:8788/health`
2. **Verify IP address**: `ifconfig | grep "inet "`
3. **Check WiFi**: Both phone and Mac on same network
4. **Review logs**: `tail -50 /tmp/server.log`
5. **Test endpoints**: Use curl to test from Mac first
6. **Check firewall**: Allow Node.js through System Preferences

---

**Status**: Ready for Mobile Testing 📱  
**IP Address**: 192.168.31.118:8788  
**Document**: Generated 2026-05-23  
**API Version**: 1.0.0 (Sarvam Integration)
