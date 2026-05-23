# GatiVani Deployment Runbook

Operational playbook for shipping a release end-to-end and rolling back when things go sideways. Use this alongside `DEPLOYMENT_GUIDE.md` (which covers initial setup).

**Audience**: on-call engineer cutting a release.
**Frequency**: every tagged release + emergency hotfixes.

---

## TL;DR

```bash
# 1. Cut the release branch
git checkout main && git pull
git checkout -b release/v1.2.0

# 2. Bump version
sed -i '' 's/^version: .*/version: 1.2.0+42/' pubspec.yaml
git commit -am "chore(release): v1.2.0"

# 3. Open PR, get review, merge to main.
# 4. Tag — this triggers production CI.
git checkout main && git pull
git tag -a v1.2.0 -m "Release v1.2.0"
git push origin v1.2.0

# 5. Approve production-approval GitHub environment in Actions UI.
# 6. Monitor Crashlytics for 1 hour. Bump rollout in Play Console / App Store Connect.
```

---

## Release cadence

| Track          | Branch     | Trigger             | Audience       | Cadence        |
|----------------|------------|---------------------|----------------|----------------|
| Preview        | feature/*  | PR opened           | Reviewer       | Per-PR         |
| Staging        | develop    | Push                | Internal QA    | Continuous     |
| Release Candidate | release/* | Push              | Beta testers   | Weekly         |
| Production     | tag `v*`   | Tag pushed + approval | Public       | Bi-weekly      |
| Hotfix         | hotfix/*   | Tag `v*-hotfix.N`   | Public         | As needed      |

---

## Pre-release checklist (T-24h)

- [ ] All `main` PRs for this release merged and CI green.
- [ ] Manual QA pass complete on staging (`https://staging.gativani.app`).
- [ ] Crashlytics dashboard for staging shows no new crash signatures.
- [ ] Performance budget intact (see `docs/MONITORING_SETUP.md`):
  - [ ] First contentful paint < 1.5s on web.
  - [ ] App startup p95 < 2.5s on mid-tier Android.
  - [ ] Audio start latency p95 < 1.2s.
- [ ] Localization sanity check: te-IN strings render in Mallanna font, no missing glyphs.
- [ ] Release notes drafted in `distribution/whatsnew/whatsnew-en-US` and `whatsnew-te-IN`.
- [ ] PM/Marketing sign-off in #release Slack channel.

---

## Cutting the release

### 1. Version bump

Format: `MAJOR.MINOR.PATCH+BUILD`

- MAJOR — breaking schema migration or platform behavior change.
- MINOR — user-visible feature.
- PATCH — bug fix only.
- BUILD — monotonically increasing integer. CI rejects duplicate `versionCode` (Android) or `CFBundleVersion` (iOS).

```bash
# In release branch
./scripts/bump-version.sh 1.2.0
git commit -am "chore(release): v1.2.0"
git push -u origin release/v1.2.0
```

### 2. PR review

- Diff should be: pubspec.yaml version, `whatsnew-*` files, and changelog entry only.
- One approver required from #release-approvers.

### 3. Merge to main, then tag

```bash
git checkout main && git pull
git tag -a v1.2.0 -m "v1.2.0"
git push origin v1.2.0
```

This kicks off the full production pipeline: `analyze → test → security-scan → build-* → production-approval → deploy-* → smoke-test → upload-crashlytics-symbols → create-release`.

### 4. Approve production gate

- Open Actions UI on the workflow run.
- Click the `production-approval` job. A reviewer (from the `production-approval` environment) must click "Approve and deploy".
- Approval requires two-factor and is logged.

### 5. Watch the deploy

Expected timing:
- Build (parallel web/android/ios): 25–60 min.
- Approval gate: variable.
- Deploy web (Firebase Hosting): 1–2 min.
- Deploy Android (Play Console internal track): 2–5 min.
- Deploy iOS (TestFlight): 10–30 min (Apple processing).
- Smoke tests + symbol upload: 5 min.

### 6. Staged rollout

**Google Play**:
- Play Console > Production > Manage rollout.
- Start at 5%. Wait 4h. If crash-free users ≥ 99.5%, bump to 20%.
- 20% → 50% → 100% over the next 72h, with 4h soak between bumps.

**App Store**:
- Phased Release for Automatic Updates is enabled (1% > 2% > 5% > 10% > 20% > 50% > 100% over 7 days).
- App Store Connect > App > Version > Phased Release controls pause/resume.

**Web**:
- Firebase Hosting deploys fully and immediately to all users. There is no staged rollout for web. To gate, ship feature flags via Firebase Remote Config — see `docs/MONITORING_SETUP.md`.

---

## Monitoring during rollout

For each release, watch these for **24 hours**:

| Signal                 | Threshold                | Source            |
|------------------------|--------------------------|-------------------|
| Crash-free users       | ≥ 99.5%                  | Firebase Crashlytics |
| ANR rate (Android)     | < 0.47% (Play threshold) | Play Console Vitals |
| Slow start rate        | < 1%                     | Firebase Performance |
| API p95 latency        | < 500ms                  | Cloud Run / Cloud Logging |
| 5xx rate from backend  | < 0.1%                   | Cloud Run         |
| Audio session failures | < 0.5%                   | Custom analytics event `audio.session.failed` |

If any metric breaches threshold for more than 15 consecutive minutes, halt rollout (see below).

---

## Rollback

### Web rollback (fastest, < 2 min)

```bash
firebase hosting:clone gativani-prod:live gativani-prod:live --version <previous-version-id>
# Or via Firebase Console: Hosting > Release history > "..." > Rollback.
```

### Android rollback

Play Console does not support binary rollback. Options:

1. **Halt the staged rollout** — Play Console > Production > Manage rollout > Halt rollout. New users on the old version stay there; users on the new version stay on it.
2. **Ship a fixed AAB** with a higher `versionCode`:
   ```bash
   git checkout v1.2.0
   git checkout -b hotfix/v1.2.1
   # revert offending commits
   git tag -a v1.2.1 -m "Hotfix"
   git push origin v1.2.1
   ```
3. **Server-side disable** — flip the Remote Config flag `feature.<broken>.enabled = false`.

### iOS rollback

Same model as Android — no binary rollback. Options:

1. **Pause phased release** — App Store Connect > App > Version > Phased Release > Pause.
2. **Submit expedited hotfix** — App Store Connect > Resolution Center > Request expedited review (use sparingly).
3. **Remove from sale** — App Store Connect > Pricing and Availability > Remove from sale. Existing installs keep working.

### Database / schema rollback

Firestore is forward-compatible by design (schemaless), but if a release wrote bad documents:

1. Disable the writing code path via Remote Config.
2. Run the cleanup function `functions/src/cleanup/v<version>-bad-writes.ts` (one per release, opt-in only).
3. If catastrophic: restore from automated daily Firestore export in `gs://gativani-prod-backups/firestore/`.

---

## Hotfix procedure

For a P0 production issue:

1. Page on-call: `pagerduty.com/services/gativani-prod`.
2. File an incident in #incidents Slack.
3. Cut from the **latest tagged release**, not main:
   ```bash
   git checkout v1.2.0
   git checkout -b hotfix/v1.2.1
   ```
4. Apply minimal fix. Keep the diff < 200 LOC. No refactoring.
5. Run the full CI pipeline.
6. Skip the staged rollout — push 1% > 100% over 1 hour.
7. Post-incident: schedule a 30-min retro within 5 business days.

---

## Environment management

See `docs/ENVIRONMENT_STRATEGY.md` for the full matrix. Short version:

| Env       | Bundle ID            | Firebase project    | URL                          | Source            |
|-----------|----------------------|---------------------|------------------------------|-------------------|
| Dev       | app.gativani.dev     | gativani-dev        | dev.gativani.app             | Local + `develop` |
| Staging   | app.gativani.staging | gativani-staging    | staging.gativani.app         | `develop` push    |
| Production| app.gativani         | gativani-prod       | gativani.app                 | `v*` tag          |

---

## Secrets and credentials

All secrets live in GitHub Actions Secrets (org level for shared, repo level for app-specific). See `docs/ENVIRONMENT_STRATEGY.md` for the inventory. Rotation policy:

- App-signing keys: never rotated (loss = locked out of app updates forever).
- API keys (Sarvam, Gemini, Claude): rotate every 90 days or on suspected compromise.
- Firebase service accounts: rotate every 180 days.
- Play Console / App Store API keys: rotate yearly.

---

## Common failures and recovery

| Symptom                              | Likely cause                              | Fix                                                                 |
|--------------------------------------|-------------------------------------------|---------------------------------------------------------------------|
| iOS build fails with "no provisioning profile" | Profile expired or bundle ID drift | Regenerate in Apple Developer portal, re-encode to `IOS_DIST_CERT_P12_BASE64` secret |
| Android build fails with `keystore not found` | `ANDROID_KEYSTORE_BASE64` secret unset/corrupt | Re-encode keystore: `base64 -i upload-keystore.jks \| pbcopy` |
| Play upload fails: "version code already used" | Forgot to bump `+BUILD`                   | Bump and re-tag                                                     |
| TestFlight upload succeeds but never appears | Apple still processing                    | Wait 30 min. If 2h, check email for ITC binary rejection           |
| Web deploy succeeds but 404           | Hosting target mismatch                   | Verify `.firebaserc` targets align with `firebase.json` hosting keys |
| Crashlytics shows obfuscated stacks   | Symbols not uploaded                      | Run `firebase crashlytics:symbols:upload` manually or re-run `upload-crashlytics-symbols` job |
