#!/bin/bash
# Build GatiVani APK with ZIP extraction fix

set -e  # Exit on any error

PROJECT_DIR="/Users/siddharthapothulapati/Projects/gativani-app"
cd "$PROJECT_DIR"

echo "========================================="
echo "GATIVANI BUILD - ZIP EXTRACTION FIX"
echo "========================================="
echo ""

echo "Step 1: Cleaning project..."
flutter clean || true
rm -rf build .dart_tool pubspec.lock || true
echo "✓ Clean complete"
echo ""

echo "Step 2: Getting dependencies..."
flutter pub get
echo "✓ Dependencies resolved"
echo ""

echo "Step 3: Building APK (Debug)..."
flutter build apk --debug
echo "✓ APK built successfully"
echo ""

echo "Step 4: Installing APK on device..."
adb install -r build/app/outputs/flutter-apk/app-debug.apk
echo "✓ APK installed"
echo ""

echo "Step 5: Clearing logcat buffer..."
adb logcat -c
echo "✓ Logcat cleared"
echo ""

echo "========================================="
echo "BUILD COMPLETE!"
echo "========================================="
echo ""
echo "To test the OCR with ZIP extraction:"
echo "1. Open the GatiVani app on your device"
echo "2. Go to 'Upload Content' screen"
echo "3. Select a newspaper image"
echo "4. Watch the terminal for logs - the ZIP should now extract properly!"
echo ""
echo "Monitor logs with:"
echo "adb logcat | grep -E '\[OCR|TTS\]'"
