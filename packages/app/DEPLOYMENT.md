# GatiVani Production Deployment Guide

This guide covers the complete deployment infrastructure for GatiVani across web, Android, and iOS platforms.

## Table of Contents

1. [Quick Start](#quick-start)
2. [GitHub Actions CI/CD Pipeline](#github-actions-cicd-pipeline)
3. [Environment Management](#environment-management)
4. [Build Configuration](#build-configuration)
5. [Firebase Deployment](#firebase-deployment)
6. [App Store Submissions](#app-store-submissions)
7. [Monitoring & Observability](#monitoring--observability)
8. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Prerequisites

- Flutter SDK (v3.22.0+)
- Android SDK (for Android builds)
- Xcode 14+ (for iOS builds)
- Firebase CLI (`npm install -g firebase-tools`)
- Git

### Initial Setup

```bash
# Clone and setup
git clone https://github.com/your-org/gativani-app.git
cd gativani-app

# Install dependencies
flutter pub get

# Install Firebase CLI
npm install -g firebase-tools

# Login to Firebase
firebase login
```

### Deploy Web (Staging)

```bash
# Build web
flutter build web --release

# Deploy to staging
firebase deploy --only hosting:gativani-staging --token $FIREBASE_TOKEN
```

### Deploy Web (Production)

```bash
# Tag release
git tag v1.0.0
git push origin v1.0.0

# GitHub Actions automatically deploys on tag push
```

---

## GitHub Actions CI/CD Pipeline

### Pipeline Stages

The CI/CD pipeline (.github/workflows/ci-cd.yml) runs the following stages:

#### 1. Code Quality & Testing
- **Analyze**: Flutter analyzer and linting
- **Test**: Unit tests, widget tests, coverage reports

#### 2. Build Artifacts
- **Build Web**: Flutter web release build
- **Build Android**: AAB (App Bundle) + APK builds
- **Build iOS**: iOS archive (.xcarchive)

#### 3. Deployment
- **Deploy Staging**: On develop branch push
- **Deploy Production**: On version tag (v*.*)
- **Submit to Stores**: Android Play Store + Apple App Store

#### 4. Notifications
- Slack notifications for pipeline status

### Triggering Deployments

#### Automatic Deployments

**Staging** - Triggered on push to `develop` branch:
```bash
git checkout develop
git commit -m "Feature: xyz"
git push origin develop
# → Automatically deploys to gativani-staging Firebase Hosting
```

**Production** - Triggered on version tag:
```bash
git tag v1.0.1
git push origin v1.0.1
# → Automatically deploys to production Firebase Hosting
# → Submits to Google Play Store and App Store
```

#### Manual Deployments

Trigger workflow_dispatch for manual deployment:
```bash
# Via GitHub CLI
gh workflow run ci-cd.yml -f deploy_to=production

# Or use GitHub UI: Actions → CI/CD Pipeline → Run workflow
```

### Required GitHub Secrets

Configure these in: Settings → Secrets and variables → Actions

```
GCP_PROJECT_ID              # Google Cloud Project ID
GCP_SA_KEY                  # GCP Service Account JSON
FIREBASE_TOKEN              # Firebase CLI token
FIREBASE_HOSTING_KEY        # Firebase Hosting API key

ANDROID_KEYSTORE_BASE64     # Android signing keystore (base64)
ANDROID_KEY_ALIAS           # Android key alias
ANDROID_KEY_PASSWORD        # Android key password
ANDROID_STORE_PASSWORD      # Android store password
GOOGLE_PLAY_KEY_BASE64      # Google Play API key (base64)

IOS_CERTIFICATE_BASE64      # iOS certificate (base64)
IOS_PROVISIONING_PROFILE_BASE64  # iOS provisioning profile (base64)
APP_STORE_CONNECT_API_KEY   # App Store Connect API key
FASTLANE_USER               # Apple ID
FASTLANE_PASSWORD           # Apple ID password

SLACK_WEBHOOK               # Slack webhook for notifications
```

---

## Environment Management

### Environment Files

Three environment configurations:

```
.env.development    # Local development
.env.staging       # Staging/UAT environment
.env.production    # Production environment
.env.example       # Template (tracked in git)
```

### Loading Environments

**Development (default)**:
```bash
flutter run
```

**Staging**:
```bash
flutter run --dart-define-from-file=.env.staging
```

**Production**:
```bash
flutter run --dart-define-from-file=.env.production
```

### Environment Variables

Key variables in each environment file:

```dart
// Firebase Configuration
FIREBASE_API_KEY
FIREBASE_PROJECT_ID
FIREBASE_STORAGE_BUCKET
FIREBASE_AUTH_DOMAIN

// AI Services
SARVAM_API_KEY              # OCR & TTS
GEMINI_API_KEY              # Summarization

// App Configuration
APP_ENV                     # 'development' | 'staging' | 'production'
LOG_LEVEL                   # 'debug' | 'info' | 'warning'
ENABLE_ANALYTICS            # true/false
ENABLE_CRASH_REPORTING      # true/false
```

### Security Best Practices

1. **Never commit `.env` files** - Only `.env.example` is tracked
2. **Use CI/CD secrets** - Store sensitive keys in GitHub Secrets
3. **Rotate keys regularly** - Update API keys every 90 days
4. **Audit access** - Review who has access to secrets
5. **Use environment-specific keys** - Different keys per environment

---

## Build Configuration

### Web Build

```bash
# Development
flutter build web

# Production
flutter build web --release \
  --dart-define=ENVIRONMENT=production \
  --dart-define-from-file=.env.production

# Size analysis
flutter build web --release --analyze-size
```

**Optimization flags**:
- `--split-debug-info` - Separate debug symbols
- `--dart-define=DART_DEFINES=...` - Optimize for size
- `--web-renderer=canvaskit` or `html` - Rendering engine

### Android Build

```bash
# Development APK
flutter build apk --debug

# Release AAB (for Play Store)
flutter build appbundle --release

# Release APK
flutter build apk --release

# Target specific architecture
flutter build apk --release --target-platform android-arm64
```

**Signing configuration** (android/app/build.gradle):
```gradle
signingConfigs {
    release {
        keyAlias System.getenv("ANDROID_KEY_ALIAS") ?: System.getProperty("ANDROID_KEY_ALIAS")
        keyPassword System.getenv("ANDROID_KEY_PASSWORD") ?: System.getProperty("ANDROID_KEY_PASSWORD")
        storeFile file(System.getenv("ANDROID_KEYSTORE_PATH") ?: System.getProperty("ANDROID_KEYSTORE_PATH"))
        storePassword System.getenv("ANDROID_STORE_PASSWORD") ?: System.getProperty("ANDROID_STORE_PASSWORD")
    }
}
```

### iOS Build

```bash
# Development
flutter build ios

# Production (requires signing)
flutter build ios --release

# Archive for App Store
cd ios
xcodebuild -workspace Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -archivePath build/Runner.xcarchive \
  archive
```

**Code signing**:
- Configure in Xcode: Runner → Build Settings
- Provisioning profile: Development or Distribution
- Certificate: iOS App Development or iOS Distribution

---

## Firebase Deployment

### Firebase Setup

```bash
# Initialize Firebase project
firebase init

# Select hosting, functions, storage, firestore
# Choose existing project (gativani-prod)
```

### Firestore Security Rules

Rules defined in `firestore.rules`:

```firestore
match /users/{userId} {
  allow read, write: if request.auth.uid == userId;
}

match /newspapers/{newspaperId} {
  allow read: if true;
  allow write: if request.auth.token.admin == true;
}
```

Deploy rules:
```bash
firebase deploy --only firestore:rules
```

### Storage Rules

Rules defined in `storage.rules`:

```storage
match /audio/{allPaths=**} {
  allow read: if true;
  allow write: if request.auth.token.admin == true;
}
```

Deploy rules:
```bash
firebase deploy --only storage
```

### Hosting Configuration

Defined in `firebase.json`:

```json
{
  "hosting": {
    "gativani": {
      "public": "build/web",
      "rewrites": [{"source": "**", "destination": "/index.html"}],
      "headers": [{
        "source": "/static/**",
        "headers": [{"key": "Cache-Control", "value": "public, max-age=31536000, immutable"}]
      }]
    }
  }
}
```

### Deploy to Firebase Hosting

```bash
# Staging
firebase deploy --only hosting:gativani-staging --token $FIREBASE_TOKEN

# Production
firebase deploy --only hosting:gativani --token $FIREBASE_TOKEN

# Rollback
firebase hosting:channels:list
firebase hosting:channels:deploy old-version
```

---

## App Store Submissions

### Android: Google Play Store

#### Prepare

1. Create Google Play developer account ($25)
2. Generate signing key:
```bash
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10950 \
  -alias upload-key
```

3. Create app bundle:
```bash
flutter build appbundle --release
```

4. Upload to Play Console:
   - Create new app
   - Fill app details (title, description, screenshots)
   - Upload app bundle (build/app/outputs/bundle/release/app-release.aab)
   - Set up store listing, pricing, distribution

#### Submission Checklist

- [ ] App title and short description
- [ ] Full description (4000 chars max)
- [ ] Screenshots (min 2, max 8)
- [ ] Feature graphic (1024x500)
- [ ] Category and content rating
- [ ] Privacy policy URL
- [ ] Content rating questionnaire
- [ ] Target audience
- [ ] Permissions justification

#### Using Fastlane

```ruby
# android/fastlane/Fastfile
default_platform(:android)

platform :android do
  desc "Submit to Google Play internal testing"
  lane :deploy_internal do
    build_android_app(
      task: "bundle",
      project_dir: "android/"
    )
    
    upload_to_play_store(
      track: "internal",
      json_key: "fastlane/key.json",
      skip_upload_changelogs: true
    )
  end
end
```

Deploy:
```bash
cd android
bundle exec fastlane deploy_internal
```

### iOS: Apple App Store

#### Prepare

1. Register Apple Developer account ($99/year)
2. Create certificates and provisioning profiles in Apple Developer Portal
3. Create iOS app in App Store Connect
4. Archive app:
```bash
cd ios
xcodebuild -workspace Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -archivePath build/Runner.xcarchive \
  archive
```

5. Upload to App Store Connect

#### Submission Checklist

- [ ] App name and subtitle
- [ ] Description (4000 chars max)
- [ ] Keywords (100 chars max)
- [ ] Support URL
- [ ] Privacy policy URL
- [ ] Screenshots (min 2 screens, min 1242x2208)
- [ ] Preview video (optional)
- [ ] Category
- [ ] Age rating
- [ ] License agreement
- [ ] Contact information
- [ ] Demo account (if needed)
- [ ] Notes for reviewer

#### Using Fastlane

```ruby
# ios/fastlane/Fastfile
default_platform(:ios)

platform :ios do
  desc "Submit to TestFlight"
  lane :deploy_testflight do
    build_app(
      workspace: "Runner.xcworkspace",
      scheme: "Runner",
      configuration: "Release",
      export_method: "app-store"
    )
    
    upload_to_testflight(
      api_key_path: "fastlane/app_store_connect_api_key.json",
      skip_waiting_for_build_processing: true
    )
  end
  
  desc "Submit to App Store"
  lane :submit_for_review do
    deliver(
      api_key_path: "fastlane/app_store_connect_api_key.json",
      skip_binary_upload: true,
      automatic_release: false
    )
  end
end
```

Deploy:
```bash
cd ios
bundle exec fastlane deploy_testflight
```

---

## Monitoring & Observability

### Firebase Crashlytics

Monitor app crashes in real-time:

```dart
// Enable in production
await FirebaseService().initializeCrashlytics();

// Log custom error
FirebaseCrashlytics.instance.recordError(
  exception,
  stackTrace,
  reason: 'Custom error context'
);
```

Dashboard: Firebase Console → Crashlytics

### Firebase Analytics

Track user behavior and events:

```dart
// Log event
FirebaseAnalytics.instance.logEvent(
  name: 'article_listened',
  parameters: {
    'newspaper_id': newspaperId,
    'duration_seconds': durationInSeconds,
  },
);
```

Dashboard: Firebase Console → Analytics

### Performance Monitoring

Monitor app performance:

```dart
// Trace custom metric
final trace = FirebasePerformance.instance.newTrace('article_load');
await trace.start();
// ... load article
await trace.stop();
```

Dashboard: Firebase Console → Performance

### Error Tracking (Sentry)

Configure for production:

```dart
import 'package:sentry_flutter/sentry_flutter.dart';

void main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://your-sentry-dsn';
      options.environment = Environment.production.name;
    },
    appRunner: () => runApp(const MyApp()),
  );
}
```

Dashboard: sentry.io

---

## Troubleshooting

### Build Issues

**Flutter pub get fails**:
```bash
flutter clean
flutter pub cache clean
flutter pub get
```

**Gradle/Android build fails**:
```bash
cd android
./gradlew clean
./gradlew build
```

**iOS pod issues**:
```bash
cd ios
rm Podfile.lock
pod install
```

### Deployment Issues

**Firebase deployment fails**:
```bash
firebase login --reauth
firebase deploy --debug
```

**GitHub Actions secrets not accessible**:
- Verify secrets are added in Settings → Secrets
- Check organization/repository scope
- Rerun workflow

**App signing issues**:
- Android: Verify keystore exists and passwords are correct
- iOS: Check provisioning profile in Xcode

### Performance Issues

**Large build size**:
```bash
# Analyze
flutter build web --analyze-size

# Optimize
flutter build web --release \
  --dart-define=DART_VM_PROFILE=false \
  --split-debug-info
```

**Slow tests**:
```bash
# Run tests in parallel
flutter test --exclude-tags=slow --concurrency=4
```

---

## Release Checklist

Before every production release:

- [ ] Update version in pubspec.yaml
- [ ] Update CHANGELOG.md
- [ ] Run full test suite
- [ ] Test on staging environment
- [ ] Get stakeholder approval
- [ ] Create release tag
- [ ] Monitor Crashlytics for 24 hours
- [ ] Post-release notes in Slack
- [ ] Update documentation

---

## Support

For issues or questions:

1. Check logs: `flutter logs`
2. Review GitHub Actions output
3. Check Firebase Console
4. Consult deployment troubleshooting section
5. Contact DevOps team

