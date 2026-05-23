# Quick Build & Test Guide

## Step 1: Clean & Build
Run in Terminal:
```bash
cd ~/Projects/gativani-app
flutter clean
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## Step 2: Clear Logs
```bash
adb logcat -c
```

## Step 3: Trigger OCR Upload
1. Open GatiVani app on your device
2. Go to "Upload Content" screen
3. Select a newspaper image (PDF or image)
4. Watch Terminal for logs

## Step 4: Capture Full Error
The logs now show full response bodies for:
- Presigned URL request → `[OCR API] Upload URLs body:`
- File upload attempt → `[OCR API] File upload body:`
- Status polling → `[OCR API] Full status response:`
- Download URLs → `[OCR API] Download URLs body:`

**CRITICAL**: The Azure error message should now be fully visible. Look for the XML error details in `[OCR API] File upload body:`.

## Key Logs to Watch:
```
[OCR API] Got presigned URL successfully
[OCR API] File upload response: 400
[OCR API] File upload body: [FULL ERROR HERE - THIS IS WHAT WE NEED]
```

The XML response from Azure will tell us exactly what header or format is wrong for the presigned URL PUT.
