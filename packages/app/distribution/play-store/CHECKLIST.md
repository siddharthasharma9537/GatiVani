# Google Play Store — Submission Checklist

Run this end-to-end before clicking "Send for review" in Play Console.

## 0. Pre-requisites
- [ ] Play Console developer account active ($25 one-time, paid).
- [ ] D-U-N-S number registered (required for organization accounts).
- [ ] Bank account verified for payouts (only if you ever monetize).
- [ ] Signing key registered with Google Play App Signing.
  - [ ] Upload key generated and stored in `1Password > GatiVani > android-upload-key`.
  - [ ] Upload key SHA-1 added to Firebase project (Settings > Your apps > SHA fingerprints).

## 1. Bundle build
- [ ] CI pipeline green on the tag commit.
- [ ] `app-release.aab` size < 150 MB compressed (currently ~28 MB target).
- [ ] `--obfuscate --split-debug-info=build/symbols/android` applied.
- [ ] `--tree-shake-icons` applied.
- [ ] `versionCode` strictly greater than the last accepted upload.
- [ ] `versionName` follows semver: `MAJOR.MINOR.PATCH`.
- [ ] No `INTERNET-only` permissions warnings in `bundletool dump manifest`.
- [ ] Permissions audited:
      `MANAGE_EXTERNAL_STORAGE` removed, `RECORD_AUDIO` only if feedback recorder enabled.

## 2. Store listing (Play Console > Main store listing)
- [ ] App name (30 char): "GatiVani: News Audio".
- [ ] Short description (80 char).
- [ ] Full description (4000 char) from `listing-en-US.md`.
- [ ] App icon: 512x512 PNG, < 1 MB, no alpha, no rounded corners (Play rounds them).
- [ ] Feature graphic: 1024x500 PNG/JPG, no transparency.
- [ ] Phone screenshots: at least 2, max 8. 1080x1920 portrait.
- [ ] 7" tablet screenshots: at least 1 if tablet support advertised.
- [ ] 10" tablet screenshots: at least 1 if tablet support advertised.
- [ ] Promo video: optional YouTube URL.

## 3. Content rating (Play Console > Content rating)
- [ ] IARC questionnaire submitted. Expected rating: Everyone / 3+.
- [ ] No violence, sexual content, profanity from app itself (news content disclosed in description).

## 4. Target audience and content
- [ ] Target age group: 18+ (news app — keep adult to avoid COPPA/Designed for Families requirements).
- [ ] Ads declared: No (or Yes if Admob/AdSense enabled — currently No).
- [ ] News app declaration: Yes. Publisher attestation uploaded.

## 5. Data safety form
Mirrors the App Privacy section. Declare:
- [ ] Personal info > Email — collected, linked, optional, for account functionality.
- [ ] Personal info > User IDs — collected, linked, required, for account functionality.
- [ ] App activity > Product interaction — collected, not linked, optional, for analytics.
- [ ] App info & performance > Crash logs — collected, not linked, required, for app functionality.
- [ ] App info & performance > Diagnostics — collected, not linked, required, for app functionality.
- [ ] Data is encrypted in transit: Yes.
- [ ] Users can request data deletion: Yes (in-app + support@gativani.app).
- [ ] Adheres to Play Families policy: N/A (target 18+).

## 6. Government apps / News apps (India)
- [ ] News publisher attestation: upload signed agreement with each newspaper publisher.
- [ ] If targeting India distribution only: add India localization (te-IN, hi-IN).

## 7. Pricing & distribution
- [ ] Free.
- [ ] Countries: 7 launch markets (IN, US, UK, CA, AU, SG, AE).
- [ ] Contains ads: No.
- [ ] In-app purchases: No (at launch).

## 8. App access
- [ ] Reviewer credentials provided if any screens require login.
- [ ] Demo account: appstore-review@gativani.app / rotated password.

## 9. Release tracks
- [ ] **Internal testing**: deploy here first via CI (track: `internal`).
- [ ] **Closed testing**: opt-in beta group, ~50 users, 1-week soak.
- [ ] **Open testing**: ~500 users, 2-week soak.
- [ ] **Production**: staged rollout 5% > 20% > 50% > 100% over 7 days.

## 10. Pre-launch report
- [ ] Pre-launch crawl in Play Console completes with 0 critical issues.
- [ ] Address all "stability", "performance", "accessibility" warnings.

## 11. Post-submit
- [ ] Review SLA: typically 1-3 business days.
- [ ] On approval: bump rollout to 5% (Play Console > Production > Manage rollout).
- [ ] Monitor Crashlytics for 24h, then 20%, then 50%, then 100%.
- [ ] If crash-free users drops below 99.5%, halt rollout immediately.

## 12. Common rejection reasons (avoid)
- Using copyrighted news content without publisher agreement.
- Requesting `SYSTEM_ALERT_WINDOW` or `MANAGE_EXTERNAL_STORAGE` without justification.
- Hardcoded API keys discovered in obfuscated bundle (run `strings` over the AAB).
- Missing data safety form for any collected data category.
- Outdated target SDK (must target API 34+ as of 2025-08).
