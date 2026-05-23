#!/bin/bash

# GatiVani APK Build Script
# Usage: ./build_apk.sh [debug|release]
# Default: debug (fastest for testing)

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BUILD_TYPE="${1:-debug}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  GatiVani APK Builder${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo -e "${YELLOW}Build Type:${NC} $BUILD_TYPE"
echo -e "${YELLOW}Project Dir:${NC} $PROJECT_DIR"
echo ""

# Validate build type
if [[ "$BUILD_TYPE" != "debug" && "$BUILD_TYPE" != "release" ]]; then
  echo -e "${RED}Error: Invalid build type. Use 'debug' or 'release'${NC}"
  exit 1
fi

# Check Flutter installation
if ! command -v flutter &> /dev/null; then
  echo -e "${RED}Error: Flutter is not installed or not in PATH${NC}"
  echo "Please install Flutter from: https://flutter.dev/docs/get-started/install"
  exit 1
fi

echo -e "${GREEN}✓ Flutter found${NC}"
echo ""

# Step 1: Get dependencies
echo -e "${BLUE}Step 1: Fetching dependencies...${NC}"
cd "$PROJECT_DIR"
flutter pub get
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Dependencies fetched${NC}"
else
  echo -e "${RED}✗ Failed to fetch dependencies${NC}"
  exit 1
fi
echo ""

# Step 2: Analyze code
echo -e "${BLUE}Step 2: Analyzing code...${NC}"
flutter analyze --no-fatal-infos
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Code analysis passed${NC}"
else
  echo -e "${YELLOW}⚠ Code analysis found issues (usually safe to ignore)${NC}"
fi
echo ""

# Step 3: Build APK
echo -e "${BLUE}Step 3: Building $BUILD_TYPE APK...${NC}"
echo "(This may take 2-3 minutes on first run)"
echo ""

if [ "$BUILD_TYPE" = "debug" ]; then
  flutter build apk --debug
  APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
elif [ "$BUILD_TYPE" = "release" ]; then
  flutter build apk --release
  APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
fi

if [ -f "$APK_PATH" ]; then
  echo -e "${GREEN}✓ APK built successfully${NC}"
  echo ""
  echo -e "${BLUE}================================================${NC}"
  echo -e "${GREEN}  BUILD COMPLETE!${NC}"
  echo -e "${BLUE}================================================${NC}"
  echo ""
  echo -e "${YELLOW}APK Location:${NC}"
  echo "  $APK_PATH"
  echo ""

  # Get APK size
  APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
  echo -e "${YELLOW}APK Size:${NC} $APK_SIZE"
  echo ""

  echo -e "${YELLOW}Next Steps:${NC}"
  echo "  1. Connect Android device via USB"
  echo "  2. Install: adb install -r $APK_PATH"
  echo "  3. Or manually install by copying APK to device"
  echo ""

  echo -e "${BLUE}Recommended Next Commands:${NC}"
  echo ""
  echo "  # Install via ADB:"
  echo "  adb install -r $APK_PATH"
  echo ""
  echo "  # Or view logs while testing:"
  echo "  flutter logs"
  echo ""

else
  echo -e "${RED}✗ Build failed${NC}"
  exit 1
fi
