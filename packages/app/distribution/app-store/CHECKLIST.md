# Apple App Store — Submission Checklist

Run this end-to-end before tapping "Submit for Review" in App Store Connect.

## 0. Pre-requisites
- [ ] Apple Developer Program membership active ($99/year, paid).
- [ ] App Store Connect role: Account Holder or App Manager.
- [ ] Bundle ID registered: `app.gativani` in Certificates, Identifiers & Profiles.
- [ ] Capabilities enabled: Push Notifications, Background Modes (audio, fetch), App Groups (if needed).
- [ ] Distribution certificate generated and stored in `1Password > GatiVani > ios-dist-cert`.
- [ ] App Store provisioning profile created.
- [ ] App-Specific Shared Secret created (Account > Apps > GatiVani > App-Specific Shared Secret).

## 1. App record
- [ ] App created in App Store Connect under team `GatiVani Labs`.
- [ ] Primary language: English (US).
- [ ] SKU: `gativani-ios`.
- [ ] Bundle ID matches `app.gativani`.

## 2. Build
- [ ] CI pipeline green on the tag commit.
- [ ] Build uploaded to App Store Connect via Transporter or `xcrun altool`/CI.
- [ ] Build processed (~10–30 min after upload).
- [ ] `Info.plist` keys present:
  - [ ] `NSMicrophoneUsageDescription` — only if feedback recorder enabled.
  - [ ] `NSPhotoLibraryUsageDescription` — for share-screenshot feature.
  - [ ] `UIBackgroundModes` — `audio`, `fetch`, `remote-notification`.
  - [ ] `ITSAppUsesNonExemptEncryption` = `NO` (we use HTTPS only, no custom crypto).
  - [ ] `LSApplicationCategoryType` = `public.app-category.news`.
- [ ] Minimum iOS deployment target: 13.0.
- [ ] Build size < 200 MB compressed.
- [ ] No private API usage (`xcrun` notarization should not flag this for App Store builds, but `nm` over the IPA shouldn't reveal `_objc_msgSend` to private classes).

## 3. App Information
- [ ] Subtitle (30 char): "Telugu newspapers, as podcasts".
- [ ] Category: Primary = News, Secondary = Magazines & Newspapers.
- [ ] Content Rights: "Does your app contain, show, or access third-party content?" = Yes (newspaper content under publisher agreements).
- [ ] Age Rating: 4+ (questionnaire all "None").

## 4. Pricing & Availability
- [ ] Price: Free (Tier 0).
- [ ] Availability: 7 launch markets (IN, US, GB, CA, AU, SG, AE).
- [ ] Pre-order: No.
- [ ] Educational discount: No.

## 5. App Privacy
- [ ] Data Types declared (matches Android Data Safety):
  - [ ] Email Address — linked, used for App Functionality (sign-in).
  - [ ] User ID — linked, used for App Functionality.
  - [ ] Product Interaction — not linked, used for Analytics.
  - [ ] Crash Data — not linked, used for App Functionality.
  - [ ] Performance Data — not linked, used for App Functionality.
- [ ] Tracking: No (we do not use IDFA).
- [ ] Privacy policy URL: `https://gativani.app/privacy`.

## 6. App Store Listing (per locale)
- [ ] **en-US**: from `listing-en-US.md`.
- [ ] **te-IN**: localized name, subtitle, description, screenshots.
- [ ] **hi-IN**: (optional beta) localized listing.
- [ ] Promotional text (170 char) — can be updated post-launch without re-review.
- [ ] Keywords (100 char) — comma-separated, no spaces after commas (counts against limit).
- [ ] Support URL: `https://gativani.app/support`.
- [ ] Marketing URL: `https://gativani.app`.

## 7. Screenshots (per locale, per device)
Required device sizes:
- [ ] **iPhone 6.7"** (1290 x 2796, iPhone 14/15 Pro Max) — 3–10 screenshots.
- [ ] **iPhone 6.5"** (1242 x 2688) — 3–10 screenshots OR Apple will use 6.7" auto-scaled.
- [ ] **iPad 12.9"** (2048 x 2732) — 3–10 screenshots, REQUIRED if iPad support advertised.

App Preview video (optional):
- [ ] 15–30 second video, .m4v/.mp4/.mov, 1080p+.

## 8. Game Center / In-App Purchases
- [ ] Game Center: No.
- [ ] IAPs: None at launch.

## 9. App Review Information
- [ ] Sign-in required: Yes.
- [ ] Demo account: `appstore-review@gativani.app` / rotated password.
- [ ] Contact info: review-contact@gativani.app, +91-XXXXXXXXXX.
- [ ] Notes for reviewer: paste content rights clarification (see `listing-en-US.md`).
- [ ] Attachments: Sample publisher agreement (PDF, redact financials).

## 10. Version Release
- [ ] **Phased Release for Automatic Updates**: Enabled (rolls out over 7 days).
- [ ] **Automatically release this version**: choose "Manually release this version" for first launch — flip to automatic after v1.0.0 stable.

## 11. TestFlight pre-launch
- [ ] Internal testers (team) install build, smoke test on iPhone + iPad.
- [ ] External testers (Beta App Review approves once, then up to 10K testers).
- [ ] Soak for 7 days before public submission.

## 12. Common rejection reasons
- Minimum functionality (4.2) — make sure the news catalog isn't empty on first launch.
- Sign in with Apple required if any third-party social login is offered (we use email-link only — safe).
- Background audio without an actual audio feature (we have one — safe).
- Push notifications used for marketing without consent prompt — only transactional notifications at launch.
- Privacy nutrition label mismatched with actual data collection — match exactly.
- Crashes on review device (iPhone XR running latest iOS is common review hardware).

## 13. Post-submit
- [ ] Review SLA: typically 24–48h.
- [ ] On approval and manual release: phased rollout starts automatically.
- [ ] Monitor Crashlytics + Apple Analytics for 24h.
- [ ] If crash-free sessions < 99.5%, halt phased release in App Store Connect.
