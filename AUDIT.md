# GatiVani — Comprehensive Codebase & Infrastructure Audit

**Date:** 2026-06-11 · **Auditor:** Claude (full-stack review with gh / supabase / vercel CLIs + Cloudflare MCP)

## System topology (verified live)

```
Flutter app (packages/app)  ──►  Supabase Edge Functions (project jjoxowdvzmlchtfarpbs)
  iOS / Android / Web               health · documents-process · documents-synthesize
        │                           · documents-summarize
        │                                │
   Vercel (web)                     Supabase Postgres (4 tables, RLS on)
   gativani.vercel.app              Supabase Storage (uploads, audio)
   Firebase (auth/hosting cfg)      Sarvam OCR + Gemini 2.5 Flash (refine/TTS)
```

- **GitHub:** `siddharthasharma9537/GatiVani` (PUBLIC), main synced, new CI green.
- **Cloudflare:** 1 unrelated scratch worker (`autumn-art-cf98`); no GatiVani infra.
- **cPanel (`gativani.sohum.cloud`):** dead — serves a placeholder page, not the API.
- **Legacy Supabase projects:** `voxnews-production`, `newscast` — both INACTIVE.

## Endpoint verification (all live, post-refactor)

| Endpoint | Result |
|---|---|
| `GET /functions/v1/health` | ✅ 200 `gativani-edge` |
| `POST /functions/v1/documents-process` (real PDF) | ✅ 200 in 65 s — 4 articles, Sarvam OCR + Gemini refine, all rows persisted |
| `POST /functions/v1/documents-synthesize` | ✅ 200 — 177 KB audio, **provider gemini-2.5** (correct tier routing) |
| `POST /functions/v1/documents-summarize` | ✅ 200 — 3 Telugu bullets |
| `GET /rest/v1/newspapers,articles` (anon) | ✅ 200 — RLS public-read works |
| Vercel production (`gativani.vercel.app`) | ✅ 200 |
| GitHub Actions CI | ✅ green (first run) |
| Storage `storage_url` fetch | ❌ **400 — see Open Issue 1** |

## Fixed during this audit

1. **Production backend was unversioned** — the 4 deployed edge functions existed only
   in Supabase. Root cause: a blanket `/supabase/` line in `.gitignore`. Removed; all
   functions + `config.toml` + a baseline schema migration (tables, RLS, buckets) are
   now in git (`supabase/`).
2. **Two live Sarvam API keys hardcoded in a PUBLIC repo** —
   `packages/app/lib/services/sarvam_ai_service.dart` and `DEPLOYMENT_GUIDE.md`.
   Scrubbed (key now via `--dart-define`). ⚠️ **ACTION REQUIRED: rotate both keys
   at dashboard.sarvam.ai — they remain in public git history.**
3. **CI never ran** — workflows lived in `packages/app/.github/` which GitHub ignores.
   New lean root CI (Flutter analyze + Node/Python syntax checks); legacy workflows
   archived in `.github/workflows-archive/`.
4. **Dead Gemini key in edge-function secrets** — caused empty summaries and silent
   TTS fallback to Sarvam. Replaced with the verified key; summarize + Gemini TTS now
   work, restoring the intended chain (Gemini 2.5 Flash primary → Sarvam fallback).
5. **Config drift** — stale `gativaniFiles/vercel.json` draft archived (root
   `vercel.json` is live); app `.env.*` templates pointed to the dead cPanel URL,
   now point to the live functions URL; legacy `packages/core` renamed
   `gativani-core-legacy` with a README warning; `__pycache__` ignored; docs moved
   out of `lib/screens/`.

## Open issues (decisions needed — not auto-applied)

1. **Broken cover-art URLs (every `newspapers.storage_url`).** `documents-process`
   calls `getPublicUrl()` on the **private** `uploads` bucket → all stored URLs return
   HTTP 400. Options: (a) make `uploads` public — one SQL update, URLs already in DB
   start working; (b) switch the function to signed URLs — code change + redeploy,
   keeps files private. *(a) is simplest; uploads are newspaper pages, low sensitivity.*
2. **`extracted_texts` allows anonymous INSERT** (advisor-confirmed, spam vector) and
   an over-broad UPDATE policy. Edge functions use the service role (bypasses RLS),
   and the app does not write this table directly, so tightening is safe:
   `drop policy extracted_texts_insert_public on public.extracted_texts;`
   (and recreate restricted to `authenticated` if needed).
3. **Advisor WARN:** `public.update_timestamp` has a mutable `search_path` —
   one-line hardening: `alter function public.update_timestamp() set search_path = '';`
4. **Firebase client keys** in `google-services.json` / `GoogleService-Info.plist` are
   public-by-design but should be API-restricted in Google Cloud Console.
5. ~~Hardcoded page-specific hack in production parser~~ — **RESOLVED 2026-06-11**:
   the CHALLENGE structure engine is now ported into `documents-process`
   (`structure.ts`, deployed): atomize Sarvam HTML → Gemini index-only assignment
   (quota-resilient ladder: flash+doc → flash-lite+doc → text-only) → deterministic
   assembly + validation. Live result on the benchmark page: **20 articles vs 4**,
   with per-article `reviewFlags` persisted for the human-review screen. The legacy
   parser (incl. the hack) remains only as an automatic fallback path.
6. **`articles.js` router disabled** in legacy core (`server.js` comment: needs
   Node 22/ws) — moot once core is retired, listed for completeness.

## Quality observation

**Resolved same day:** the CHALLENGE engine now runs in production
(`documents-process` → `structure.ts`). Verified live: **20 articles vs 4** on the
benchmark page, 55 s end-to-end, all rows persisted with `extraction_engine:
"structured-v1"` and per-article review flags. Remaining tuning: title quality on
boxed/graphic items, and per-model Gemini quota headroom (the ladder degrades
gracefully through flash-lite and text-only modes).


---

## Follow-up sweep — 2026-06-11 (afternoon): all open items executed

| # | Item | Status |
|---|---|---|
| 1 | Broken cover-art URLs | ✅ `uploads` bucket made public (migration); all `storage_url`s serve HTTP 200 |
| 2 | `extracted_texts` anon INSERT + broad UPDATE | ✅ policies dropped/fixed (migration); advisor warnings cleared |
| 3 | `update_timestamp` search_path | ✅ pinned (migration) |
| 4 | Firebase key restriction | ⚠️ user action — restrict in Google Cloud Console |
| 5 | Tier spoofing / no rate limit | ✅ header honored only for authenticated JWTs (anon→free, verified); per-IP 12/h limit via `request_log` |
| 6 | Audio regenerated every play | ✅ `documents-synthesize` caches to public `audio` bucket + `articles.audio_url` (verified: 2nd call `provider=cache`, URL serves) |
| 7 | `publication_date` = upload date | ✅ printed date (Gemini) → filename (`…20260512`) → today |
| 8 | Stage-2 token waste | ✅ split into small classify call + lazy correction; structured path skips correction entirely (~halves Gemini tokens/page) |
| 9 | Dead Flutter code | ✅ removed unrouted `review_screen.dart`, dead `sarvam_ai_service.dart` (+ orphan tests, mock stripped) |
| 10 | Stale docs | ✅ warning banners on 6 legacy-era root docs |
| 11 | Deploy automation | ✅ `.github/workflows/deploy-functions.yml` (auto-deploy on `supabase/functions/**` push). **User action:** `gh secret set SUPABASE_ACCESS_TOKEN` (token from supabase.com/dashboard/account/tokens) — skips safely until set |
| 12 | Repo bloat / copyright | ✅ `packages/uploads/` (35 MB) + CHALLENGE page scans untracked & gitignored (note: still in git history — full scrub needs `git filter-repo` or a private repo) |
| 13 | Test suite health | ⚠️ documented: suite references nonexistent services (`firebase_service`, `gemini_service`, `news_service`) and cannot compile — needs an overhaul; `flutter test` added to CI as informational |

**Duplicates check:** 0 duplicate (title, date) newspaper groups after dedupe + upsert.
**Advisors:** previous 3 WARNs cleared; one intentional INFO (`request_log` service-role-only).
**Known transient:** free-tier Gemini daily quota exhausted by today's testing — summarize
returns 429 until reset; documents-process degrades through its flash-lite/text-only ladder.
Durable fix: paid-tier Gemini key.

**Still user-only actions:** rotate both leaked Sarvam keys; set SUPABASE_ACCESS_TOKEN
secret; restrict Firebase keys; (optional) repo private / history scrub.


---

## Spine build — 2026-06-12

| Piece | Status |
|---|---|
| **Categories** | ✅ live — Stage-B returns a per-article category enum (18 labels incl. District, Sci-Tech); preferred over regex fallback. Verified: Crime/Judiciary/Education labels accurate on benchmark page. |
| **Timings (lyrics sync)** | ✅ deployed — background Sarvam STT forced alignment after TTS (EdgeRuntime.waitUntil); timings JSON stored next to cached audio; `timingsUrl` in synthesize responses; app's SentenceTiming.fromJson format. **Caveat:** batch STT returned segment-level (not per-word) granularity on short clips — powers sentence-sync today; per-word needs sync-API 30s chunking (follow-up). |
| **Multi-page editions** | ✅ deployed — `documents-process-edition`: async job, one page per invocation self-chaining via service-role continuations, per-page failure isolation, aggregation under one newspaper, 2/h/IP limit, `processing_jobs` polling table. |

**Client contract (for the Flutter upload screen):**
1. `POST /functions/v1/documents-process-edition` (multipart `document`) → `{jobId, newspaperId, totalPages}`
2. Poll `GET /rest/v1/processing_jobs?id=eq.{jobId}&select=status,done_pages,total_pages,article_count,failed_pages`
3. On `completed`: `GET /rest/v1/articles?newspaper_id=eq.{newspaperId}&order=page_number` → list, play, synthesize per article (pass `articleId` for caching + timings).
