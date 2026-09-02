# GatiVani — Orchestration & Cost Plan (Claude-based)

**Written:** 2026-09-02 · **Scope:** the whole repo as of `9e0b0dc` · **Status:** proposal

This document answers three questions: what GatiVani actually is today (as built, not
as the stale `packages/app/docs/ARCHITECTURE.md` describes it), where its money and
fragility live, and how to re-orchestrate the AI work on Claude models
(Sonnet 4.6 / Opus 4.5 as requested, with a cheaper same-role option noted) at a
lower and more predictable cost.

---

## 1. What you have built

GatiVani is a **Telugu newspaper → narrated audio** product. Flutter web app
(`packages/app`, ~16.8k lines Dart) on Supabase (Postgres + Storage + 16 Deno edge
functions, ~6.2k lines TS). Web deploy on Vercel, audio moving to Cloudflare R2.

There are **five AI-touching pipelines**. Everything else (podcasts, AIR, Mann Ki
Baat, markets, cricket) is fetch-and-parse with no model cost.

| # | Pipeline | Entry point | Models today | Who pays |
|---|---|---|---|---|
| 1 | **Edition ingest** (Paper tab) | `documents-process-edition` → `_shared/structure.ts` | Sarvam OCR; Gemini 2.5 Flash (page image + block manifest → structure JSON); Flash‑Lite (coherence, continuation match, printed-date) | User's BYOK Gemini key (`x-user-gemini-key`) |
| 2 | **Narration (TTS)** | `documents-synthesize` | Gemini 2.5 Flash TTS, 1450-char chunks (700 for chunk 0), WAV | **GatiVani shared key** (moved off BYOK in `5a8d17c`) |
| 3 | **Vāni Q&A** | `documents-ask` | `gemini-flash-latest`, grounded on article (6k chars) + edition index (8k chars) | Shared key |
| 4 | **Explainers** (Live tab) | `feeds-explains` | Flash‑Lite over scored + corroborated headlines | Shared key |
| 5 | **Summaries / single-doc** | `documents-summarize`, `documents-process` | Flash (3-fact summary; OCR correction; document classification) | Shared / BYOK |

### 1.1 The ingest pipeline in detail (the one worth redesigning)

```
PDF upload (direct to Storage `uploads/editions/`)
  → runStart: count pages (pdf-lib), create processing_jobs row, fire page 1
  → processPage(n)              [one edge-function invocation per page, self-fetched]
      ├─ pdf-lib: split page n → 1-page PDF
      ├─ Sarvam doc-digitization job (create/upload/start/poll/download)  ~20 s
      ├─ structure.ts
      │    [A] atomize   — parse Sarvam HTML → ordered Blocks (text is ground truth, never edited)
      │    [B] assign    — Gemini sees PAGE + numbered manifest, returns ONLY block ids/roles/seq
      │                    ladder: flash+doc → flash-lite+doc → flash text → flash-lite text, 2 tries each
      │    [C] assemble  — deterministic grouping + Telugu mid-sentence stitching
      │    [D] validate  — caption_leak / fused_articles / headline_missing / ends_mid_sentence → review flags
      │    Layer 2 coherencePass (flash-lite) — reorder within column
      │    Layer 3 visionPass (flash + image) — only for gapped articles
      ├─ insert articles (status ready|review), update job, delete page
      └─ fireContinuation(n+1)  via fetch + EdgeRuntime.waitUntil
  → finalizeContinuations: regex "(మిగతా 3వ పేజీలో)" + headline match + flash-lite semantic match
  → delete source PDF
```

This design is genuinely good in one important way: **the model never emits Telugu**
during structuring. It returns indices over OCR ground truth, so hallucinated news is
impossible by construction. Keep that invariant. Everything below preserves it.

### 1.2 Where the money goes today

Ranked by likely spend (no usage logging exists yet, so this is read from the code):

1. **TTS** — every unique article × every chunk, on the shared key. Cached in
   `article_chunks` + R2 keyed by `text_hash`, so cost is bounded by unique content,
   but a signed-in caller can still POST arbitrary `text` (120 req/hr/user cap only).
   Claude does not do TTS; this line item stays on a speech provider regardless.
2. **Page structuring** — per page: full page PDF (up to 15 MB, base64) + manifest to
   Flash, then coherence, then possibly vision again. Three model calls per page,
   with the page image sent at native resolution.
3. **Sarvam OCR** — fixed per page; not replaceable by Claude without breaking the
   ground-truth invariant.
4. Vāni, explainers, summaries — small.

### 1.3 Fragility and hygiene findings

- **Self-fetch page chain is not durable.** If one `processPage` invocation is
  killed (cold start, 150 s wall clock, Sarvam poll timeout), the chain stops and the
  job sits in `processing` forever. There is no retry, no dead-letter, no resume.
- **Serial pages.** 20 pages × (20 s OCR + 20 s structure) ≈ 13–15 min per edition.
  Nothing forces this to be serial except the chain design.
- **Quota ladder is a symptom.** `flash → flash-lite → text-only` exists because
  free-tier Gemini keys 429 constantly. On a paid Claude key with one model tier this
  ladder disappears.
- **Free-form JSON from the model** (`text.match(/\{[\s\S]*\}/)`) plus a
  "your previous answer was invalid" retry. Structured outputs remove both.
- **Two ingest engines coexist.** `documents-process` (1,150 lines) carries the legacy
  HTML parser, Gemini correction merge, classification, and the structured engine.
  `documents-process-edition` uses only the structured engine.
- **No per-call usage logging.** You cannot currently answer "what did this edition
  cost".
- **Tests are stale and CI hides it.** `test/services/firebase_service_test.dart`,
  `gemini_service_test.dart`, etc. reference services that no longer exist in
  `lib/services/`, and `ci.yml` runs analyze + test with `continue-on-error: true`.
- **`processing_jobs` is world-readable** (documented TODO), anon can start editions
  (2/hr/IP).
- `packages/app/docs/ARCHITECTURE.md` describes a Firebase/Sarvam-TTS app that no
  longer exists. The root `README.md` is accurate.

---

## 2. Target design

### 2.1 Principles

1. **Deterministic first, model second.** Atomize / assemble / validate / regex
   continuation / feed parsing stay model-free (they already are).
2. **One model gateway.** All Claude calls go through `_shared/llm.ts`: tier enum,
   cached system prefix, strict structured output, usage logging, refusal + 429
   handling, escalation helper. No function builds its own `fetch` to a model.
3. **Cheap tier by default, escalate on a signal.** Run every page on the cheap tier
   at low/medium effort; re-run only pages that *fail a deterministic check* on the
   expensive tier. Validation flags already exist — they become the escalation signal.
4. **Durable, parallel orchestration.** A queue and a per-step state row replace the
   self-fetch chain. Pages fan out; steps are idempotent; failures retry.
5. **Process each physical page once, ever.** Hash the OCR text of a page; a second
   user uploading the same Eenadu edition hits cache at the page level, not just the
   audio level.
6. **Two lanes.** *Interactive* (a user's own upload, wants progress) and *Shared
   daily editions* (prepared overnight, no one waiting) — the second lane runs on the
   Batch API at 50 % off.

### 2.2 Model routing

You asked for Sonnet 4.6 and Opus 4.5. Both are valid and the plan uses them as
named. One fact you should know before choosing: **Sonnet 5 is priced below
Sonnet 4.6** and has higher-resolution vision (2576 px), which matters for a
newspaper page. Opus 5 sits at the same Opus-tier price as 4.x. The routing below
works unchanged with either pair; swap the IDs in one place (`_shared/llm.ts`).

| Tier | Model | $/MTok in / out | Effort | Used for |
|---|---|---|---|---|
| T0 | none | — | — | atomize, assemble, validate, regex continuation, feed parse, all caches |
| T1 | `claude-haiku-4-5` | 1 / 5 | — | printed-date detection (cropped masthead image), 3-fact summary, category fallback |
| T2 | `claude-sonnet-4-6` *(or `claude-sonnet-5`, 2 / 10)* | 3 / 15 | `low`→`medium` | **page structure assignment** (image + manifest → strict JSON), coherence pass, vision gap pass, explainers, Vāni Q&A, OCR correction |
| T3 | `claude-opus-4-5` *(Opus-tier ≈ 5 / 25 — confirm on the pricing page; the bundled table lists 4.6+ only)* | ~5 / 25 | `high` | **escalation only**: pages where T2 fails `checkAssignment` or produces > N review flags; edition-wide continuation stitching (one call per edition); optional "general" Vāni mode |

Rules that keep this cheap:

- Adaptive thinking on (`thinking: {type: "adaptive"}`), effort set explicitly per
  route. Do not disable thinking on Sonnet 4.6 — lower effort instead.
- `strict: true` structured output with the `Assignment` schema. Deletes the regex
  JSON scrape and the "invalid, try again" loop.
- `cache_control` on the static prefix (`ASSIGN_PROMPT` + category rules ≈ 1.2k
  tokens; above Sonnet's minimum). Per-page content goes after the breakpoint.
- For Vāni: the **edition index block (≤ 8k chars) is the cache breakpoint**; the
  current article and question follow it. Follow-up questions in the same edition
  within 5 minutes read the index at 0.1×.
- **Downscale the page before sending it.** Vision is billed by pixel area
  (~1 token per 28×28 patch). Render the 1-page PDF to a ~1600 px-tall JPEG
  (`pdf-lib` can't rasterise; use `pdfium` via `npm:@hyzyla/pdfium` or
  pre-render once in the upload step). This is the single largest cut to the
  structuring line item — today a 15 MB page PDF goes in as base64.
- Log `response.usage` for every call into `model_calls` (see §3, Phase 0).

### 2.3 Orchestration

Replace `fireContinuation` with a table-driven state machine and a queue.

```
uploads/editions/<id>.pdf
   │
   ▼
[ingest_jobs]  status: queued→splitting→pages→stitching→ready|failed
   │
   ▼ split (T0)  ─ writes one row per page ─▶ [ingest_pages] (job_id, page, status, ocr_hash)
                                                     │
                       ┌─────────────────────────────┼──────────────────────────────┐
                       ▼                             ▼                              ▼
                  page 1 worker                 page 2 worker    …            page N worker   (fan-out, k-parallel)
                  ├ ocr        (Sarvam)          idempotent on (job_id,page); retries with backoff
                  ├ hash+dedupe  → cache hit? copy articles from prior edition, done
                  ├ structure  (T2, strict JSON, cached prefix)
                  ├ validate   (T0)  → flags
                  ├ escalate?  (T3 only if flags>N or assign failed)
                  └ insert articles
                       │
                       ▼ when all pages terminal
                  stitch (T0 regex → T3 one call)  →  ready  →  prewarm chunk 0 TTS for top stories
```

**Where to run the queue.** Two options; pick the first unless you are already
moving compute to Cloudflare:

- **A. Supabase-native (recommended, smallest change).** `pgmq` extension for the
  queue, `pg_cron` every 10–15 s calling a `pipeline-dispatch` edge function via
  `pg_net` that pops up to *k* messages and invokes `pipeline-page`. State lives
  in `ingest_jobs` / `ingest_pages`. Everything stays in one project; RLS unchanged.
- **B. Cloudflare Queues + Workers.** Native R2 bindings, better wall-clock limits,
  true consumer concurrency. Costs a port of `structure.ts` (portable — it is
  plain TS) and split auth between two platforms. Revisit if edge-function
  timeouts keep biting after A.

**Concurrency knob.** *k* is bounded by Sarvam's job concurrency and your Claude
rate limit, not by design. Start at k=4; a 20-page edition drops from ~14 min to
~4 min.

**Idempotency.** Every step keys on `(job_id, page, step)`; re-delivery re-reads
the row and skips finished work. Page-level `ocr_hash` (sha256 of Sarvam text)
is the dedupe key across editions and users.

### 2.4 Narration (TTS) — what changes and what does not

Claude cannot narrate. Keep the Gemini 2.5 Flash TTS path (or evaluate Sarvam
Bulbul against it on ₹/char — a measurement, not a guess). What the orchestration
gives you here is *when* and *how much* you synthesise:

- **Shared editions** synthesise chunk 0 of the top ~3 stories per section
  overnight (batchable, nobody waiting), everything else stays on-demand. Users get
  instant first sound on what most people tap.
- The **text-hash content check** (`3a77400`) stays; add a check that `text` for a
  real `articleId` must match `articles.full_content` *before* synthesis, not only
  the cache read — that closes the "burn the shared key on arbitrary text" hole.
- Sentence timings: `alignment.ts` (Sarvam STT forced alignment) is disabled for
  cost; the client estimates. A cheaper middle ground is per-chunk boundaries
  (already exact) plus proportional-by-character within a chunk. No model needed.

### 2.5 The rest of the model surface

| Function | Today | Target |
|---|---|---|
| `documents-ask` (Vāni) | flash-latest, 6k+8k chars stuffed per call | T2, index block cached, `max_tokens` ≈ 600, cite-by-number from the index so answers stay grounded |
| `feeds-explains` | flash-lite | T2 at `low`; cache the explainer per `(lang, day)` in `feed_cache` — you already have the table |
| `documents-summarize` | flash, 3 facts | T1 (Haiku), strict JSON `{facts: string[3]}` |
| `documents-process` (single doc) | flash classify + correct + legacy parser | Delete the legacy HTML parser path; classify on T1; correction on T2 `low` only when `documentType` needs it (slokas) |
| `detectPrintedDate` | Gemini on page bytes | T1 on a masthead crop (top 15 % of page 1), or regex on Sarvam text first |

---

## 3. Implementation plan

Phases are independently shippable and ordered by risk-per-dollar. Each names the
files it touches. Keep the Gemini path behind an env flag (`LLM_PROVIDER=gemini|claude`)
until the eval says the Claude path is at least as good.

### Phase 0 — See what you spend (≈ 2–3 days)

1. **Migration** `model_calls(id, fn, tier, model, job_id, page, input_tokens,
   cache_read, cache_write, output_tokens, latency_ms, ok, created_at)`; service-role
   only. Every model call in every function writes one row. This is the baseline
   every later phase is measured against.
2. **Downscale page images** before any model call (`documents-process-edition`
   → new `_shared/raster.ts`). Applies to Gemini today, Claude tomorrow. Measure
   tokens before/after on one page.
3. **CI honesty.** Remove `continue-on-error: true` from `ci.yml`; delete or rewrite
   the tests that reference removed services (`firebase_service_test`,
   `gemini_service_test`, `news_service_test`, `storage_service_test` and their
   fixtures/mocks). A red CI you can trust beats a green one you can't.
4. Delete `packages/app/docs/ARCHITECTURE.md` or replace it with a pointer to this
   file and the README.

### Phase 1 — Model gateway + structuring on Claude (≈ 1 week)

1. **`supabase/functions/_shared/llm.ts`** using `npm:@anthropic-ai/sdk` (Deno
   imports it fine). Exposes:
   - `Tier` = `haiku | sonnet | opus` → model IDs in one map.
   - `structured<T>(tier, {system, cachedPrefix, parts, schema, effort, maxTokens})`
     → typed `T`, via `output_config.format` + `strict`.
   - `escalate(fn)` — runs on `sonnet`, re-runs on `opus` when a caller-supplied
     `check()` fails.
   - Always: adaptive thinking, `cache_control` on `cachedPrefix`, refusal
     stop-reason handling, typed error chain (`RateLimitError` → backoff, 4xx → fail
     fast), `model_calls` insert with `response.usage`.
2. **`_shared/structure.ts`**: `assignWithGemini` → `assign()` on the gateway.
   Replace the 4-config ladder with: T2 `low` → `checkAssignment` → on failure T2
   `medium` with the error appended → on failure T3 `high`. `coherencePass` and
   `visionPass` → T2. Keep atomize/assemble/validate untouched.
3. **`documents-process-edition`**: `semanticContinuationMatch` → T3 (one call per
   edition, small); `detectPrintedDate` → T1 on masthead crop.
4. **Eval harness** (`supabase/functions/_shared/structure_eval.ts` + a `scripts/`
   runner): the structured engine was validated against
   `gativani-extraction/CHALLENGE` (15 correct articles vs 4 legacy). Turn that page
   plus ~10 more pages with hand-checked article counts/boundaries into a golden set.
   Score: article count, headline match, `review` flag rate, cost/page from
   `model_calls`. Run Gemini vs Sonnet `low` vs Sonnet `medium` vs Opus. Ship the
   cheapest config that matches or beats Gemini on the golden set.

### Phase 2 — Durable, parallel orchestration (≈ 1–2 weeks)

1. Migrations: `ingest_jobs`, `ingest_pages` (with `ocr_hash`, `step`, `attempts`,
   `last_error`), enable `pgmq`, `pg_cron`, `pg_net`; RLS: users read their own jobs
   (closes the world-readable `processing_jobs` TODO).
2. New functions: `pipeline-start` (split, enqueue N page messages),
   `pipeline-dispatch` (cron target, pops ≤ k, invokes workers), `pipeline-page`
   (one page, idempotent), `pipeline-finalize` (stitch, prewarm, cleanup).
   `documents-process-edition` becomes a thin shim to `pipeline-start`, then dies.
3. **Page dedupe**: on OCR complete, look up `ingest_pages.ocr_hash`; on hit, copy
   the prior page's `articles` rows under the new `newspaper_id` and skip every model
   call.
4. Client (`document_service.dart` `pollEdition`): poll `ingest_jobs` instead;
   progress = terminal pages / total.

### Phase 3 — Everything else onto the gateway (≈ 3–4 days)

`documents-ask` (cached index), `feeds-explains` (cached per day), `documents-summarize`
(Haiku), `documents-process` (drop legacy parser). Remove the Gemini text-generation
key from every function once the flag flips; the Gemini key remains only for TTS.

### Phase 4 — Shared editions + Batch lane (≈ 1 week, after usage data exists)

A nightly `pipeline-start` for each publisher edition you are allowed to carry;
pages run as a Message Batch (50 % off every token, cache reads included); TTS chunk‑0
prewarm for top stories. BYOK stops being necessary for the Paper tab entirely,
which is the usability win: **no key gate on first launch.**

---

## 4. What it should cost (estimate — replace with `model_calls` data after Phase 0)

Assumptions per page: downscaled image ≈ 1.5k tokens, manifest ≈ 3k, static prompt
1.2k (cached after first page), output ≈ 1.5k. Coherence pass ≈ 2k in / 0.5k out.

| Item | Sonnet 4.6 | Sonnet 5 | Notes |
|---|---|---|---|
| Structure, one page | ≈ $0.04 | ≈ $0.026 | image+manifest in, JSON out |
| Coherence, one page | ≈ $0.013 | ≈ $0.009 | |
| Opus escalation, ~20 % of pages | + $0.06/page escalated | same | ≈ $0.30 per 20-page edition |
| **20-page edition, interactive** | **≈ $1.35** | **≈ $1.00** | vs. serial Gemini ladder on a free key that 429s |
| Same edition via Batch lane | ≈ $0.68 | ≈ $0.50 | shared daily editions |
| Vāni question, first in session | ≈ $0.03 | ≈ $0.02 | 8k index written to cache |
| Vāni follow-up within 5 min | ≈ $0.01 | ≈ $0.007 | index read at 0.1× |
| Page dedupe hit | $0.00 | $0.00 | second upload of the same edition |

Sarvam OCR and Gemini TTS are separate lines and unchanged by this plan; the plan
reduces *how often* TTS runs (prewarm only top stories, dedupe editions), not its
unit price.

---

## 5. Decisions you need to make

1. **Sonnet 4.6 as requested, or Sonnet 5 at ~⅓ less with better vision?** The code is
   identical; this is a one-line swap. My recommendation: run the Phase 1 eval on
   both and let the golden set decide.
2. **Queue on Supabase (A) or Cloudflare (B)?** A unless you already plan to move
   functions to Workers.
3. **Shared daily editions** need publisher permission per title. The pipeline is
   ready for it either way; the legal question is yours.
4. **TTS provider** stays Gemini until you have measured Sarvam Bulbul on the same
   100 articles for cost and Telugu quality.
