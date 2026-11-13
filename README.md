# GatiVani (గతివాణి)

Telugu news you can listen to. GatiVani turns newspapers, live headlines,
and podcasts into narrated audio — live headlines and market updates read
aloud, full newspaper editions narrated section by section, All India Radio
and Mann Ki Baat streamed, and independent Telugu podcasts — so you can stay
informed on the commute instead of scrolling.

**Live:** https://gativani.sohum.cc (`gativani.sohum.cloud` redirects there)

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

Audio narration today is made on the server (`documents-synthesize`): Gemini
TTS with the user's own key (BYOK, kept client-side), or Google Cloud TTS on a
free lane. The code notes that `gemini-2.5-flash-preview-tts` was due to retire
on 16 Oct 2026; whether the Gemini path still works has not been checked here.
Audio is stored in R2 when configured, otherwise in the public `audio` bucket.

## Stack

- **App**: Flutter (web-first via `flutter build web`; iOS/Android capable)
- **Backend**: Supabase (the shared `sohum` project) — Postgres, Storage, and Deno Edge Functions
- **OCR**: Sarvam Vision, for digitizing newspaper page images
- **TTS**: Gemini 2.5 Flash TTS (BYOK) or Google Cloud TTS, server-side (see above), or on the device with Indic Tiny TTS Telugu (section below), or the device's own voice
- **Hosting**: the web app is served from the Cloudflare Worker `gativani`
  (since 2026-10-17). `deploy-web.yml` in this repo still deploys to Vercel; how
  the Worker is updated is not documented in this repo.

## Eenadu daily PDFs (personal use, the owner's Mac)

Eenadu's e-paper is saved each morning by scripts that run on the owner's Mac,
with the owner's own e-paper login, outside this repo (`~/eenadu-auto`, started
at about 05:00, Mac woken at 04:58). They write to the Drive folder
`My Drive/sohum-gativani/`:

- `Eenadu_<EDITION>_<dd-mm-yyyy>.pdf`: the page PDFs merged (Telangana, Andhra
  Pradesh, Greater Hyderabad), with a text layer in legacy fonts;
- `Eenadu_<EDITION>_<date>.links.json`: the front page's "continued on page N"
  hotspots (`jumps`, in PDF points) and, from the next daily run, the page labels
  Eenadu prints (`pages: [{page, title}]`, e.g. EDITORIAL, BUSINESS; plain pages
  are just "Page");
- `manifest-<date>.json`: written last; page count per edition against the site's.

**Rule: personal use only. Ask Ushodaya Enterprises before any hosted use.** No
Eenadu content, login or key is in this repo, and none is uploaded anywhere.

## Legacy-font converter (glyph reading, not a model)

The page PDFs carry real text, but Telugu is in Eenadu's legacy fonts, so the
extracted characters are glyph codes, not Unicode. The converter reads each code
from the glyph outlines (a table of what every code is) and composes the pieces
with a small rules file (cluster order, vowel signs drawn before their letter,
curl glyphs that make మ/య/ఘ, the dot that aspirates a consonant, ra-vattu order).
Nothing is learned from data; OCR output was used only to check readings. It
decodes per span and joins a line, so marks in a neighbouring font attach to
their letter; English, digits and punctuation pass through exactly. The code and
tables live outside the repo, with the other Eenadu files, in
`~/Workspace/sohum-veda-work/eenadu-glyph/`.

Measured on 12-11-2026, whole editions, against Tesseract's reading of the same
lines (lines where both have the same word count; exact word match, and ignoring
punctuation at word edges): Eenadu-Light body text about 91% (95%) in Telangana,
Andhra Pradesh and Greater Hyderabad; Narmada 88.5–90.3%; GodawariHeading
86–87%; GodawariSubHeading 90–93%. Sarvam Vision was used as a second yardstick
on page 1 and 5 of each edition (Andhra Pradesh page 1 is mostly graphics and is
not usable): 98.2% of the converter's words occur in Sarvam's text, against
91.0% for Tesseract's (not a like-for-like count). The editorial pages decode as
well as the rest (about 91%). Limits: one day's papers; Tesseract is noisy on
bold and large type, so the figures understate the converter in places; no
native Telugu reader has checked the output; all Telugu readings are an AI
proposal.

Not covered: the font `EenaduU` (advertisement text, one page of one edition);
headlines printed as a picture have no text (they need OCR); words broken at
line ends keep a gap; story grouping and joining continuations are a first cut.

## Local review and "Today's paper" screens (not in normal or deployed builds)

Two screens read the owner's PDFs and converter output on the Mac. They exist
only when the web app is built with `--dart-define=EENADU_REVIEW=true`; a normal
or deployed build has neither route.

- `/review`: the page, each text block with its picture, the converted text and
  the OCR reading, OK / Fix with a note, a filter ("only blocks that need a
  look"), "next unreviewed".
- `/paper/today` (also a button on the Paper tab header): the paper as news,
  grouped by Eenadu's page labels, and a reading screen per story.

```bash
cd packages/app && flutter build web --release --dart-define=EENADU_REVIEW=true
cd ../.. && ~/eenadu-env/bin/python scripts/eenadu_review_server.py               # on the LAN / hotspot
cd ../.. && ~/eenadu-env/bin/python scripts/eenadu_review_server.py --local-only  # 127.0.0.1 only
```

The server prints a link with a per-run key (a cookie is set from it) and uses
plain HTTP, so use it on a network you trust. Review results are saved in
`~/eenadu-review/results_<edition>_<date>.json`; page pictures and crops are
cached there too. Nothing goes to Supabase or any other host.

## TTS direction

Goal: a free app that narrates on the device. The Indic Tiny TTS port and browser
playback are built on this branch; see the implementation and local verification
below. Native background playback, phone performance, and native-reader approval
remain open. Earlier phase-1 feasibility notes are superseded by that status.

## Status (2026-11-12)

| Item | State |
| --- | --- |
| Eenadu daily PDFs to Drive | built, runs on the owner's Mac |
| Legacy-font converter | built, local only (outside this repo) |
| Review and Today's paper screens | built, local only, behind `EENADU_REVIEW` |
| Eenadu content in the live app | not done: nothing Eenadu-related is live or public |
| Owner-only live load (schema, importer) | planned, not started |
| Upload fix (#25) on the live site | merged to `main`, not deployed: the live site rejected uploads when last checked (2026-11-07) until a web deploy |
| On-device TTS | built on PR #28 (`feat/on-device-tts`), not merged; played from Today's paper in the local review build (`feat/eenadu-listen`) |

## On-device Telugu voice (Indic Tiny TTS)

Settings → Voice picks who reads a story: **Automatic** (the on-device voice when its pack is installed, else the phone's own
Telugu voice, else the cloud voice), **On-device**, **Phone's voice**, or **Online**. Female and male voices.

- **Model**: [sulabhkatiyar/indic-tiny-tts-telugu](https://huggingface.co/sulabhkatiyar/indic-tiny-tts-telugu), three ONNX graphs
  (text encoder, flow decoder, vocoder; 87 MB). Weights CC-BY-4.0 (trained on AI4Bharat Rasa, CC-BY-4.0), code and Vocos MIT. The
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
  no NaN, both voices. On a four-sentence news paragraph (with "140" and "15" in it) the total audio duration equals the model's
  own Python output to the sample (24.79 s female, 23.52 s male), which checks the text path, the encoder, the durations and the
  inverse STFT length against the reference. Not verified by ear, not measured on a phone, and the normaliser is not yet
  compared with the Python one over the whole number range (owner step in the PR).
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

Pushing to `main` can trigger two GitHub Actions workflows (their secrets are
set):

- `deploy-web.yml` — when `packages/app/**` changes, builds the Flutter web app and
  deploys it to Vercel. The live site is on a Cloudflare Worker, so this does not
  update it.
- `deploy-functions.yml` — when `supabase/functions/**` or `supabase/config.toml`
  changes, deploys **every** edge function to the `sohum` project (not only the
  changed ones).

## Listen review follow-up (2026-11-13, local only)

Branch `codex/eenadu-listen-review` starts at `704e1a5` on `feat/eenadu-listen`,
including the fresh-player-per-clip fix `7ea5c8e`. No merge, deploy or live database
write. Tests contain synthetic material only; Telugu readings are AI proposals.

- List and story use the same server headline. A reused story route now reloads
  when its edition/date/id changes and ignores late responses for the old story.
  Bullet glyphs are removed from headline text. The supplied Kamalam headline
  and Hydra opening/continuation were already correct in the starting commit.
- The lexicon now reads each available edition/date once and removes surrounding
  punctuation for lookup. A line boundary joins only if its combined word is
  attested, at least one piece is not independently attested, and the pair is not
  attested. `Store.rejoin_log['unclear']` lists unresolved boundaries; no spelling
  is invented. The local 12/13-Nov corpus supports the first reported word join;
  the other two reported examples remain ambiguous/unattested and need review.
- A smaller display heading at a block end after two main subheadings introduces
  a separate side note. The Kamalam award note is one "Also on this page" item,
  excluded from narration; its two main subheadings remain once each. This is a
  typography heuristic, not semantic understanding; other layouts need review.
- Inline page pointers are removed from display as well as narration. Repeated
  identical subheadings are suppressed. Existing continuation matching remains
  conservative; a failed match is shown as an English status note.
- Ellipses stay inside one narration phrase and become a comma pause in the
  synthesis frontend. Chunk limits still apply to long phrases. The printed
  headline remains unchanged. No paid OCR/TTS service was called. Graphic
  headlines retain their picture and "needs OCR" notice.
- "Play all in this section" is deferred: queue ownership, cancellation and
  navigation need more than a small button change.

Measured on the owner's 12-Nov PDFs (before -> after):

| Edition | Stories | Joined | Unmatched | Graphic headlines | Inline display pointers |
| --- | ---: | ---: | ---: | ---: | ---: |
| Telangana | 229 -> 229 | 11 -> 11 | 4 -> 4 | 8 -> 8 | 0 -> 0 |
| Andhra Pradesh | 256 -> 256 | 6 -> 6 | 3 -> 3 | 3 -> 3 | 6 -> 0 |
| Greater Hyderabad | 252 -> 252 | 10 -> 10 | 5 -> 5 | 3 -> 3 | 0 -> 0 |

All 12 unmatched jumps lack a detected continuation block on their target page
and have no sufficiently strong headline fallback. Targets: Telangana 3/8/22/18;
AP 18/10/12; Greater Hyderabad 3/11/12/25/18. These are extraction limits, not a
claim that the PDF lacks the continuation. AP's picture-only front page still
has no extracted story records. Across the 13 extracted front-page stories in
each of Telangana and Greater Hyderabad, headline bullets fell 4 -> 0 and
trailing jump tags stayed 0 -> 0. Four in each still have no extracted byline;
that is a review flag, not proof of a missing opening. Hydra has its dateline,
opening paragraph and linked page-3 body in both baseline and final output.

Verification commands (from the checkout root):

```bash
~/eenadu-env/bin/python -m unittest discover -s scripts/tests -v
(cd packages/app && flutter test)
(cd packages/app && flutter build web --release --dart-define=EENADU_REVIEW=true)
~/eenadu-env/bin/python scripts/eenadu_review_server.py --local-only --port 8097
```

Use the access link printed by the server; keep its key private. Port 8097 avoids
interrupting the desk's server on 8096. The review build passed, with existing
third-party Wasm dry-run warnings; this verifies JavaScript web output, not Wasm.

### Native playback follow-up: notes only, not implemented or phone-tested

Android: add `audio_service` in a future native change and let its audio handler
own `SentenceReader` beyond the lifetime of the screen. Map play/pause/stop and
sentence navigation to media controls; publish queue and playback state. Use
`AudioServiceActivity` (or its base class for an existing custom activity),
`AudioService` with `foregroundServiceType="mediaPlayback"`, and
`MediaButtonReceiver`. Declare `WAKE_LOCK`, `FOREGROUND_SERVICE`, and
`FOREGROUND_SERVICE_MEDIA_PLAYBACK`. Start from an explicit foreground play
request; test paused-service restart on Android 12+. Follow the package's
[Android setup](https://pub.dev/packages/audio_service#android-setup).

The iOS Runner project/Info.plist/Podfile are absent here. In a clean native
feature checkout, restore them or run `flutter create --platforms=ios .` and
review the generated diff. Set the Runner minimum deployment to 16.0 in Xcode.
For CocoaPods, edit `ios/Podfile`:

```ruby
platform :ios, '16.0'
# Inside the existing Runner target, replace its use_frameworks! declaration:
use_frameworks! :linkage => :static
```

Then run `(cd ios && pod install)` from `packages/app`, and open
`ios/Runner.xcworkspace`. These settings match the installed
[flutter_onnxruntime 1.9.0 instructions](https://pub.dev/packages/flutter_onnxruntime/versions/1.9.0).
Add to Runner's Info.plist (or its existing array):

```xml
<key>UIBackgroundModes</key>
<array><string>audio</string></array>
```

Configure a speech/playback audio session after audio plugins initialize. The
[background-audio setup](https://pub.dev/packages/audio_service#ios-setup) does
not grant indefinite background computation: keep synthesis ahead of the
current clip; validate handoff between clips while locked. Route disposal
currently stops the reader and must be changed with handler ownership.

Current resource bounds, not measured device RAM: 220 UTF-16 units per narration
segment, 250 characters per frontend chunk (numbers may expand), model-manifest
token limit, two look-ahead sentences, serial synthesis, 24 MiB memory cache plus
an 8 MiB secondary memory cache on web or 120 MiB disk cache on native. Shared
models release after 90 seconds idle. These caps do not bound ONNX activations,
PCM/WAV copies or base64 data URIs; there is no hard frame/audio-duration cap.
Before shipping, measure peak RSS on low-memory phones, add a measured frame cap
before allocating model tensors, and verify the cache and model release after
stop. The earlier 100–200 MB estimate is not a measured ceiling.

Real-phone checks still required: full story with screen locked and app
backgrounded; notification/lock-screen controls; calls, headphone removal and
Bluetooth changes; pause/resume during synthesis; rapid story/voice changes;
long numbers and maximum chunks; 30-minute heat/battery/RAM; low storage, pack
resume and corruption; process death and saved position; offline playback after
pack installation. No native background feature is claimed working.

Browser verification on this Mac: the list tile and story headline agree; the
story retains its graphic and needs-OCR notice. Kamalam played 30/30 sentences
at normal speed in about 4m28s; measured synthesis RTF was about 0.16–0.20.
A second full pass logged 30 distinct data-URI fingerprints and 30 clip-ended
events; the player reached 100% and "Listen again". The fingerprint probe was
injected into the ignored local build only and is not part of the source/PR.
This checks progression and distinct clips, not native-reader voice quality.

The downloaded model's Python was not run. If the owner separately approves a
reference rerun, from the checkout root, with networking disabled, run:

```bash
GV_REFERENCE_MODEL="$HOME/Workspace/sohum-veda-work/eenadu-glyph/tts_samples/model"
GV_REFERENCE_PYTHON="$HOME/Workspace/sohum-veda-work/eenadu-glyph/tts_samples/venv/bin/python"
"$GV_REFERENCE_PYTHON" -I scripts/tts_reference/ref_numbers.py /tmp/gativani-normalizer-reference.json "$GV_REFERENCE_MODEL"
"$GV_REFERENCE_PYTHON" -I scripts/tts_reference/ref_durations.py /tmp/gativani-duration-reference.json "$GV_REFERENCE_MODEL"
```

These commands are instructions only; current checks use Dart tests and the
browser's ONNX runtime, not execution of downloaded model Python.
