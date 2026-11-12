# GatiVani (గతివాణి)

Telugu news you can listen to. GatiVani turns newspapers, live headlines,
and podcasts into narrated audio — live headlines and market updates read
aloud, full newspaper editions narrated section by section, All India Radio
and Mann Ki Baat streamed, and independent Telugu podcasts — so you can stay
informed on the commute instead of scrolling.

**Live:** https://gativani.sohum.cloud

## What it does

The app is four tabs:

- **Live** — scraped web headlines, a market/cricket ticker, and "Latest
  stories" narrated on tap. Original AI-generated commentary/explainers where
  the underlying source is facts-only (cricket scores, the day's top story) —
  never a reproduction of a publisher's actual sentences.
- **Paper** — upload a newspaper edition (PDF or camera scan); it's OCR'd,
  structured into articles by section, and narrated end to end.
- **Shows** — Telugu podcasts, Mann Ki Baat archive, All India Radio
  bulletins.
- **Library** — alerts for watched topics, resume-where-you-left-off,
  playlists, downloads, reading history.

Audio narration is BYOK: each user brings their own Gemini API key, kept
client-side, so the app's own infrastructure cost stays near zero per user.

## Stack

- **App**: Flutter (web-first via `flutter build web`; iOS/Android capable)
- **Backend**: Supabase — Postgres, Storage, and Deno Edge Functions
- **OCR**: Sarvam Vision, for digitizing newspaper page images
- **TTS**: Gemini 2.5 Flash in the cloud (chunked, progressive playback — audio starts
  before the whole article finishes synthesizing), or **on the device** with Indic
  Tiny TTS Telugu (below), or the device's own voice
- **Hosting**: Vercel (web), deployed via GitHub Actions

## On-device Telugu voice (Indic Tiny TTS)

Settings → Voice picks who reads a story: **Automatic** (the on-device voice when its pack is installed, else the phone's own
Telugu voice, else the cloud voice), **On-device**, **Phone's voice**, or **Online**. Female and male voices.

- **Model**: [sulabhkatiyar/indic-tiny-tts-telugu](https://huggingface.co/sulabhkatiyar/indic-tiny-tts-telugu), three ONNX graphs
  (text encoder, flow decoder, vocoder; 86 MB). Weights CC-BY-4.0 (trained on AI4Bharat Rasa, CC-BY-4.0), code and Vocos MIT. The
  credits text (required by CC-BY) is `voicePackCredits` in `lib/services/tts/voice_pack/pack_manifest.dart`, shown in
  Settings → Voice → Voice credits.
- **Voice pack**: downloaded after install from a pinned Hugging Face revision; every file's size and SHA-256 is in the manifest
  and checked before use. Android/iOS: files in the app-support folder, resumable (HTTP Range), storage-space check, versioned
  folder (an old version is removed only after the new one verified), delete button. Web: Cache Storage (no resume).
- **Pipeline** (`lib/services/tts/`): `indic_tiny/telugu_normalizer.dart` (port of the model's number-to-words plus rupee, percent,
  decimal, date, time, ordinal and unit reading — the extensions are AI proposals, not checked by a native reader) →
  `indic_tiny/frontend.dart` → `engine.dart` (encoder, durations, 4 Euler steps, vocoder, inverse STFT in Dart) →
  `narration_segmenter.dart` (story text → sentences) → `sentence_reader.dart` (look-ahead, pause/resume/stop/seek/speed, position
  kept, automatic fallback to the phone's voice if the model fails to start, fails, or is slower than real time) →
  `playback_service.dart` (the existing mini-player drives it). Sentences are cached by text + voice + pack version
  (memory + disk). ONNX Runtime: `flutter_onnxruntime` (MIT) on Android/iOS, ONNX Runtime Web directly in the browser (loaded
  from jsDelivr on first use, version pinned in `ort_loader_web.dart`; the plugin cannot make int64 tensors on the web).
- **Resources**: models load on the first sentence, are shared, and are closed 90 s after the last reader stops. CPU provider,
  2 threads. Expect roughly 100-200 MB of RAM while reading (weights 86 MB plus ONNX Runtime working memory); **not measured on a
  phone**.
- **Measured** (this Mac, ONNX Runtime Web/WASM in the in-app browser, real voice pack, `tool/tts_probe`): model load 0.7 s warm,
  real-time factor 0.17-0.20 (about 5x faster than real time), peak level and loudness in line with the model's published samples,
  no NaN, both voices. Not verified by ear, not measured on a phone, not compared with the model's Python output (see the owner
  steps in the PR).
- **Not done / needs a device**: Android background playback (a foreground service, e.g. `audio_service`) and the iOS
  `UIBackgroundModes: audio` entry (the iOS project's Info.plist is not in this repo); phone-call interruption is handled by
  just_audio's audio session for the on-device voice, not tested on a device; iOS needs a minimum iOS 16 and static linkage for
  ONNX Runtime (Podfile).

Tests: `cd packages/app && flutter test test/services/tts` (unit tests for everything pure, a fake-runner engine test, a fake
HTTP server for the downloader). `tool/tts_probe` is a browser harness for the real model (see its header).

## Repo layout

```
packages/app/            Flutter app
  lib/features/<name>/     screens, grouped by feature (paper, player, library, ...)
  lib/services/            PlaybackService, DocumentService, GeminiKeyStore, ...
  lib/widgets/              shared chrome: tab bar/dock, playback puck
  lib/design/               tokens + design-system components
  lib/l10n/                 Telugu/English strings

supabase/functions/       Deno edge functions (OCR pipeline, TTS synthesis,
                           the Vāni Q&A assistant, live content feeds)
supabase/migrations/      Postgres schema

docs/                     Auth setup, design system reference
```

## Development

```bash
cd packages/app
flutter pub get
flutter run -d chrome          # or: python3 ../../scripts/serve_web_nocache.py 8082
```

Edge functions run against a linked Supabase project — see
`supabase/config.toml`. Use the Supabase CLI (`supabase start`) for local
development against a local stack.

## Deployment

Push to `main` triggers two GitHub Actions workflows:

- `deploy-web.yml` — builds the Flutter web app and deploys to Vercel
- `deploy-functions.yml` — deploys every changed Supabase edge function

Both are CI-driven; there's no manual deploy step.
