# Architecture

**This file previously described a system that no longer exists.** It documented
a Firebase + Sarvam-TTS Flutter app with `lib/screens/`, `firebase_service.dart`,
`gemini_service.dart`, `news_service.dart` and a `SarvamAIService` — none of
which are in the codebase. Keeping it was worse than having nothing: it sent
readers looking for files that were deleted, and its "Version 1.0.0 · Production
Ready" header implied it had been checked.

The accurate descriptions live in two places:

| For | Read |
|---|---|
| What GatiVani is, the stack, repo layout, how to run and deploy it | [`README.md`](../../../README.md) at the repo root |
| How the pipelines actually work, what they cost, and what is planned | [`docs/ORCHESTRATION_PLAN.md`](../../../docs/ORCHESTRATION_PLAN.md) |

## The short version

Flutter web app (`packages/app`) on Supabase — Postgres, Storage, and Deno edge
functions — with audio on Cloudflare R2 and the web build deployed to Vercel.

Five pipelines call a paid model; everything else (podcasts, All India Radio,
Mann Ki Baat, markets, cricket) is fetch-and-parse and costs nothing:

- **Edition ingest** — `documents-process-edition` → `_shared/structure.ts`.
  Sarvam Vision OCRs each page; Gemini is shown the page plus a numbered
  manifest of OCR text blocks and returns *only block indices*, never Telugu.
  Hallucinated news is impossible by construction — preserve that invariant.
- **Narration** — `documents-synthesize`, Gemini TTS, chunked for progressive
  playback, cached by a hash of the source text.
- **Vāni Q&A** — `documents-ask`, grounded on one article plus an index of its
  edition.
- **Explainers** — `feeds-explains`, over independently corroborated headlines.
- **Summaries** — `documents-summarize` and the single-document path of
  `documents-process`.

Since Phase 0 of the orchestration plan, every one of those calls writes a row
to `model_calls`, so `select * from edition_cost` answers what an edition cost
in rupees. Read that before optimising anything.

## Layout

```
packages/app/lib/
  features/<name>/    screens, grouped by feature (paper, player, library, live, …)
  services/           PlaybackService, DocumentService, GeminiKeyStore, …
  widgets/            shared chrome: tab bar, playback puck, ticker
  design/             tokens + design-system components
  l10n/               Telugu/English strings

supabase/functions/
  _shared/            structure.ts (extraction engine), usage.ts (cost ledger),
                      mp3.ts, raster.ts, r2.ts
  documents-*/        ingest, synthesis, Q&A
  feeds-*/            live content

supabase/migrations/  Postgres schema
```
