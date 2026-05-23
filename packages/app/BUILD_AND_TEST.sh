#!/bin/bash
# Build GatiVani APK with comprehensive error logging

echo "=== CLEANING PROJECT ==="
flutter clean

echo -e "\n=== BUILDING APK (DEBUG) ==="
flutter build apk --debug

echo -e "\n=== INSTALLING APK ==="
adb install -r build/app/outputs/flutter-apk/app-debug.apk

echo -e "\n=== CLEARING LOGCAT BUFFER ==="
adb logcat -c

echo -e "\n=== WAITING 2 SECONDS FOR APP INIT ==="
sleep 2

echo -e "\n=== RUNNING LOGCAT WITH FILTERS ==="
echo "Filter: [OCR API] | [TTS] | [OCR] - for 30 seconds"
adb logcat | grep -E "\[OCR|TTS\]" &
LOGCAT_PID=$!

sleep 30

kill $LOGCAT_PID 2>/dev/null

echo -e "\n=== BUILD AND TEST COMPLETE ==="
