# 🚀 GatiVani: Build APK & Test on Android — Quick Start

**Time to APK:** ~5 minutes  
**Time to Testing:** ~10 minutes  
**Total Time:** ~15 minutes

---

## ⚡ QUICKEST PATH (Copy-Paste Ready)

Open Terminal and run these commands:

```bash
# 1. Navigate to project
cd /Users/siddharthapothulapati/Projects/gativani-app

# 2. Get dependencies (1-2 min)
flutter pub get

# 3. Build APK - Debug version (2 min, fastest for testing)
flutter build apk --debug

# 4. Install on device - option A: via adb
adb install -r build/app/outputs/flutter-apk/app-debug.apk

# OR option B: use flutter install
flutter install build/app/outputs/flutter-apk/app-debug.apk

# 5. Launch app on device and start testing!
```

**That's it!** You now have GatiVani running on your Android device.

---

## 📱 WHAT YOU CAN TEST IMMEDIATELY

### Phase 1: Content Upload + OCR ✨ **NEW**

**Try this right now:**
1. Launch app
2. Tap "+" button (top-right corner)
3. See "Add Content" modal with 3 options
4. Select "📄 Upload PDF" or "📷 Camera/Photos"
5. Watch OCR extract text from your file
6. Edit text and save

**What happens in background:**
- PDF uploaded to Firebase Storage
- Text extracted via Sarvam AI OCR
- Categorized automatically via Google Gemini
- Saved to Firestore database

### Phase 2: Synchronized Subtitles ✨ **NEW**

**Try this next:**
1. Go to any article
2. Tap "Listen" button
3. Audio plays with synced text below
4. Current sentence highlights in real-time
5. Tap any sentence to jump audio to that point
6. Watch smooth auto-scroll

**What you'll see:**
- Text highlights current sentence (primary color)
- Background tint on highlighted text
- Auto-scroll keeps sentence centered
- Play/pause controls
- Progress bar with time display

---

## 📋 PREREQUISITES CHECKLIST

Before you start, make sure you have:

- [ ] **Flutter installed** — Check with `flutter --version`
- [ ] **Android device or emulator**
- [ ] **USB debugging enabled** (for physical device)
  - Go to: Settings → Developer Options → USB Debugging
- [ ] **Device connected via USB** or
- [ ] **Wireless ADB configured** (optional)
- [ ] **Internet connection** on device (WiFi or data)
- [ ] **At least 100MB free storage**

**Quick check:**
```bash
flutter doctor
```

Should show ✓ for Flutter, Android Toolchain, and one of (Xcode or Android Studio)

---

## 🎯 STEP-BY-STEP PROCESS

### **Step 1: Prepare Project** (30 seconds)

```bash
cd /Users/siddharthapothulapati/Projects/gativani-app
flutter pub get
```

✅ If no errors, proceed to Step 2

### **Step 2: Verify Code** (optional, 30 seconds)

```bash
flutter analyze
```

⚠️ May show warnings (safe to ignore)

### **Step 3: Build Debug APK** (2 minutes)

```bash
flutter build apk --debug
```

You'll see:
```
✓ Built build/app/outputs/flutter-apk/app-debug.apk
```

✅ APK is ready!

### **Step 4: Install on Device** (30 seconds)

**Option A - Via ADB (Recommended):**
```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

You should see:
```
Success
```

**Option B - Via Flutter:**
```bash
flutter install build/app/outputs/flutter-apk/app-debug.apk
```

**Option C - Manual Installation:**
1. Copy APK to device
2. Open Files app
3. Find the APK
4. Tap to install
5. Tap "Install"

### **Step 5: Launch & Test** (ongoing)

**On your device:**
1. Find "GatiVani" app icon
2. Tap to launch
3. Grant permissions when prompted:
   - Camera access
   - Photos access
   - Storage access
4. Start testing features!

---

## 🧪 QUICK TEST SEQUENCE (10 minutes)

### **Minute 1-2: App Startup**
- Launch app
- Verify HomeScreen loads
- Check "+" button visible in top-right

### **Minute 2-5: Phase 1 (Upload + OCR)**
- Tap "+" button
- See modal with 3 options
- Tap "📷 Camera/Photos"
- Take photo or select from gallery
- Watch OCR extraction
- See extracted text in OCRReviewScreen
- Tap Save

### **Minute 5-8: Phase 2 (Sync Subtitles)**
- Go back to HomeScreen
- Tap "Listen" on any article
- PlayerScreen opens with synced text
- Tap play
- Watch text highlight and auto-scroll
- Tap a sentence to jump audio
- Stop and go back

### **Minute 8-10: Verify Firestore**
1. Open Firebase Console
2. Go to Firestore Database
3. Check `uploaded_articles` collection
4. Verify your uploaded article is there

---

## 🐛 TROUBLESHOOTING

### **Problem: "flutter: command not found"**
```bash
# Solution: Add Flutter to PATH
export PATH="$PATH:$(which flutter | xargs dirname)/../.."
# Then re-run flutter build command
```

### **Problem: "Build failed with gradle error"**
```bash
# Solution: Clean and rebuild
flutter clean
flutter pub get
flutter build apk --debug
```

### **Problem: "adb: command not found"**
```bash
# Solution: Use flutter install instead
flutter install build/app/outputs/flutter-apk/app-debug.apk
```

### **Problem: "Device not recognized"**
```bash
# Check device connection
adb devices

# If not listed, try:
adb kill-server
adb start-server
# Then plug device back in
```

### **Problem: "Installation fails - App already exists"**
```bash
# Solution: Force uninstall and reinstall
adb uninstall com.example.gativani_app
adb install build/app/outputs/flutter-apk/app-debug.apk
```

### **Problem: "Gradle taking too long"**
Let it run — Gradle can take 2-3 minutes on first build. Subsequent builds are faster.

### **Problem: "Out of memory error"**
```bash
export GRADLE_OPTS="-Xmx4096m -Xms1024m"
flutter build apk --debug
```

---

## 📊 APK DETAILS

**Debug APK** (recommended for testing)
- Size: ~50-80 MB
- Speed: Fast to build
- Performance: Good (logging enabled)
- Install time: ~30 seconds
- Best for: Development & testing

**Release APK** (smaller, faster on device)
- Size: ~30-50 MB
- Speed: Slower to build
- Performance: Optimized
- Install time: ~20 seconds
- Best for: Real testing, production

---

## 🎯 TESTING FOCUS AREAS

### **Must Test:**
1. ✅ Home screen "+" button
2. ✅ PDF upload and OCR
3. ✅ Photo capture and OCR
4. ✅ Text editing in OCRReviewScreen
5. ✅ Firestore data storage
6. ✅ Audio playback on PlayerScreen
7. ✅ Text sync with audio
8. ✅ Tap sentence to jump audio
9. ✅ Auto-scroll while playing

### **Nice to Have:**
- Play/pause toggle
- Progress bar seeking
- Time display accuracy
- Permissions handling
- Error messages
- Performance (startup time, memory)

---

## 📞 QUICK REFERENCE

### **Commands Cheat Sheet**

| Command | Purpose | Time |
|---------|---------|------|
| `flutter pub get` | Get dependencies | 1-2 min |
| `flutter analyze` | Check code quality | 30 sec |
| `flutter build apk --debug` | Build debug APK | 2 min |
| `flutter build apk --release` | Build optimized APK | 3 min |
| `adb install -r app.apk` | Install APK | 30 sec |
| `flutter install app.apk` | Install via Flutter | 30 sec |
| `adb logcat \| grep gativani` | View app logs | Real-time |
| `adb devices` | List connected devices | 1 sec |

### **File Locations**

| What | Path |
|------|------|
| Debug APK | `build/app/outputs/flutter-apk/app-debug.apk` |
| Release APK | `build/app/outputs/flutter-apk/app-release.apk` |
| Project root | `/Users/siddharthapothulapati/Projects/gativani-app` |
| Build script | `build_apk.sh` (in project root) |
| Testing guide | `TESTING_GUIDE.md` |
| Build instructions | `BUILD_APK_INSTRUCTIONS.md` |

---

## 🚀 USING THE BUILD SCRIPT (Alternative)

Instead of running commands individually, use the automated script:

```bash
# Make script executable (one-time)
chmod +x /Users/siddharthapothulapati/Projects/gativani-app/build_apk.sh

# Run script (builds debug APK)
/Users/siddharthapothulapati/Projects/gativani-app/build_apk.sh debug

# Or build release
/Users/siddharthapothulapati/Projects/gativani-app/build_apk.sh release
```

Script will:
1. Check Flutter installation ✓
2. Get dependencies ✓
3. Analyze code ✓
4. Build APK ✓
5. Show APK location and size ✓
6. Suggest next commands ✓

---

## ✅ SUCCESS CHECKLIST

After following this guide:

- [ ] Flutter pub get completed
- [ ] APK built successfully
- [ ] APK size shown (should be 50-80 MB for debug)
- [ ] APK installed on device
- [ ] App launches without crashes
- [ ] HomeScreen visible with "+" button
- [ ] Can tap "+" and see upload modal
- [ ] Can upload PDF and see OCR
- [ ] Can play audio and see synced text
- [ ] Tap sentence jumps audio
- [ ] No major crashes

✅ **All checked?** Your GatiVani testing environment is ready!

---

## 📖 DETAILED GUIDES

For more information, see:

1. **BUILD_APK_INSTRUCTIONS.md**
   - Detailed build steps
   - Troubleshooting
   - Release APK signing

2. **TESTING_GUIDE.md**
   - Complete test cases
   - Test report template
   - Performance testing

3. **FEATURES_IMPLEMENTATION_SUMMARY.md**
   - Architecture overview
   - Feature details
   - Design principles

4. **PHASE_1_IMPLEMENTATION_COMPLETE.md**
   - Upload + OCR implementation details

5. **PHASE_2_IMPLEMENTATION_COMPLETE.md**
   - Sync subtitles implementation details

---

## 🎉 YOU'RE READY!

You now have everything needed to:
1. ✅ Build the APK
2. ✅ Install on Android device
3. ✅ Test all features
4. ✅ Report results

**Get started:** Copy the quick build commands above and run them!

---

**Generated:** 2026-05-12  
**Version:** 1.0.0
