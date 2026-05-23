# GatiVani Testing Guide — Comprehensive

**Date:** 2026-05-12  
**Scope:** Phase 1 (Upload + OCR) & Phase 2 (Sync Subtitles)  
**Environment:** Android Device or Emulator

---

## 🚀 QUICK TEST SUMMARY

**What to test:** All new features work end-to-end  
**Time required:** 15-30 minutes  
**Device required:** Android phone or emulator  
**Permissions needed:** Camera, Photos, Storage, Network

---

## 📋 PRE-TESTING CHECKLIST

Before you start testing, verify:

- [ ] APK installed on Android device
- [ ] Device connected to internet (WiFi or data)
- [ ] Firebase credentials configured (credentials should auto-load)
- [ ] Enough storage space (at least 100MB free)
- [ ] Android version 5.0+ (SDK 21+)

---

## 🧪 PHASE 1: CONTENT UPLOAD + OCR TESTING

### **Test 1.1: Home Screen "+" Button**

**Steps:**
1. Launch GatiVani app
2. Look at top-right corner of HomeScreen
3. Should see a "+" button (add icon)
4. Tap the "+" button

**Expected Result:**
- ✅ Navigation to UploadContentScreen
- ✅ "Add Content" modal appears with 3 options
- ✅ No crashes

**Screenshot Verification:**
- HomeScreen should have AppBar with "+" icon
- Modal should show: "Add Content" title
- Three options visible: 📄 PDF, 📷 Camera/Photos, 🔗 URL

---

### **Test 1.2: PDF Upload Flow**

**Prerequisites:**
- Have a PDF file on your device (any PDF works)
- Sample: Receipt, document, newspaper clipping, etc.

**Steps:**
1. Tap "+" button on HomeScreen
2. In modal, tap "📄 Upload PDF"
3. File picker opens
4. Navigate to a PDF file
5. Select the PDF
6. Wait for processing (shows loading dialog)
7. OCRReviewScreen appears with extracted text

**Expected Result:**
- ✅ File picker opens correctly
- ✅ PDF file selectable
- ✅ Loading dialog shows (2-5 seconds)
- ✅ OCRReviewScreen displays extracted text
- ✅ Text is readable and mostly accurate
- ✅ "Confidence: ~90%" badge shown
- ✅ Category badge shown (should auto-categorize)
- ✅ No crashes

**Verification Points:**
- Extracted text should match PDF content (allow minor OCR errors)
- Text should be editable in the TextEditingController
- Cancel button works (returns to HomeScreen)
- Save button is enabled

**Data to Check in Firebase:**
1. Go to Firebase Console → Firestore
2. Check `uploaded_articles` collection
3. Should have new document with:
   - `id`: timestamp
   - `title`: PDF filename
   - `content`: extracted text
   - `source`: "pdf"
   - `category`: one of 8 categories
   - `storageUrl`: Firebase Storage URL
   - `extractedAt`: timestamp

---

### **Test 1.3: Camera/Photo Upload Flow**

**Prerequisites:**
- Android device with camera
- Or image files on device

**Steps:**
1. Tap "+" button on HomeScreen
2. In modal, tap "📷 Camera/Photos"
3. Either:
   - Take a new photo with camera
   - Or select existing photo from gallery
4. Wait for processing
5. OCRReviewScreen appears

**Expected Result:**
- ✅ Camera/photo picker works
- ✅ Photo captured or selected
- ✅ OCR extraction completes
- ✅ Text displays in OCRReviewScreen
- ✅ Image source correctly set to "camera"

**Note:** Photo quality affects OCR accuracy. High-quality, well-lit photos work best.

---

### **Test 1.4: OCR Text Editing**

**Steps:**
1. Complete Test 1.2 or 1.3 (see OCRReviewScreen)
2. Extracted text visible in TextEditingController
3. Edit some text (fix OCR errors)
4. Make several changes
5. Tap "Save" button

**Expected Result:**
- ✅ Text is editable
- ✅ Can select/delete/modify text freely
- ✅ Keyboard works (no input issues)
- ✅ Save button enabled
- ✅ Saving doesn't crash
- ✅ SnackBar shows "Article saved successfully! ✓"
- ✅ Navigation returns to HomeScreen

**Data to Check:**
- Modified text should be in Firestore (check `uploaded_articles.content`)
- Should match your edits exactly

---

### **Test 1.5: Category Parsing**

**Steps:**
1. Upload different content types:
   - Political/government news → Should categorize as "National News"
   - Sports article → Should categorize as "Sports & Entertainment"
   - Technology article → Should categorize as "Science & Technology"
   - Business/market news → Should categorize as "Business & Economy"
2. Check category badge in OCRReviewScreen

**Expected Result:**
- ✅ Categories correctly identified (mostly correct)
- ✅ Category badge displays in OCRReviewScreen
- ✅ Category saved to Firestore
- ✅ Rare misclassifications acceptable (AI isn't 100% perfect)

**8 Expected Categories:**
1. National News
2. State & Local
3. Crime & Law
4. Business & Economy
5. Science & Technology
6. Sports & Entertainment
7. Social & Health
8. Opinion & Editorial

---

### **Test 1.6: Error Handling**

**Scenario A: Invalid PDF**
1. Try to upload a corrupted/invalid PDF
2. Should show error message
3. ✅ No crash, graceful error

**Scenario B: Network Failure**
1. Disable internet
2. Try PDF upload
3. Should show error about network
4. ✅ Error message shown, no crash

**Scenario C: Permissions Denied**
1. Deny camera/storage permissions when prompted
2. App should gracefully handle
3. ✅ Error message explains what to do

---

## 🎵 PHASE 2: SYNCHRONIZED SUBTITLES TESTING

### **Test 2.1: Player Screen Launch**

**Steps:**
1. Go back to HomeScreen
2. Tap any article's "Listen" button
3. Wait for PlayerScreen to load

**Expected Result:**
- ✅ PlayerScreen loads without crashes
- ✅ EnhancedAudioPlayer component visible
- ✅ Article title shown at top
- ✅ Text displayed below player controls

**Visual Verification:**
- Title visible in header
- Audio controls visible (play/pause button)
- Progress bar visible
- Text content visible below

---

### **Test 2.2: Audio Playback Controls**

**Steps:**
1. On PlayerScreen (Test 2.1)
2. Tap play button
3. Audio should start playing (might use mock audio)
4. Tap pause
5. Tap progress bar to seek to middle

**Expected Result:**
- ✅ Play/pause button toggles correctly
- ✅ Icon changes (play ↔ pause)
- ✅ Progress bar updates during playback
- ✅ Dragging progress bar seeks correctly
- ✅ Time display shows mm:ss format
- ✅ Time updates as audio plays

**Verification:**
- Time display accurate (< 1 second off)
- Progress bar smooth (no stuttering)
- Seek works on first drag (no lag)

---

### **Test 2.3: Text Synchronization**

**Steps:**
1. On PlayerScreen with audio playing
2. Watch text display
3. Current sentence should be highlighted
4. As audio progresses, different sentences highlight

**Expected Result:**
- ✅ Current sentence highlighted in primary color
- ✅ Background tint on highlighted sentence
- ✅ Bold font weight on highlighted sentence
- ✅ Highlighting changes smoothly as audio plays
- ✅ Sync is roughly accurate (±2 seconds acceptable)

**Visual Verification:**
- Highlighted text clearly visible
- Color provides good contrast
- No overlapping highlights
- Smooth transitions between sentences

---

### **Test 2.4: Auto-Scroll During Playback**

**Steps:**
1. Start audio playback
2. Current sentence should appear in viewport center
3. As audio plays and sentences change, view auto-scrolls
4. Scroll should be smooth and follow audio

**Expected Result:**
- ✅ Text auto-scrolls during playback
- ✅ Current sentence stays roughly centered
- ✅ Scroll animation smooth (no jumping)
- ✅ Animation duration ~300ms (not too fast/slow)
- ✅ Scroll stops when audio pauses

**Performance Check:**
- Scroll smooth at 60fps (no frame drops)
- No lag when scrolling
- Responsive to audio progress changes

---

### **Test 2.5: Tap-to-Jump Functionality**

**Steps:**
1. On PlayerScreen
2. Tap a sentence near the end of text
3. Audio playhead should jump to that position
4. Playback continues from new position

**Expected Result:**
- ✅ Tap on any sentence recognized
- ✅ Audio seeks to approximate position
- ✅ Seek is accurate (±2 seconds)
- ✅ Playback continues smoothly
- ✅ Text highlight follows new position

**Verification:**
- Tapping works on first tap (no need to tap twice)
- Jump is quick (< 500ms)
- Audio resumes immediately after seek
- No audio artifacts/stuttering

---

### **Test 2.6: Text Display Quality**

**Steps:**
1. Review text display on PlayerScreen
2. Check for:
   - Readability
   - Font size (should be 16pt)
   - Line height (should be 1.6x)
   - Text alignment (justified)

**Expected Result:**
- ✅ Text easily readable
- ✅ Line spacing comfortable (not cramped)
- ✅ No text overflow
- ✅ Proper line breaks
- ✅ Punctuation preserved

**Device-Specific Tests:**
- Test on phone (small screen)
- Test on tablet (large screen)
- Test on landscape orientation
- Text should be readable on all

---

### **Test 2.7: Close Button**

**Steps:**
1. On PlayerScreen
2. Tap close button (X icon if present)
3. Or tap back button in AppBar

**Expected Result:**
- ✅ Navigation back to previous screen
- ✅ Audio stops playing
- ✅ No crashes

---

## 🔄 INTEGRATION TESTING

### **Test 3.1: Full Upload → Play Flow**

**Steps:**
1. Upload a PDF (Test 1.2)
2. Save the article
3. Go to HomeScreen
4. Find the uploaded article in the feed
5. Tap to open article detail
6. Tap "Listen"
7. PlayerScreen shows synced text
8. Play audio, watch sync

**Expected Result:**
- ✅ Uploaded article appears in feed
- ✅ Full flow works without crashes
- ✅ Sync works on user-uploaded content

---

### **Test 3.2: Multiple Uploads**

**Steps:**
1. Upload 3-5 different PDFs
2. Go to HomeScreen
3. All should appear in feed
4. Tap each one, play audio
5. Check sync on each

**Expected Result:**
- ✅ Multiple articles stored
- ✅ All sync correctly
- ✅ No performance degradation
- ✅ App memory usage reasonable

---

## 📊 PERFORMANCE TESTING

### **Test 4.1: App Startup Time**

**Steps:**
1. Close app completely
2. Reopen
3. Time from tap to HomeScreen visible

**Target:** < 2 seconds

---

### **Test 4.2: OCR Processing Time**

**Steps:**
1. Upload PDF
2. Time from selection to OCRReviewScreen

**Target:** < 10 seconds (depends on PDF size/complexity)

---

### **Test 4.3: Memory Usage**

**Steps:**
1. Launch app
2. Open Android Settings → App Info → Memory Usage
3. Check memory while:
   - Browsing articles
   - Playing audio
   - Uploading PDF
   - Scrolling synced text

**Target:** < 200MB steady state

---

### **Test 4.4: Audio Sync Accuracy**

**Steps:**
1. Play audio with synced text
2. Check if highlighted sentence matches what's being read
3. Test at different points (start, middle, end)

**Target:** ±2 seconds acceptable

---

## 🔐 PERMISSION TESTING

### **Test 5.1: Camera Permission**

**Steps:**
1. Tap "+" → "📷 Camera/Photos"
2. First time should prompt for camera permission
3. Grant permission
4. Camera opens

**Expected Result:**
- ✅ Permission prompt shown
- ✅ After grant, camera works
- ✅ If denied, shows error gracefully

---

### **Test 5.2: Photo Library Permission**

**Steps:**
1. Tap "+" → "📷 Camera/Photos" → Select from gallery
2. Should prompt for photo library access
3. Grant permission

**Expected Result:**
- ✅ Permission prompt shown
- ✅ Gallery opens after grant

---

### **Test 5.3: Storage Permission**

**Steps:**
1. Tap "+" → "📄 Upload PDF"
2. Should work with storage permission
3. Check in Android Settings → Permissions

**Expected Result:**
- ✅ Storage access works
- ✅ Files visible in file picker

---

## ❌ ERROR SCENARIOS

Test each error case:

1. **Corrupted PDF** → Shows error message
2. **Network timeout** → Shows network error
3. **Invalid image** → Shows error
4. **Storage full** → Shows space error
5. **Permission denied** → Shows permission error
6. **Audio file missing** → Shows graceful fallback

All should:
- ✅ Show user-friendly error message
- ✅ Allow retry
- ✅ Not crash app

---

## 📝 TEST REPORT TEMPLATE

```
GatiVani Testing Report
Date: [DATE]
Tester: [YOUR NAME]
Device: [DEVICE MODEL, Android VERSION]
App Version: 1.0.0

=== Phase 1: Upload + OCR ===
Test 1.1 (Home "+" Button): ✅ PASS / ❌ FAIL
Test 1.2 (PDF Upload): ✅ PASS / ❌ FAIL
Test 1.3 (Camera Upload): ✅ PASS / ❌ FAIL
Test 1.4 (Text Editing): ✅ PASS / ❌ FAIL
Test 1.5 (Categories): ✅ PASS / ❌ FAIL
Test 1.6 (Error Handling): ✅ PASS / ❌ FAIL

=== Phase 2: Sync Subtitles ===
Test 2.1 (Player Launch): ✅ PASS / ❌ FAIL
Test 2.2 (Audio Controls): ✅ PASS / ❌ FAIL
Test 2.3 (Synchronization): ✅ PASS / ❌ FAIL
Test 2.4 (Auto-Scroll): ✅ PASS / ❌ FAIL
Test 2.5 (Tap-to-Jump): ✅ PASS / ❌ FAIL
Test 2.6 (Text Quality): ✅ PASS / ❌ FAIL

=== Issues Found ===
1. [Issue description]
2. [Issue description]

=== Performance ===
- Startup time: [TIME]
- OCR time: [TIME]
- Memory usage: [AMOUNT]

Overall: ✅ READY FOR LAUNCH / ❌ NEEDS FIXES
```

---

## 🎉 SUCCESS CRITERIA

**Green Light Checklist:**
- [x] Phase 1 all tests pass
- [x] Phase 2 all tests pass
- [x] No crashes
- [x] Permissions work correctly
- [x] Sync accurate (±2 sec)
- [x] Performance acceptable
- [x] Error messages helpful

**If all checked:** ✅ Ready for Phase 3 (AI Features) or production launch!

---

**Testing Guide Generated:** 2026-05-12
