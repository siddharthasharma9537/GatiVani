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
- **TTS**: Gemini 2.5 Flash (chunked, progressive playback — audio starts
  before the whole article finishes synthesizing)
- **Hosting**: Vercel (web), deployed via GitHub Actions

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
