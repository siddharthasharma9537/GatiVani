#!/bin/bash
cd "$(dirname "$0")"
export PATH="/Users/siddharthapothulapati/flutter/bin:$PATH"
echo "Starting Flutter APK build..."
flutter clean
flutter pub get
flutter build apk --debug
echo "Build complete! APK location: build/app/outputs/flutter-apk/app-debug.apk"
read -p "Press Enter to close..."
