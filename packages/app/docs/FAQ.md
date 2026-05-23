# GatiVani — Frequently Asked Questions

**Version**: 1.0.0 | **Last Updated**: May 2026

---

## Table of Contents

1. [General](#general)
2. [Audio & Playback](#audio--playback)
3. [Languages & Content](#languages--content)
4. [Account & Data](#account--data)
5. [Performance & Storage](#performance--storage)
6. [Errors & Issues](#errors--issues)
7. [Developers & API](#developers--api)

---

## General

**What is GatiVani?**

GatiVani is a Telugu news audio app that converts newspaper articles from major Telugu publications into natural-sounding audio using AI. It is designed for commuters and anyone who prefers listening to reading.

**Which newspapers are available?**

Five Telugu newspapers are currently supported: Andhra Jyothi, Namasthe Telangana, Sakshi, Andhra Prabha, and Prajasakti. More sources will be added in future updates.

**Is GatiVani free?**

Yes. The core listening experience is free. Premium features (if introduced) will be clearly labelled.

**Do I need an account to use GatiVani?**

No. You can use GatiVani without signing in or creating an account.

**Which platforms does GatiVani support?**

GatiVani runs on Android (API 21 / Android 5.0 and above), iOS (iOS 13.0 and above), and modern web browsers (Chrome, Firefox, Safari, Edge).

**How often is the news updated?**

The app fetches fresh articles every 30 minutes. Pull down on the home screen to force a refresh at any time.

---

## Audio & Playback

**How is the audio generated?**

GatiVani uses a two-step AI pipeline:
1. Google Gemini summarizes the article text into a concise, podcast-friendly script.
2. Sarvam AI's text-to-speech engine converts the script into natural-sounding speech in your chosen language.

**Why does it take a few seconds before audio starts?**

The first time you tap an article, the app needs to summarize and synthesize the audio. This typically takes 2–5 seconds. After the first play, the audio is cached and replays instantly.

**Can I adjust the reading speed?**

Yes. Tap the speed button in the player (it shows "1.0×" by default) and choose from 0.5×, 0.75×, 1×, 1.25×, 1.5×, or 2×. Your preference is saved.

**Does playback continue when I lock my screen?**

Yes. Audio continues in the background. You can control playback from the lock screen notification on both Android and iOS.

**Can I skip forward or backward?**

Use the skip-forward (+10 s) and rewind (−10 s) buttons flanking the play button. Drag the progress bar to jump to any position.

**Can I listen to a full article without the AI summary?**

Currently, all playback uses the AI-generated summary for conciseness. Support for full-length narration is planned.

**Why is the audio quality lower than expected?**

Audio quality depends on your network speed during generation. On slow connections, the app may deliver a lower-bitrate file. Switching to Wi-Fi usually improves quality.

---

## Languages & Content

**Which languages can GatiVani read in?**

Telugu (default), English, and Hindi. Switch your preference in Settings > Language.

**Can GatiVani read English articles in Telugu?**

The AI summarization and TTS engine work in the language you select in Settings. If you select Telugu, all articles — including English-language ones — are summarized and narrated in Telugu.

**Is the Telugu pronunciation accurate?**

GatiVani uses Sarvam AI's Telugu TTS, which is purpose-built for Indian languages and handles standard Telugu pronunciation well. Unusual proper nouns or dialect-specific words may occasionally be mispronounced.

**Will more newspapers be added?**

Yes. Support for additional Telugu and other Indian-language newspapers is on the roadmap.

**Can I read the article text instead of listening?**

Tap any article card on the home screen to open the Article Detail view, which shows the original article headline and a link to the source website for the full text.

---

## Account & Data

**What data does GatiVani collect?**

GatiVani uses Firebase Analytics to collect anonymized usage events (screens viewed, articles played, errors). No personally identifiable information is collected without your consent. Push notification tokens are stored by Firebase to deliver notifications.

**How do I turn off analytics?**

Analytics collection can be disabled in the app's Settings screen. You can also revoke notification permissions from your device's system settings.

**Where are my bookmarks stored?**

Bookmarks are stored locally on your device using Hive. They are not synced to a server or shared. Uninstalling the app removes bookmarks.

**Does GatiVani sell my data?**

No. GatiVani does not sell user data to third parties.

---

## Performance & Storage

**How much storage does GatiVani use?**

The app itself is roughly 20–30 MB. Cached audio files take additional space — the cache holds up to 100 articles. To free space, go to Settings > Clear Cache.

**The app is slow. What can I do?**

- Ensure you have a stable internet connection.
- Clear the cache in Settings to remove stale files.
- Restart the app.
- Make sure you are running the latest version.

**Does GatiVani work offline?**

Articles you have previously listened to are cached locally and play offline. New articles require internet access.

**The feed is not refreshing. Why?**

New articles are fetched every 30 minutes. Pull down to force a refresh. If the refresh spinner spins indefinitely, check your internet connection. If the problem persists, close and reopen the app.

---

## Errors & Issues

**"Could not load articles" appears.**

This usually means a network problem. Check your internet connection and pull to refresh. If the issue persists, the news API server may be temporarily unavailable — try again in a few minutes.

**"Audio generation failed" appears.**

The AI summary or TTS service is temporarily unavailable. Wait a moment and tap Retry. If the error persists across multiple articles, check the [Troubleshooting Guide](TROUBLESHOOTING.md).

**The app crashes on launch.**

1. Force-close the app and reopen it.
2. Ensure your OS is up to date.
3. Uninstall and reinstall the app. Bookmarks are stored locally and will be lost on uninstall.
4. If the crash continues, report it via GitHub Issues with your device model and OS version.

**Notifications are not arriving.**

Ensure notification permissions are granted (device Settings > GatiVani > Notifications). If permission is granted but notifications are still missing, check that battery saver mode is not restricting background activity.

**I found a bug or want to request a feature.**

Open an issue on the GitHub repository with as much detail as possible: what you expected to happen, what actually happened, your device model, and your OS version.

---

## Developers & API

**Is there a public API?**

GatiVani's backend and service layer are internal. There is no public API at this time.

**How do I set up the development environment?**

See the [Developer Guide](DEVELOPER_GUIDE.md) for step-by-step setup instructions.

**Where is the source code?**

The source code is in the GitHub repository linked in the app's Settings screen.

**Which AI services does GatiVani use?**

- **Summarization**: Google Gemini (`gemini-pro` model)
- **Text-to-Speech**: Sarvam AI TTS
- **OCR** (for image-based articles): Sarvam AI OCR

**How does the caching work?**

GatiVani uses a two-tier cache: an in-memory LRU cache (up to 100 items) backed by Hive persistent storage on the device. News articles are cached for 30 minutes. Generated audio URLs are cached until the article is evicted. See the [Architecture Guide](ARCHITECTURE.md) for details.

**Can I contribute?**

Yes. Read the contributing section of the [Developer Guide](DEVELOPER_GUIDE.md) and open a pull request against the `develop` branch.
