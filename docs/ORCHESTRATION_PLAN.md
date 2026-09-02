# GatiVani — ₹50-per-edition Orchestration Plan

**Written:** 2026-09-02 · **Scope:** the whole repo as of `9e0b0dc` · **Status:** proposal (v2)

Goal, as stated: **process and narrate a whole edition for under ₹50**, and narrate
the **Live feed on free-tier TTS**. Runtime stack stays **Sarvam Vision (OCR) +
Gemini (vision/structure) + Gemini TTS** — this plan does not move inference to
Claude. Prices below were looked up on 2026-09-02; ₹ figures use **₹95 / $1**.
Sources at the end. Anything marked *verify* could not be read from the vendor's
own page (blocked from this session) and was taken from secondary sources.

---

## 0. The one-paragraph answer

A 20-page Telugu daily costs about **₹10 to OCR** and **₹5–13 to structure**. That
leaves ~₹27–35 for narration. A full edition is ~120–180k Telugu characters, which
is **2.8–4.3 hours of audio**; on Gemini TTS that is **₹100–360**, so "narrate the
whole edition on Gemini for under ₹50" is not achievable at any orchestration. What
*is* achievable, and what this plan builds:

1. **Process every edition once, share it** (page-hash dedupe) so the ₹20 of OCR +
   structure is paid once per edition, not per user.
2. **Prewarm only the top stories on Gemini TTS via Batch mode** (50 % off) —
   ~35 min of premium audio for **₹13–26**. Edition total lands at **₹35–50**.
3. **Narrate the long tail and the Live feed on Google Cloud TTS Standard/WaveNet
   Telugu voices**, which are **free for 4 M characters/month** (≈ 22 full
   editions or ~4,000 headlines a day) and ₹0.38/1k chars after that. Browser
   `speechSynthesis` on Android Chrome is the ₹0 first choice for headlines.
4. **Stop storing WAV.** 24 kHz PCM is ~2.9 MB/min; Opus/MP3 at 32 kbps is ~0.24 MB/min.
   That is why the audio bucket blew the Supabase quota.
5. **Migrate off every `gemini-2.5-*` model before 16 Oct 2026** — Google retires
   the 2.5 line then, and every model call in this repo is on it.

---

## 1. What you have (short — see git history for the long version)

Five pipelines touch a model; the rest (podcasts, AIR, Mann Ki Baat, markets,
cricket) is fetch-and-parse with no model cost.

| Pipeline | Entry | Models today | Who pays |
|---|---|---|---|
| Edition ingest (Paper) | `documents-process-edition` → `_shared/structure.ts` | Sarvam OCR; Gemini 2.5 Flash (page + block manifest → structure JSON); Flash‑Lite (coherence, continuation, printed date) | User BYOK key |
| Narration | `documents-synthesize` | `gemini-2.5-flash-preview-tts`, 1450-char chunks, 24 kHz WAV → R2 | GatiVani shared key |
| Vāni Q&A | `documents-ask` | `gemini-flash-latest` over article + edition index | Shared key |
| Explainers (Live) | `feeds-explains` | Flash‑Lite over scored headlines | Shared key |
| Summaries / single doc | `documents-summarize`, `documents-process` | Flash | Shared / BYOK |

The structuring engine's invariant — **the model only returns block indices over
Sarvam OCR ground truth, never Telugu text** — is the best design decision in the
repo. Keep it.

Findings that matter for cost and reliability:

- **Serial, non-durable page chain** (`fireContinuation` self-fetch). One killed
  invocation strands the job; 20 pages ≈ 14 min.
- **Full page PDF sent to Gemini** (up to 15 MB base64) up to three times per page.
- **Quota ladder** (`flash → flash-lite → text-only`, 2 tries each) exists because
  free-tier keys 429 at 3–15 RPM. It is a symptom, not a design.
- **WAV storage.** `article_chunks` + R2 hold raw 24 kHz PCM. A 4-hour edition is
  ~700 MB.
- **No per-call usage logging**, so nothing here can be measured today.
- **Tests reference deleted services** and `ci.yml` runs with
  `continue-on-error: true`. `packages/app/docs/ARCHITECTURE.md` is fiction.
- **`documents-synthesize` accepts arbitrary `text`** for any signed-in user (120/hr
  cap only) on the shared key.

---

## 2. The budget, line by line

### 2.1 Unit prices (2026-09-02)

| Item | Price | Notes |
|---|---|---|
| Sarvam Vision OCR | **₹0.50 / page** | cut from ₹1.50 in 2026 |
| Gemini 2.5 Flash | $0.30 in / $2.50 out per 1M | **retires 16 Oct 2026** |
| Gemini 2.5 Flash‑Lite | $0.10 / $0.40 | retires 16 Oct 2026 |
| Gemini 3.1 Flash‑Lite (preview) | $0.25 / $1.50 | successor, *verify* |
| Gemini 3.5 Flash‑Lite | $0.30 / $2.50 | successor, *verify* |
| Gemini image/PDF input | 258 tokens per 768×768 tile; a PDF page = 1 image | |
| Gemini 2.5 Flash TTS | $0.50 text in / **$10 per 1M audio tokens**; 25 tokens/s → **$0.90/hour ≈ ₹1.43/min** | |
| Gemini 3.5 Flash TTS | $6 per 1M audio tokens → **$0.54/h ≈ ₹0.86/min** | *verify* |
| Gemini 3.1 Flash TTS | $20 per 1M → $1.80/h | avoid |
| Gemini Batch mode | **50 % off**, TTS included | results within 24 h |
| Gemini TTS free tier | 3 RPM / 15 RPD | unusable for anything |
| Google Cloud TTS Standard / WaveNet te‑IN | **0–4 M chars/month free**, then **$4 / 1M chars ≈ ₹0.38 / 1k chars ≈ ₹0.27/min** | returns MP3/OGG directly; WaveNet free tier *verify* |
| Google Cloud TTS Chirp 3 HD | 1 M free/month, then $30/1M | premium tail option |
| Azure Neural TTS te‑IN | 0.5 M chars/month free, then $16/1M | second free pool |
| Sarvam Bulbul v2 / v3 | ₹15 / ₹30 per 10k chars → ₹1.05 / ₹2.1 per min | more expensive than Gemini per minute |
| Browser `speechSynthesis` te‑IN | ₹0 | Android Chrome + Google TTS engine; quality varies by device |

### 2.2 An edition

Assumptions from the code: ~147 articles per edition (from the `5/147` flag
statistic in `structure.ts`), 800–1,200 Telugu chars per article, **700 chars/min**
(the constant in `documents-process`). So **118k–176k chars ≈ 168–252 min of audio**.

**Processing (paid once per edition, shared across users):**

| Step | Model | Per page | 20 pages |
|---|---|---|---|
| OCR | Sarvam Vision | ₹0.50 | **₹10.0** |
| Structure assign (image tiles ≈ 3k tok + manifest ≈ 8k tok in, 1.5k out) | 2.5 Flash‑Lite (until Oct) | ₹0.16 | ₹3.3 |
| | 3.5 Flash‑Lite (after Oct) | ₹0.65 | ₹13.0 |
| Coherence + vision gap pass (flagged pages only) + date | Flash‑Lite | ₹0.05 | ₹1.0 |
| Continuation stitch | Flash‑Lite, once | — | ₹0.1 |
| **Processing total** | | | **₹14 now · ₹24 after Oct** |

**Narration options for the same edition:**

| Strategy | Audio | Cost | Under ₹50 with processing? |
|---|---|---|---|
| Everything on Gemini 2.5 Flash TTS, interactive | 168–252 min | ₹240–360 | No |
| Everything on Gemini 3.5 Flash TTS, Batch | 168–252 min | ₹72–108 | No |
| Everything on Google Cloud Standard, beyond free tier | 118–176k chars | ₹45–67 | Borderline |
| Everything on Google Cloud Standard, **inside 4 M free/month** | up to ~22 editions | **₹0** | **Yes** |
| **Top 24 stories prewarmed on Gemini 3.5 Flash TTS Batch (~35 min), tail on Cloud Standard free** | 35 min premium + rest lazy | **₹15 + ₹0** | **Yes: ₹29 now, ₹39 after Oct** |
| Same, prewarm on Gemini 2.5 Flash TTS Batch | | ₹25 + ₹0 | Yes: ₹39 / ₹49 |
| Tail synthesised lazily on Gemini per play | ~₹0.86–1.43 per listened minute | user-driven | Only if listening is short |

The hybrid row is the recommendation. Premium voice where most taps land, free
Telugu voice everywhere else, nothing synthesised twice.

### 2.3 The Live feed

Headlines are ~80–120 chars; explainers ~1,500. At 200 headlines + 2 explainers per
language per day: **~25k chars/day ≈ 750k/month**, comfortably inside Google Cloud
TTS's 4 M free characters, and one cache entry per headline serves every user.
Order of preference:

1. **Browser `speechSynthesis` (te‑IN)** — ₹0, no round trip, no storage. Available on
   Android Chrome with the Google TTS engine, most desktop Chrome, not iOS Safari for
   Telugu. Feature-detect and prefer it for headlines and the ticker.
2. **Google Cloud TTS Standard te‑IN** server-side, cached per headline hash in R2 as
   MP3 — the free-tier pool.
3. **Azure Neural te‑IN** as a second free pool (0.5 M/month) if Google's runs out.
4. **Never Gemini TTS for the Live feed.** Its free tier is 15 requests/day and its
   paid tier is ~5× Cloud Standard per minute.

---

## 3. Target design

### 3.1 Principles

1. Deterministic first, model second (atomize / assemble / validate / regex stay
   model-free — they already are).
2. **Process once, share.** Page-level `ocr_hash` dedupe; a second upload of the same
   Eenadu edition costs ₹0 to process and ₹0 to narrate.
3. **Cheap tier by default, escalate on a deterministic signal.** Flash‑Lite for every
   page; re-run on Flash only pages that fail `checkAssignment` or carry > N review
   flags. The flags already exist.
4. **Two TTS lanes.** Premium (Gemini, Batch, prewarmed top stories) and Free (Cloud
   Standard / browser) for the tail and Live. Both cached forever as Opus/MP3.
5. **Durable, parallel orchestration.** A queue + per-page state row replaces the
   self-fetch chain.
6. **Measure.** Every model and TTS call logs its units (tokens, chars, seconds) and ₹.

### 3.2 Model routing (Gemini)

| Tier | Model (now → after 16 Oct) | Effort | Used for |
|---|---|---|---|
| T0 | none | — | atomize, assemble, validate, regex continuation, feed parse, caches |
| T1 | 2.5 Flash‑Lite → 3.1/3.5 Flash‑Lite | thinking off | **structure assignment** (default), coherence, printed date, category, 3-fact summary, explainers |
| T2 | 2.5 Flash → 3.5 Flash | thinking low | escalation only (failed/heavily flagged pages), vision gap pass, continuation semantic match, Vāni Q&A |
| TTS‑P | 2.5 Flash TTS → 3.5 Flash TTS, **Batch** | — | prewarmed top stories per section |
| TTS‑F | Cloud TTS Standard/WaveNet te‑IN (MP3), browser speechSynthesis | — | everything else, Live feed |

Rules that keep it cheap:

- **Downscale the page.** Render each 1-page PDF to a ~1600 px-tall JPEG before any
  model call; that is ~6 tiles ≈ 1.5k tokens instead of a 15 MB PDF. Use
  `responseSchema` (Gemini structured output) with the existing `Assignment`
  shape; delete the regex JSON scrape and the "invalid, retry" loop.
- **Manifest is the big input.** Telugu tokenises expensively; shorten `head/tail`
  snippets (72/32 → 48/24 chars) and drop `cls=paragraph` for body blocks; measure
  on the golden set before and after.
- **Context caching on the static prompt** (`ASSIGN_PROMPT` + category rules) is
  worth it only on a paid key with steady volume; skip on BYOK free tier.
- **Thinking off on Flash‑Lite for structure**; thinking tokens are billed as output
  and the task is classification over a manifest, not reasoning.
- **Batch mode for the shared-edition lane** (processing *and* TTS): 50 % off, and
  nobody is waiting overnight.

### 3.3 Orchestration

```
uploads/editions/<id>.pdf
   ▼
[ingest_jobs]  queued → splitting → pages → stitching → ready | failed
   ▼ split (T0): one [ingest_pages] row per page (job_id, page, status, ocr_hash), enqueue N
   ├──────────────┬──────────────┬───── … ─────┐        k parallel page workers
   ▼              ▼              ▼             ▼        idempotent on (job_id, page, step)
 OCR (Sarvam) → hash → dedupe hit? copy prior articles, skip all model calls
             → raster (T0) → structure (T1, schema) → validate (T0)
             → escalate (T2) only if failed / flags > N → insert articles
   ▼ when all pages terminal
 stitch (T0 regex → T2 once) → ready
   ▼
 prewarm lane: top 3 stories/section → Gemini TTS Batch → Opus → R2
 tail lane:    on first play → Cloud TTS Standard (MP3) → R2, or browser TTS
```

**Where the queue runs.** Supabase-native, smallest change: `pgmq` for the queue,
`pg_cron` every 10–15 s hitting `pipeline-dispatch` via `pg_net`, which pops ≤ k
messages and invokes `pipeline-page`. State in `ingest_jobs` / `ingest_pages`, RLS
scoped to the owner (closes the world-readable `processing_jobs` TODO). Cloudflare
Queues + Workers is the alternative if edge wall-clocks keep biting;
`structure.ts` is plain TS and ports cleanly. Start at k = 4: 20 pages drop from
~14 min to ~4.

### 3.4 Audio storage and format

- **Encode before storing.** Gemini TTS returns PCM; encode to **MP3 via `lamejs`
  (pure JS, runs in Deno)** or Opus via a WASM encoder, at 32–48 kbps mono. Cloud
  TTS returns MP3/OGG natively (`audioEncoding: MP3`), no transcode.
- 24 kHz PCM WAV ≈ 2.9 MB/min → MP3 32 kbps ≈ 0.24 MB/min: **12× smaller**. A 4-hour
  edition goes from ~700 MB to ~60 MB; R2's 10 GB free tier holds ~170 editions
  instead of ~14.
- Keep the `text_hash` content-match (`3a77400`). Add: for a real `articleId`, verify
  `text` equals `articles.full_content` *before* synthesis, not just on cache read.
- Retention: keep prewarmed audio for the edition's shelf life (7 days), tail audio
  30 days since last play; `storage-cleanup` already exists.

### 3.5 Sentence timing without STT

`alignment.ts` (Sarvam STT forced alignment) is disabled for cost. Chunk boundaries
are exact; inside a chunk, distribute time proportionally by character count with a
per-sentence pause weight. No model, no cost, good enough for karaoke highlighting.
Cloud TTS also returns **SSML `<mark>` timepoints** for free if you want real
sentence marks on the Free lane.

### 3.6 The rest of the model surface

| Function | Today | Target |
|---|---|---|
| `documents-ask` (Vāni) | flash-latest, 6k + 8k chars per call | T2; cap index at 4k chars, `maxOutputTokens` 600, answer by index number |
| `feeds-explains` | 2.5 Flash‑Lite | T1; cache per (lang, day) in `feed_cache` (table exists); narrate on TTS‑F |
| `documents-summarize` | 2.5 Flash | T1, `responseSchema {facts: string[3]}` |
| `documents-process` (single doc) | Flash classify + correct + legacy HTML parser | delete the legacy parser; classify T1; correction T1 only for sloka/mantra types |
| `detectPrintedDate` | Gemini on page bytes | regex on Sarvam text first, T1 on a masthead crop as fallback |

---

## 4. Implementation plan

Phases are independently shippable, ordered by ₹ saved per day of work. Each names
the files it touches.

### Phase 0 — Measure and stop the bleeding (2–3 days)

1. Migration `model_calls(fn, model, kind: llm|tts|ocr, job_id, page, input_tokens,
   output_tokens, chars, audio_seconds, inr_estimate, latency_ms, ok, created_at)`,
   service-role only. Every Sarvam, Gemini and TTS call writes one row. A daily view
   `edition_cost` sums it per `newspaper_id`. **This is the ₹50 meter.**
2. **Raster pages** in a new `_shared/raster.ts` (pdfium via `npm:@hyzyla/pdfium`)
   before any Gemini call; send JPEG, not PDF. Measure tokens/page before and after.
3. **Encode audio** in `documents-synthesize`: PCM → MP3 (`lamejs`) before `storeAudio`.
   Client `PlaybackService` already plays by URL; `just_audio` handles MP3.
4. CI honesty: remove `continue-on-error`, delete/rewrite the tests that reference
   removed services. Replace `packages/app/docs/ARCHITECTURE.md` with a pointer.

### Phase 1 — Cheaper structuring + the 2.5 retirement (≈ 1 week)

1. `_shared/gemini.ts`: one client for all Gemini calls — model tier map (with the
   post-October IDs behind an env switch), `responseSchema`, thinking config, 429
   backoff, `model_calls` logging, and `escalate()` (T1 → T2 on a failed check).
2. `structure.ts`: replace the 4-config ladder with T1 → T1 with the check error
   appended → T2. Shorten manifest snippets. Keep atomize/assemble/validate.
3. **Golden set + eval runner** (`scripts/eval_structure.ts`): the page validated in
   `gativani-extraction/CHALLENGE` (15 correct vs 4) plus ~10 hand-checked pages.
   Score article count, headline match, flag rate, ₹/page from `model_calls`. Run
   2.5 Flash‑Lite, 3.1 Flash‑Lite, 3.5 Flash‑Lite, 2.5 Flash. Ship the cheapest that
   matches today's quality. **Do this before 16 Oct.**

### Phase 2 — Free-lane TTS + Live feed (≈ 4–5 days)

1. `documents-synthesize`: add `lane: "premium" | "free"`; free lane calls Cloud TTS
   `te-IN-Standard-*` / `Wavenet` with `audioEncoding: MP3`, cached by `text_hash`
   like today. Default the Live feed, explainers and every non-prewarmed article to
   the free lane.
2. Flutter: `speech_web.dart` already wraps `SpeechRecognition`; add
   `speak_web.dart` for `speechSynthesis` with te‑IN voice detection. Use it for
   headlines/ticker when a Telugu voice exists; fall back to the free lane URL.
3. Second free pool (Azure te‑IN neural) behind the same interface, only if the
   Google pool is exhausted mid-month.

### Phase 3 — Durable, parallel, shared editions (1–2 weeks)

1. Migrations: `ingest_jobs`, `ingest_pages` (`ocr_hash`, `step`, `attempts`,
   `last_error`); enable `pgmq`, `pg_cron`, `pg_net`; owner-scoped RLS.
2. Functions `pipeline-start`, `pipeline-dispatch`, `pipeline-page`,
   `pipeline-finalize`; `documents-process-edition` becomes a shim, then goes.
3. Page dedupe on `ocr_hash` → copy prior articles, skip all model calls.
4. Client `pollEdition` reads `ingest_jobs`.

### Phase 4 — Prewarm lane on Gemini Batch (≈ 3–4 days)

1. `pipeline-finalize` picks top 3 stories per section (position on page 1, headline
   size class, section weight) and submits one Gemini **Batch** TTS job per edition.
2. A `pg_cron` poller collects results, encodes MP3, writes `article_chunks`.
3. First-launch UX: the Paper tab no longer needs a BYOK key for shared editions;
   keep BYOK only for personal uploads if you want that lane to stay ₹0 to you.

---

## 5. Using Claude models to *build* this (not to run it)

If "Sonnet 4.6 / Opus 4.5" meant the coding agents rather than the runtime: run
Phases 0–4 as Claude Code sessions with **Sonnet for implementation** (each phase
step above is one well-scoped task with named files and a test) and **Opus for the
two design-heavy pieces** — the `pgmq` orchestration (Phase 3) and the golden-set
eval harness (Phase 1.3) — plus a final review pass. Give every session this file,
the README, and `structure.ts`; ask for a PR per phase step.

---

## 6. Decisions that are yours

1. **Prewarm voice:** Gemini 3.5 Flash TTS (₹15/edition, *verify* price) vs 2.5 Flash
   TTS (₹25, retiring). Cloud Chirp 3 HD te‑IN is a third option at ₹0 inside its
   1 M free chars.
2. **How much to prewarm:** 3 stories/section ≈ 35 min ≈ ₹15. Every extra story is
   ~₹0.6–1.
3. **Free-lane voice quality:** Standard vs WaveNet te‑IN — listen to both on 10
   articles; both are inside the free tier (*verify* WaveNet's free allowance).
4. **Queue platform:** Supabase (`pgmq`) unless you already plan to move to Workers.
5. **Shared daily editions** need publisher permission per title.

---

## Sources (2026-09-02)

- Sarvam Vision ₹0.50/page: [Free Press Journal](https://www.freepressjournal.in/tech/sarvam-ai-slashes-vision-api-pricing-by-67-bringing-document-digitisation-within-reach-for-indian-enterprises), [News Mobile](https://www.newsmobile.in/artificial-intelligence-ai/sarvam-ai-cuts-vision-api-prices-by-67-after-digitising-35-million-pages/)
- Sarvam Bulbul ₹15/₹30 per 10k chars: [Sarvam TTS guide](https://www.heyakashmaurya.com/blog/sarvam-ai-tts-complete-guide), [Sarvam pricing](https://www.sarvam.ai/api-pricing)
- Gemini 2.5 Flash / Flash‑Lite prices and 16 Oct 2026 retirement: [Morph](https://www.morphllm.com/gemini-api-pricing), [metacto](https://www.metacto.com/blogs/the-true-cost-of-google-gemini-a-guide-to-api-pricing-and-integration), [BenchLM](https://benchlm.ai/google/api-pricing)
- Gemini 3.1 / 3.5 Flash‑Lite prices: [pricepertoken](https://pricepertoken.com/pricing-page/model/google-gemini-3.1-flash-lite-preview), [OpenRouter](https://openrouter.ai/google/gemini-3.5-flash-lite)
- Gemini image tiling (258 tokens / 768 px tile, PDF page = image): [puter](https://developer.puter.com/tutorials/gemini-api-pricing/), [geotoolbox](https://geotoolbox.ai/blog/gemini-api-pricing)
- Gemini TTS 25 tokens/s, 2.5 Flash TTS $0.50/$10, 3.1 Flash TTS $1/$20, 3.5 Flash TTS $6, free tier 3 RPM / 15 RPD, Batch 50 %: [invideo](https://invideo.io/blog/gemini-tts-ai-voice/), [Bifrost calculator](https://www.getmaxim.ai/bifrost/llm-cost-calculator/provider/gemini/model/gemini-2.5-flash-preview-tts), [aifreeapi](https://www.aifreeapi.com/en/posts/gemini-api-free-tier-complete-guide), [apidog batch](https://apidog.com/blog/gemini-api-batch-mode/), [Rogue Marketing](https://the-rogue-marketing.github.io/google-gemini-tts-speech-audio-api-pricing-may-2026/)
- Google Cloud TTS free tier and $/1M: [costbench](https://costbench.com/software/ai-voice-tools/google-cloud-text-to-speech/free-plan/), [TextToLab](https://texttolab.com/blog/google-cloud-tts-pricing), [voice list](https://docs.cloud.google.com/text-to-speech/docs/list-voices-and-types)
- Azure Neural TTS F0 0.5 M chars, $16/1M, Telugu: [TextToLab](https://texttolab.com/blog/azure-text-to-speech-pricing), [Microsoft Learn quotas](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-services-quotas-and-limits)
- USD/INR ≈ 94.9 on 2026-09-01: [Trading Economics](https://tradingeconomics.com/india/currency), [Wise](https://wise.com/in/currency-converter/usd-to-inr-rate/history)
