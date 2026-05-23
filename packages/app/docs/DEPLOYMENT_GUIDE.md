# GatiVani Deployment Guide

Complete step-by-step guide for building and deploying GatiVani to web, iOS, and Android platforms.

**Version**: 1.0.0  
**Last Updated**: May 2026  
**Target Audience**: DevOps, Release Engineers, App Store Managers

---

## Table of Contents

1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [Web Deployment](#web-deployment)
3. [Android Deployment](#android-deployment)
4. [iOS Deployment](#ios-deployment)
5. [Environment Configuration](#environment-configuration)
6. [CI/CD Pipeline](#cicd-pipeline)
7. [Release Process](#release-process)
8. [Monitoring & Rollback](#monitoring--rollback)
9. [Troubleshooting](#troubleshooting)

---

## Pre-Deployment Checklist

### Code Quality

- [ ] All tests pass: `flutter test`
- [ ] No analyzer issues: `flutter analyze`
- [ ] Code is formatted: `flutter format lib/`
- [ ] No console errors/warnings
- [ ] Documentation updated
- [ ] Secrets not committed

### Functionality Testing

- [ ] Firebase initialization works
- [ ] Sarvam AI OCR working
- [ ] Sarvam AI TTS working
- [ ] Gemini summarization working
- [ ] Storage upload/download working
- [ ] News fetching working
- [ ] Caching working correctly
- [ ] Analytics logging working
- [ ] Push notifications working (Firebase)

### Device Testing

- [ ] iOS devices (iPhone 12, 13, 14)
- [ ] Android devices (API 21+, 10+, 12+)
- [ ] Web (Chrome, Firefox, Safari)
- [ ] Tablets (iPad, Android tablets)
- [ ] Various screen sizes
- [ ] Various network conditions

### Configuration

- [ ] Verify `AppConfig` for correct environment
- [ ] Verify `secrets.dart` has production credentials
- [ ] Update version number in `pubspec.yaml`
- [ ] Update build number
- [ ] Firebase configured for all platforms
- [ ] Push notifications enabled

### Performance

- [ ] App startup time < 2 seconds
- [ ] API response time < 1 second
- [ ] Crash rate < 0.1%
- [ ] Memory usage acceptable
- [ ] Battery consumption reasonable

---

## Web Deployment

### Prerequisites

```bash
flutter channel stable
flutter upgrade
flutter config --enable-web
```

### Build Web Release

```bash
# Clean previous builds
flutter clean

# Get dependencies
flutter pub get

# Build for web (production)
flutter build web --release

# Output: build/web/
```

### Web Build Configuration

```bash
# Custom build parameters
flutter build web \
  --release \
  --target lib/main.dart \
  --dart-define=ENVIRONMENT=production \
  --dart-define=DEBUG=false
```

### Deploy to Firebase Hosting

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login to Firebase
firebase login

# Initialize Firebase project (if not done)
firebase init hosting

# Configure firebase.json
{
  "hosting": {
    "public": "build/web",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ],
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ]
  }
}

# Deploy
firebase deploy --only hosting
```

### Deploy to Custom Server

```bash
# Build web app
flutter build web --release

# Copy build output to server
scp -r build/web/ user@server:/var/www/gativani/

# Configure nginx/Apache
# nginx.conf example:
server {
  listen 80;
  server_name gativani.com;

  location / {
    root /var/www/gativani;
    try_files $uri /index.html;
  }

  # Gzip compression
  gzip on;
  gzip_types text/plain text/css application/json application/javascript;
}

# Restart web server
systemctl restart nginx
```

### Web Performance Optimization

```bash
# Build with minification and tree-shaking
flutter build web --release --dart-define=FLAVOR=prod

# Enable service worker for PWA
flutter build web --web-renderer canvaskit --pwa-strategy offline-first
```

### Test Web Build Locally

```bash
# Serve web build locally
cd build/web
python3 -m http.server 8000

# Open browser
open http://localhost:8000
```

---

## Android Deployment

### Prerequisites

```bash
# Check Android setup
flutter doctor -v

# Install Android tools
flutter config --android-sdk /path/to/android/sdk
flutter config --android-studio-path /path/to/android/studio
```

### Prepare Android Build

#### 1. Update Build Information

**android/app/build.gradle**:
```gradle
android {
    compileSdkVersion 33
    
    defaultConfig {
        applicationId "com.example.gativani"
        minSdkVersion 21
        targetSdkVersion 33
        versionCode 1
        versionName "1.0.0"
        
        // Enable multidex
        multiDexEnabled true
    }
    
    signingConfigs {
        release {
            keyAlias System.getenv("KEY_ALIAS") ?: 'upload'
            keyPassword System.getenv("KEY_PASSWORD") ?: ''
            storeFile file(System.getenv("KEYSTORE_PATH") ?: 'keystore.jks')
            storePassword System.getenv("KEYSTORE_PASSWORD") ?: ''
        }
    }
    
    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
}
```

#### 2. Create Release Keystore

```bash
# Generate keystore for signing (one-time)
keytool -genkey -v \
  -keystore gativani-release.keystore \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias gativani-release

# Keep keystore file secure (add to .gitignore)
echo "gativani-release.keystore" >> .gitignore
```

#### 3. Configure Firebase for Android

**google-services.json**: Download from Firebase Console
- Place in `android/app/google-services.json`

**android/build.gradle**:
```gradle
buildscript {
  dependencies {
    classpath 'com.google.gms:google-services:4.3.15'
  }
}
```

**android/app/build.gradle**:
```gradle
apply plugin: 'com.google.gms.google-services'
```

### Build Android Release APK

```bash
# Build APK
flutter build apk --release

# Output: build/app/outputs/flutter-apk/app-release.apk

# Build split APKs for different CPU architectures
flutter build apk --release --split-per-abi

# Outputs:
# build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
# build/app/outputs/flutter-apk/app-x86-release.apk
# build/app/outputs/flutter-apk/app-x86_64-release.apk
```

### Build Android App Bundle (for Google Play)

```bash
# Build AAB (required for Play Store)
flutter build appbundle --release

# Output: build/app/outputs/bundle/release/app-release.aab

# View bundle details
bundletool build-apks \
  --bundle=app-release.aab \
  --output=app.apks \
  --ks=gativani-release.keystore \
  --ks-pass=pass:keystore-password \
  --ks-key-alias=gativani-release \
  --key-pass=pass:key-password
```

### Deploy to Google Play Store

#### 1. Set Up Google Play Account

- Create developer account: https://play.google.com/console
- Pay one-time fee ($25)
- Create app in Play Console

#### 2. Configure App Details

- App name: "GatiVani"
- Short description
- Full description
- Category: News
- Content rating questionnaire
- Privacy policy
- Support email

#### 3. Prepare Screenshots and Assets

Required for Play Store:
- **Screenshots**: 2-8 per device type (phone, tablet, wear)
- **Feature graphic**: 1024×500px
- **Icon**: 512×512px
- **Promo graphic**: 180×120px (optional)

#### 4. Upload to Play Store

```bash
# Use Play Console web interface or bundletool
bundletool upload-bundle \
  --bundle-path=app-release.aab \
  --key=service-account-key.json

# Or manually:
# 1. Go to Play Console
# 2. Select app: GatiVani
# 3. Release > Create new release
# 4. Upload build (AAB file)
# 5. Review app info
# 6. Submit for review
```

#### 5. Internal Testing

```bash
# 1. Create internal testing track
# 2. Upload app-release.aab
# 3. Invite internal testers
# 4. Wait for processing (5-30 minutes)
# 5. Test on devices
```

#### 6. Beta Testing

```bash
# 1. Create closed beta track
# 2. Set rollout percentage (10%)
# 3. Invite beta testers
# 4. Monitor feedback
# 5. Fix issues
# 6. Increase rollout if stable
```

#### 7. Production Release

```bash
# 1. Create production release
# 2. Review changes
# 3. Set rollout (10% → 50% → 100%)
# 4. Monitor crash reports
# 5. Be ready to rollback
```

### Android Size Optimization

```bash
# Analyze APK size
flutter analyze --prom

# View binary size
flutter build apk --analyze-size --release

# Shrink dependencies
# In pubspec.yaml, remove unused packages

# Enable code shrinking in build.gradle
minifyEnabled true
```

---

## iOS Deployment

### Prerequisites

```bash
# Check iOS setup
flutter doctor -v

# Xcode command line tools
xcode-select --install
```

### Prepare iOS Build

#### 1. Update Build Information

**ios/Runner/Info.plist**:
```xml
<key>CFBundleName</key>
<string>GatiVani</string>

<key>CFBundleShortVersionString</key>
<string>1.0.0</string>

<key>CFBundleVersion</key>
<string>1</string>

<key>CFBundleIdentifier</key>
<string>com.example.gativani</string>

<!-- Required for background audio -->
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>

<!-- Required for notifications -->
<key>UIRequiredDeviceCapabilities</key>
<array>
  <string>remote-notification</string>
</array>
```

#### 2. Configure Firebase for iOS

**GoogleService-Info.plist**: Download from Firebase Console
- Place in `ios/Runner/GoogleService-Info.plist`
- Add to Xcode project

#### 3. Sign App for Development

```bash
# Set up signing in Xcode
# 1. Open ios/Runner.xcworkspace
# 2. Select Runner project
# 3. Select Target: Runner
# 4. Signing & Capabilities tab
# 5. Select Team
# 6. Update Bundle Identifier

# Or via Flutter
flutter pub get
open ios/Runner.xcworkspace
```

#### 4. Update Pod Dependencies

```bash
cd ios
pod install
cd ..
```

### Build iOS Release

#### 1. Build for TestFlight

```bash
# Build for TestFlight
flutter build ios --release

# Archive using Xcode
open ios/Runner.xcworkspace

# Or use fastlane
gem install fastlane
cd ios
fastlane init
cd ..
```

#### 2. Using Xcode

```bash
# Open project
open ios/Runner.xcworkspace

# Product > Scheme > Select "Runner" + "Release"
# Product > Destination > Generic iOS Device
# Product > Archive

# Open Organizer
# Window > Organizer
# Select archive
# "Distribute App"
# Choose TestFlight & App Store
```

#### 3. Using fastlane (Recommended)

```bash
# Install fastlane
sudo gem install fastlane -NV

# Initialize fastlane
cd ios
fastlane init

# fastlane/Fastfile
default_platform(:ios)

platform :ios do
  desc "Push a new release build to the App Store"
  lane :release do
    build_app(
      workspace: "Runner.xcworkspace",
      scheme: "Runner",
      configuration: "Release",
      derived_data_path: "build",
      destination: "generic/platform=iOS",
      export_method: "app-store",
      output_directory: "build",
      output_name: "GatiVani.ipa"
    )
  end
end

# Build and deploy
fastlane ios release
```

### Deploy to App Store

#### 1. Set Up App Store Connect

- Create Apple Developer account
- Configure bundle identifier: `com.example.gativani`
- Create App ID in Developer Portal
- Create app in App Store Connect

#### 2. Configure App Information

- App name
- Subtitle
- Description
- Keywords
- Category
- Privacy policy URL
- Support URL

#### 3. Upload to TestFlight

```bash
# Via Xcode Organizer
# 1. Archive app
# 2. Distribute App
# 3. Select TestFlight & App Store
# 4. Upload

# Via Transporter (Apple tool)
transporter -m upload -f GatiVani.ipa -u apple-id@example.com
```

#### 4. Internal Testing

```bash
# In App Store Connect:
# 1. TestFlight > Internal Testing
# 2. Upload build
# 3. Add internal testers
# 4. Wait for processing (30 mins - 1 hour)
# 5. Test on devices
```

#### 5. Beta Testing

```bash
# 1. TestFlight > External Testing
# 2. Create beta group
# 3. Add testers (external)
# 4. Send TestFlight invite
# 5. Monitor feedback
```

#### 6. Submit for App Review

```bash
# 1. App Store > Version
# 2. Review all information
# 3. Select "Prepare for Submission"
# 4. Add release notes
# 5. Submit for Review

# Typical review time: 24 hours
```

#### 7. Release to App Store

```bash
# After approval:
# 1. App Store > Version
# 2. Release type: Manual Release
# 3. "Release this Version"
# 4. Confirm
```

### iOS Size Optimization

```bash
# Build and analyze size
flutter build ios --release --verbose

# Strip debug symbols
strip -x build/ios/Release-iphoneos/Runner.app/Runner

# Use App Thinning (automatic in App Store)
```

---

## Environment Configuration

### Configuration Management

Create environment-specific config files:

```dart
// lib/config/environments/dev.dart
class DevConfig {
  static const String appName = 'GatiVani Dev';
  static const String environment = 'development';
  static const bool enableDebugLogging = true;
  static const String firebaseProjectId = 'gativani-dev';
}

// lib/config/environments/staging.dart
class StagingConfig {
  static const String appName = 'GatiVani Staging';
  static const String environment = 'staging';
  static const bool enableDebugLogging = false;
  static const String firebaseProjectId = 'gativani-staging';
}

// lib/config/environments/prod.dart
class ProductionConfig {
  static const String appName = 'GatiVani';
  static const String environment = 'production';
  static const bool enableDebugLogging = false;
  static const String firebaseProjectId = 'gativani-prod';
}
```

### Build Flavors

**android/app/build.gradle**:
```gradle
flavorDimensions "environment"

productFlavors {
  dev {
    dimension "environment"
    applicationIdSuffix ".dev"
    versionNameSuffix "-dev"
  }
  
  staging {
    dimension "environment"
    applicationIdSuffix ".staging"
    versionNameSuffix "-staging"
  }
  
  prod {
    dimension "environment"
  }
}
```

**Building with flavors**:
```bash
# Development build
flutter build apk --flavor dev --release

# Staging build
flutter build apk --flavor staging --release

# Production build
flutter build apk --flavor prod --release
```

---

## CI/CD Pipeline

### GitHub Actions Example

**.github/workflows/build.yml**:
```yaml
name: Build and Deploy

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [develop]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.10.0'
      
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test --coverage
      - run: flutter build web --release
  
  deploy_web:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      
      - run: flutter pub get
      - run: flutter build web --release
      
      - uses: FirebaseExtended/action-hosting-deploy@v0
        with:
          repoToken: '${{ secrets.GITHUB_TOKEN }}'
          firebaseServiceAccount: '${{ secrets.FIREBASE_SERVICE_ACCOUNT }}'
          channelId: live
          projectId: gativani-prod
  
  build_android:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      
      - run: flutter pub get
      - run: flutter build appbundle --release
      
      - uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJsonPlainText: '${{ secrets.PLAY_STORE_UPLOAD_KEY }}'
          packageName: com.example.gativani
          releaseFiles: 'build/app/outputs/bundle/release/app-release.aab'
          track: internal
```

---

## Release Process

### Version Numbering

Follow Semantic Versioning: `MAJOR.MINOR.PATCH`

```dart
// pubspec.yaml
version: 1.0.0+1

// Build number increments for each release
// Format: major.minor.patch+buildnumber
```

### Release Checklist

1. [ ] Update version in `pubspec.yaml`
2. [ ] Update `CHANGELOG.md`
3. [ ] Run full test suite
4. [ ] Create release branch: `release/1.0.0`
5. [ ] Build for all platforms
6. [ ] Internal testing (7 days minimum)
7. [ ] Beta testing (3-7 days minimum)
8. [ ] Submit for review
9. [ ] After approval, release to production
10. [ ] Monitor crash reports and user feedback

### Release Notes Template

```markdown
# GatiVani 1.0.0 Release Notes

## What's New
- Feature 1: Description
- Feature 2: Description
- Improvement 1: Description

## Bug Fixes
- Fixed issue with...
- Resolved problem with...

## Performance Improvements
- Reduced app size by X%
- Improved startup time by X%

## Known Issues
- Known issue 1
- Known issue 2

## Upgrade Notes
- Users will need to...
- Please ensure...

## Support
- Report issues: [GitHub Issues](...)
- Contact support: support@example.com
```

---

## Monitoring & Rollback

### Post-Release Monitoring

```bash
# Monitor Firebase Crashlytics
# https://console.firebase.google.com

# Check metrics:
# - Crash rate (target: < 0.1%)
# - Performance metrics
# - Startup time
# - API latency

# Monitor user feedback:
# - App Store reviews
# - Google Play reviews
# - Support emails
# - GitHub issues
```

### Rollback Procedure

**If Critical Bug Discovered**:

1. **Immediate Actions**:
   ```bash
   # Stop rollout (if in gradual rollout)
   # In Play Store: Release > Version > Stop Rollout
   # In App Store: Version > Release History > Pause Release
   ```

2. **Communicate**:
   - Update status page
   - Notify support team
   - Post on social media
   - Email key users

3. **Quick Fix**:
   ```bash
   # Create hotfix branch
   git checkout -b hotfix/bug-fix
   # Fix bug
   # Build and test
   # Create new release
   ```

4. **Revert if Necessary**:
   ```bash
   # Revert version in stores
   # Restore previous version as current
   # Re-release previous stable version
   ```

---

## Troubleshooting

### Android Issues

**Issue**: "Build failed: java.lang.OutOfMemoryError"
```bash
# Increase memory for gradle
export GRADLE_OPTS="-Xmx4096m"
flutter build appbundle --release
```

**Issue**: "Manifest merge failed"
```bash
# Check conflicting dependencies
# Update build.gradle minSdkVersion/targetSdkVersion
# Resolve dependency conflicts
```

### iOS Issues

**Issue**: "Code signing failed"
```bash
# Re-setup signing
# 1. Xcode > Runner > Signing & Capabilities
# 2. Select correct team
# 3. Update bundle identifier
```

**Issue**: "Pod install fails"
```bash
cd ios
rm Podfile.lock
pod repo update
pod install
cd ..
```

### Web Issues

**Issue**: "Blank page after deploy"
```bash
# Check base href in index.html
# Ensure correct path for routing
# Check browser console for errors
```

**Issue**: "404 on refresh"
```bash
# Configure web server to rewrite all requests to index.html
# nginx: try_files $uri /index.html;
# Apache: <IfModule mod_rewrite.c>
```

---

## Additional Resources

- [Flutter Deployment Docs](https://flutter.dev/docs/deployment)
- [Google Play Console Help](https://support.google.com/googleplay)
- [App Store Connect Help](https://help.apple.com/app-store-connect)
- [Firebase Hosting](https://firebase.google.com/docs/hosting)

---

**Ready to Deploy!**
