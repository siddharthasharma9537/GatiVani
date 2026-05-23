# GatiVani App Store Submission Checklist

Complete this checklist before submitting to Google Play Store and Apple App Store.

## Pre-Submission Requirements

### Legal & Compliance

- [ ] **Privacy Policy** - Posted at https://gativani.app/privacy
  - [ ] Data collection practices documented
  - [ ] Third-party service usage disclosed
  - [ ] User rights and choices explained
  - [ ] Contact information for privacy inquiries
  
- [ ] **Terms of Service** - Posted at https://gativani.app/terms
  - [ ] User responsibilities
  - [ ] Intellectual property rights
  - [ ] Limitation of liability
  - [ ] Dispute resolution

- [ ] **GDPR Compliance** (if EU users)
  - [ ] Consent mechanism for data processing
  - [ ] Data subject rights implementation
  - [ ] Privacy impact assessment
  - [ ] Data processing agreement with vendors

- [ ] **Children's Privacy** (COPPA/GDPR)
  - [ ] Age gate implemented (if applicable)
  - [ ] Parental consent mechanism
  - [ ] Limited tracking/analytics
  - [ ] No persistent identifiers

### App Content

- [ ] **Content Rating**
  - [ ] IAMAI/PlayRating questionnaire completed
  - [ ] ESRB rating obtained
  - [ ] Age-appropriate content confirmed
  - [ ] No prohibited content

- [ ] **Localization**
  - [ ] UI translated to supported languages
  - [ ] Strings properly localized
  - [ ] RTL language support (if applicable)
  - [ ] Cultural sensitivities reviewed

- [ ] **Accessibility**
  - [ ] Screen reader support tested
  - [ ] Contrast ratios meet WCAG AA
  - [ ] Touch targets 48dp minimum
  - [ ] Keyboard navigation working

### Testing

- [ ] **Functional Testing**
  - [ ] All features tested on target devices
  - [ ] Offline functionality verified
  - [ ] Network error handling works
  - [ ] Authentication flows tested

- [ ] **Performance Testing**
  - [ ] App launches in < 2 seconds
  - [ ] No jank or stuttering
  - [ ] Memory leaks addressed
  - [ ] Battery usage optimized
  - [ ] Data usage acceptable

- [ ] **Compatibility Testing**
  - [ ] Android 8.0 (API 26) and above
  - [ ] iOS 12.0 and above
  - [ ] Various screen sizes tested
  - [ ] Multiple device configurations

- [ ] **Security Testing**
  - [ ] HTTPS used for all network requests
  - [ ] Sensitive data encrypted
  - [ ] No hardcoded credentials
  - [ ] Permissions justified
  - [ ] Certificate pinning implemented

---

## Google Play Store Submission

### Developer Account Setup

- [ ] Google Play Developer Account created ($25 one-time)
- [ ] Payment method added
- [ ] Developer profile completed
- [ ] Two-factor authentication enabled
- [ ] App consent page reviewed and accepted

### App Release Setup

- [ ] App name (50 chars max) - "GatiVani - Audio Newspaper"
- [ ] Short description (80 chars max)
  ```
  Listen to your favorite newspapers during your daily commute
  ```
- [ ] Full description (4000 chars max)
  ```
  GatiVani brings your favorite newspapers to life through audio.
  
  Features:
  - Real-time newspaper updates
  - High-quality audio narration
  - Multiple language support
  - Offline listening capability
  - Customizable playback speed
  - Resume from where you left off
  
  Perfect for your morning commute, workout, or whenever you want
  to stay informed on the go.
  ```

### Store Listing

- [ ] **Language**: English (primary)
- [ ] **Category**: News & Magazines
- [ ] **Content Rating**: 
  - [ ] Questionnaire completed
  - [ ] Rating: [Your rating]

### Graphics & Assets

- [ ] **App Icon** (512x512 PNG)
  - [ ] No text overlay
  - [ ] Clear at small sizes
  - [ ] Safe area compliant
  
- [ ] **Feature Graphic** (1024x500 JPG/PNG)
  - [ ] Eye-catching design
  - [ ] Brand identity clear
  - [ ] Readable at small sizes

- [ ] **Screenshots** (minimum 2, maximum 8)
  - [ ] 1080x1920 or 1440x2560
  - [ ] Show key features
  - [ ] Landscape & portrait (if applicable)
  - [ ] With or without text descriptions

  Required screenshots:
  - [ ] Home screen with newspapers
  - [ ] Audio player interface
  - [ ] Settings/preferences screen

- [ ] **Play Store Listing Video** (optional, up to 30 seconds)
  - [ ] Shows key features
  - [ ] Professional quality
  - [ ] No app store reviews/ads

### Build Submission

- [ ] **Build APK/AAB**
  ```bash
  flutter build appbundle --release
  ```
  
- [ ] **Version Code**: Incremented from previous (e.g., 100, 101, 102)
- [ ] **Version Name**: Semantic versioning (e.g., 1.0.0)
- [ ] **Package Name**: `com.gativani.app`
- [ ] **Min SDK**: 24 (Android 7.0)
- [ ] **Target SDK**: 34 (Latest)

- [ ] **Signing**
  - [ ] App signed with release key
  - [ ] Same key as previous versions
  - [ ] Key stored securely

### Content Declarations

- [ ] **Privacy Policy URL**: https://gativani.app/privacy
- [ ] **News App Declaration** (if applicable)
- [ ] **Ads Declaration** (if using ads)
  - [ ] Ad networks declared
  - [ ] Consent flow present

### Permissions Justification

For each permission requested:

- [ ] **INTERNET**
  - Reason: Fetch articles and stream audio
  
- [ ] **RECORD_AUDIO**
  - Reason: [If voice search/commands]
  
- [ ] **READ_EXTERNAL_STORAGE**
  - Reason: Import newspaper PDFs
  
- [ ] **WRITE_EXTERNAL_STORAGE**
  - Reason: Cache audio files
  
- [ ] **ACCESS_NETWORK_STATE**
  - Reason: Check connection status
  
- [ ] **CHANGE_NETWORK_STATE**
  - Reason: [If applicable]

### Distribution

- [ ] **Countries**: Select all (or specific regions)
- [ ] **Testing on device(s)**:
  - [ ] Pixel 6 (minimum)
  - [ ] Samsung Galaxy (alternative)
  - [ ] Other Android tablets

### Rollout Strategy

- [ ] **Staged Rollout** (recommended for first release)
  - [ ] 5% rollout to 0.1M+ users
  - [ ] Monitor crash reports
  - [ ] Expand to 25%, 100% after 24 hours

- [ ] **Monitoring Plan**
  - [ ] Crash reports checked daily
  - [ ] ANR (Application Not Responding) monitored
  - [ ] User reviews read regularly

---

## Apple App Store Submission

### Developer Account Setup

- [ ] Apple Developer Program account ($99/year)
- [ ] Organization/Individual verified
- [ ] Certificates & Identifiers created
- [ ] App ID configured (`com.gativani.app`)
- [ ] Provisioning profiles created

### Signing Certificates

- [ ] **iOS Distribution Certificate**
  - [ ] Created in Apple Developer Portal
  - [ ] Imported to Xcode
  - [ ] Valid for 1 year
  
- [ ] **Provisioning Profile** (App Store Distribution)
  - [ ] Includes distribution certificate
  - [ ] Includes App ID
  - [ ] Downloaded and installed

### App Information

- [ ] **App Name**: "GatiVani" (30 chars max)
- [ ] **Subtitle**: "Audio Newspaper Companion" (30 chars max)
- [ ] **Bundle ID**: `com.gativani.app`
- [ ] **Version**: `1.0.0`
- [ ] **Build**: `1`

### App Store Connect Setup

- [ ] Created new app in App Store Connect
- [ ] Selected category: News
- [ ] Configured bundled apps (if applicable)
- [ ] Set up Family Sharing (if applicable)

### Metadata

- [ ] **Description** (4000 chars max)
  ```
  GatiVani brings your favorite newspapers to life through audio.
  
  Features:
  - Real-time newspaper updates
  - High-quality audio narration
  - Multiple language support (English, Telugu, Hindi)
  - Offline listening capability
  - Customizable playback speed (0.75x to 1.5x)
  - Resume playback
  - Bookmarking articles
  - Smart summarization
  
  Listen while you commute, exercise, or whenever you want to stay
  informed without reading.
  ```

- [ ] **Keywords** (100 chars max)
  ```
  news, audio, newspapers, podcast, reading, hindi, telugu
  ```

- [ ] **Support URL**: `https://gativani.app/support`
- [ ] **Marketing URL**: `https://gativani.app`
- [ ] **Privacy Policy URL**: `https://gativani.app/privacy`

### Graphics & Screenshots

- [ ] **App Icon** (1024x1024 PNG)
  - [ ] Rounded corners auto-applied
  - [ ] No transparency required
  - [ ] All safe area compliant
  
- [ ] **Screenshots** (minimum 2 screens, maximum 10)
  - [ ] 1125x2436 (iPhone) minimum
  - [ ] 2048x2732 (iPad) if supported
  - [ ] Show key features
  - [ ] Optional text overlay
  - [ ] All required screens included

  Required screenshots:
  - [ ] Newspaper list/home screen
  - [ ] Audio player in action
  - [ ] Bookmarks/saved articles

- [ ] **App Preview** (optional, 30 seconds)
  - [ ] Professional quality video
  - [ ] No app store reviews/ratings
  - [ ] Shows key interactions
  - [ ] MP4 or MOV format

### Content Rating

- [ ] **Age Rating Questionnaire**
  - [ ] Answered all questions honestly
  - [ ] Category determined by Apple
  - [ ] Rating: [4+, 12+, 17+, or 18+]

- [ ] **Content Rights**
  - [ ] Confirmed all rights to content
  - [ ] No third-party IP infringement
  - [ ] Licensed music/narration rights

### Build Submission

- [ ] **Archive Built**
  ```bash
  cd ios
  xcodebuild -workspace Runner.xcworkspace \
    -scheme Runner \
    -configuration Release \
    -archivePath build/Runner.xcarchive \
    archive
  ```

- [ ] **Version**: `1.0.0`
- [ ] **Build**: `1`
- [ ] **Code signing**: Completed with distribution certificate

### Builds & Testing

- [ ] **TestFlight Beta Testing** (recommended)
  - [ ] Internal testers added (team members)
  - [ ] External testers invited (limited)
  - [ ] Tested for 48 hours minimum
  - [ ] No critical bugs found

- [ ] **Crash Log Monitoring**
  - [ ] Checked TestFlight crash logs
  - [ ] All crashes fixed
  - [ ] Stability verified

### Review Information

- [ ] **Sign-In Required**
  - [ ] Demo account provided (if needed)
  - [ ] Test account credentials included
  - [ ] Access instructions clear

- [ ] **Notes for Reviewer**
  ```
  GatiVani is an audio companion for daily newspapers. Users can
  listen to newspaper content in multiple languages with customizable
  playback speed. No special access or setup required for testing.
  
  - Test user: test@example.com
  - Password: TestPass123!
  - Features: All available from main screen
  ```

- [ ] **App Clip Configuration** (if applicable)
  - [ ] Clip app ID configured
  - [ ] Advanced app clip settings

### Usage Rights

- [ ] **Newsstand Eligibility**
  - [ ] Confirmed if applicable
  - [ ] Content rights verified

- [ ] **Media Type**
  - [ ] Identified as news/magazine
  - [ ] Reporting enabled

### Advertising

- [ ] **IDFA** (if using ad tracking)
  - [ ] Privacy Policy updated
  - [ ] User consent mechanism
  - [ ] Ad partners declared

- [ ] **Ad Networks** (if applicable)
  - [ ] All networks listed
  - [ ] SDK versions current
  - [ ] Consent flow implemented

### Submission

- [ ] **Submit for Review**
  - [ ] All fields completed
  - [ ] All assets uploaded
  - [ ] No validation errors
  - [ ] Clicked "Submit for Review"

- [ ] **Expected Timeline**
  - [ ] Review typically 24-48 hours
  - [ ] Rejection reasons handled
  - [ ] Re-submit if needed

- [ ] **Approval Actions**
  - [ ] Set automatic release (or manual)
  - [ ] Prepare release notes
  - [ ] Schedule App Store optimization

---

## Post-Submission

### Monitoring

- [ ] **Crash Reports**
  - [ ] Reviewed daily for first week
  - [ ] Critical issues handled immediately
  - [ ] Hotfix released if needed

- [ ] **User Reviews**
  - [ ] Responded to feedback
  - [ ] Addressed issues raised
  - [ ] Thanked for positive reviews

- [ ] **Analytics**
  - [ ] Tracked install rate
  - [ ] Monitored user retention
  - [ ] Analyzed user engagement

### Updates

- [ ] **Version 1.0.1** (Hotfix, if needed)
  - [ ] Critical bugs fixed
  - [ ] Performance improvements
  - [ ] Resubmitted to stores

- [ ] **Version 1.1.0** (Feature Release)
  - [ ] New features implemented
  - [ ] User feedback incorporated
  - [ ] Submitted after 2-4 weeks

---

## Store-Specific Notes

### Google Play Store

- Typically approves within 2-3 hours
- May flag privacy/permissions issues
- Updates roll out instantly after approval
- Can use alpha/beta testing before production

### Apple App Store

- Typically reviews within 24-48 hours
- More stringent review process
- Enforces specific design guidelines
- Notarization required for security
- TestFlight beta testing highly recommended

---

## Troubleshooting

### Rejection Reasons & Solutions

**"The app uses sensitive permissions without justification"**
- Remove unused permissions from AndroidManifest.xml/Info.plist
- Add clear justification in privacy policy
- Explain why each permission is necessary

**"Privacy policy is missing or unclear"**
- Host detailed privacy policy on website
- Include in app settings
- Reference in submission notes

**"App crashes on launch"**
- Test on minimum supported OS version
- Check for initialization errors
- Review crash logs in Crashlytics

**"Incomplete app or placeholder content"**
- Ensure all features are functional
- Remove "Coming Soon" or "Beta" labels
- Provide complete content/data

---

## References

- [Google Play Console Help](https://support.google.com/googleplay/android-developer)
- [App Store Connect Help](https://help.apple.com/app-store-connect/)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Google Play Developer Program Policies](https://play.google.com/about/developer-content-policy/)

