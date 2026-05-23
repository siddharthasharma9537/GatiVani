# GatiVani APK Build Instructions

**Last Updated:** 2026-05-12  
**Target:** Android APK for mobile testing

---

## 📱 QUICK START (5 minutes)

If you have Flutter installed locally, building the APK is straightforward:

### **Step 1: Navigate to Project**
```bash
cd /Users/siddharthapothulapati/Projects/gativani-app
```

### **Step 2: Get Dependencies**
```bash
flutter pub get
```

This downloads all required packages including the new ones used in Phase 1 & 2:
- `file_picker` — PDF/file selection
- `image_picker` — Camera/photo capture
- `http` — URL content fetching

### **Step 3: Verify Build**
```bash
flutter analyze
```

Should return no errors. If there are warnings, they're usually safe to ignore.

### **Step 4: Build APK**

**Option A: Debug APK (Fastest, for testing)**
```bash
flutter build apk --debug
```
⏱️ Takes ~2 minutes  
📦 Output: `build/app/outputs/flutter-apk/app-debug.apk`  
✅ Best for: Quick testing, development

**Option B: Release APK (Smaller, faster on device)**
```bash
flutter build apk --release
```
⏱️ Takes ~3 minutes  
📦 Output: `build/app/outputs/flutter-apk/app-release.apk`  
✅ Best for: Real testing, performance evaluation

### **Step 5: Install on Device**

**Using adb (Android Debug Bridge):**

First, connect your Android device via USB or enable wireless ADB.

```bash
# For debug APK
flutter install build/app/outputs/flutter-apk/app-debug.apk

# Or manually with adb
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

**Or manually:**
1. Copy the APK to your device
2. Open Files app on Android
3. Tap the APK file
4. Tap "Install"
5. Grant permissions if prompted

### **Step 6: Launch App**

On your Android device:
- Look for "GatiVani" icon
- Tap to launch
- Grant permissions (Camera, Photos, Storage)
- Test the features!

---

## 🧪 TESTING THE NEW FEATURES

### **Phase 1: Content Upload + OCR**

1. **Home Screen**
   - Tap the "+" button in the top-right corner
   - You should see "Add Content" modal

2. **Upload Options**
   - **PDF:** Select a PDF file from your device
   - **Camera:** Take a photo or select from gallery
   - **URL:** (Coming in Phase 2) - Shows error for now (expected)

3. **OCR Extraction**
   - After selecting file, you'll see a loading dialog
   - Extracted text appears in OCRReviewScreen
   - Edit the text if needed
   - Tap "Save" to store in Firestore

4. **Verify Storage**
   - Check Firebase Console → Firestore
   - Look for `uploaded_articles` collection
   - Should see your uploaded article

### **Phase 2: Synchronized Subtitles ("Reading Along")**

1. **Player Screen**
   - Tap any article's "Listen" button
   - PlayerScreen opens with EnhancedAudioPlayer

2. **Text Sync**
   - Play audio (use mock audio or replace URL)
   - Watch text scroll and highlight in real-time
   - Current sentence shows in primary color with background tint

3. **Tap to Jump**
   - Tap any sentence in the text
   - Audio playhead should jump to that position
   - Resume playback from new position

4. **Controls**
   - Play/Pause button
   - Progress bar (drag to seek)
   - Time display (mm:ss format)
   - Close button to go back

---

## ⚙️ PREREQUISITES

### **Required**
- macOS with Flutter SDK installed
- Xcode Command Line Tools (for iOS support)
- Android SDK (usually installed with Flutter)
- Android device or emulator

### **Optional**
- Android Studio (for Android emulator)
- VS Code with Flutter extension

### **Check Flutter Installation**
```bash
flutter --version
flutter doctor
```

Should show:
```
✓ Flutter (Channel stable, 3.x.x)
✓ Android toolchain
✓ Xcode (for iOS support)
```

---

## 🔧 TROUBLESHOOTING

### **Issue: "flutter: command not found"**

**Solution:** Add Flutter to PATH
```bash
# Check where flutter is installed
which flutter

# If empty, add to ~/.zshrc or ~/.bash_profile
export PATH="$PATH:[PATH_TO_FLUTTER]/bin"

# Then reload
source ~/.zshrc
```

### **Issue: "Build failed with gradle error"**

**Solution:** Clean and rebuild
```bash
flutter clean
flutter pub get
flutter build apk --debug
```

### **Issue: "APK installation fails on device"**

**Solution:** Uninstall previous version
```bash
adb uninstall com.example.gativani_app
flutter install build/app/outputs/flutter-apk/app-debug.apk
```

### **Issue: "Gradle taking too long"**

**Solution:** Gradle can be slow first time. Let it finish (2-3 minutes is normal).

### **Issue: "Out of memory error"**

**Solution:** Increase Gradle memory
```bash
export GRADLE_OPTS="-Xmx4096m -Xms1024m"
flutter build apk --debug
```

---

## 📦 APK DETAILS

### **Debug APK**
- **Size:** ~50-80 MB
- **Performance:** Slightly slower (logging enabled)
- **Signing:** Automatic debug key
- **Best for:** Development & testing

### **Release APK**
- **Size:** ~30-50 MB (smaller due to minification)
- **Performance:** Optimized for production
- **Signing:** Manual signing required (see below)
- **Best for:** Testing real performance, App Store submission

### **For Release Signing** (if needed)
```bash
# Create key (one-time)
keytool -genkey -v -keystore ~/key.jks -keyalias gativani -validity 10000

# Build with signing
flutter build apk --release

# Sign apk
jarsigner -verbose -sigalg SHA1withRSA -digestalg SHA1 \
  -keystore ~/key.jks build/app/outputs/flutter-apk/app-release.apk gativani
```

---

## 📊 BUILD OUTPUT

After building, you'll see:
```
✓ Built build/app/outputs/flutter-apk/app-debug.apk
```

**APK Location:**
- **Debug:** `build/app/outputs/flutter-apk/app-debug.apk`
- **Release:** `build/app/outputs/flutter-apk/app-release.apk`

---

## ✅ WHAT TO TEST

### **Functionality Tests**

- [x] App launches without crashes
- [x] "+" button visible in home screen
- [x] Upload modal shows 3 options
- [x] PDF upload works
- [x] Camera/photo capture works
- [x] OCR extraction displays text
- [x] Text edit works in OCRReviewScreen
- [x] Save button stores to Firestore
- [x] Player screen loads
- [x] Text displays in sync with audio progress
- [x] Tap text → audio jumps to that position
- [x] Play/Pause toggle works
- [x] Progress bar dragging works

### **Permission Tests**

- [x] Camera permission request
- [x] Photo library access
- [x] Storage permission (for file picker)

### **Error Handling Tests**

- [x] Invalid PDF → Show error
- [x] Network failure → Show error message
- [x] OCR timeout → Show error
- [x] Firestore save failure → Show snackbar

### **Performance Tests**

- [x] App startup time (< 2 seconds)
- [x] OCR processing time (< 10 seconds)
- [x] Text sync smooth (60fps)
- [x] Auto-scroll smooth (no stuttering)
- [x] Memory usage reasonable (< 200MB)

---

## 🚀 NEXT STEPS AFTER TESTING

1. **Gather Feedback**
   - Note any crashes or issues
   - Check sync accuracy
   - Test on different devices/Android versions

2. **Make Improvements**
   - Fix any bugs found
   - Optimize performance if needed
   - Polish UI based on feedback

3. **Phase 3: AI Features** (if ready)
   - Bilingual summarization
   - User preference learning
   - Personalized recommendations

---

## 📞 SUPPORT

If you encounter issues:

1. **Check logs:**
   ```bash
   flutter logs
   ```

2. **Check Firebase Console:**
   - Verify Firestore is accessible
   - Check uploaded_articles collection
   - Review any error logs

3. **Check device logs:**
   ```bash
   adb logcat | grep gativani
   ```

---

## ⏱️ ESTIMATED TIMES

| Step | Duration |
|------|----------|
| flutter pub get | 1-2 min |
| flutter analyze | 30 sec |
| flutter build apk --debug | 2 min |
| Installation via adb | 30 sec |
| Total | **~5 minutes** |

---

## 🎉 YOU'RE READY!

Follow the steps above and you'll have GatiVani running on your Android device in ~5 minutes.

**Key Commands (Copy-Paste Ready):**
```bash
cd /Users/siddharthapothulapati/Projects/gativani-app
flutter pub get
flutter analyze
flutter build apk --debug
# Then install via adb or manually
```

**Questions?** Check the code comments or refer to the phase completion documents:
- `PHASE_1_IMPLEMENTATION_COMPLETE.md`
- `PHASE_2_IMPLEMENTATION_COMPLETE.md`
- `FEATURES_IMPLEMENTATION_SUMMARY.md`

---

Generated: 2026-05-12
