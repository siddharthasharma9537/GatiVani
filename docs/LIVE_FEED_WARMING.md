# Live feed batch warming

**Status:** built 2026-09-02, not yet exercised against production.

## The problem

The Live feed was a pass-through of `feeds-articles`, narrated on demand. That
put Gemini synthesis on playback's critical path, and the numbers never worked:
one chunk takes **32-52s to synthesize** while a chunk only buys **~45s of
audio**. The first chunk boundary was a coin flip, which is why articles played
for about 45 seconds and then went silent or restarted.

## The design

Double-buffering. A batch is staged, fully narrated out of band under the rate
limit, and only then swapped in front of readers. The previous batch keeps
serving until that swap, so the feed is never empty and never half-narrated.

```
build ──► drain (rate-limited) ──► publish (atomic swap) ──► retire ──► delete
```

An article enters the published payload only once **every** one of its chunks is
cached, so "the audio is ready" is an invariant of the feed rather than
something playback has to race. A batch that partly fails publishes short — it
never publishes a gap.

The second prize is retention. Audio is regenerable and short-lived, and an
unbounded `audio` bucket is what put the project into
`exceed_storage_size_quota` once already (see `R2_AUDIO_MIGRATION.md`), where
every edge function 402s. Double-buffering makes garbage *identifiable* instead
of guessed at: a replaced batch is provably nobody's current feed. Steady-state
residency is ~2 batches instead of unbounded growth.

Two carve-outs on deletion, both load-bearing:
- A story often survives into the next batch — the id is a hash of the publisher
  link, so it is the same article and the same audio. Only ids in **no** live
  batch are garbage.
- An article someone played stays resumable for 24h via `recent_plays`.

## Cadence

The cron is a **tick**, not the cadence. Each tick does a bounded slice; the
real knobs are env vars on the function, so they change with no redeploy:

```
supabase secrets set --project-ref jjoxowdvzmlchtfarpbs \
  WARM_INTERVAL_MINUTES=120 \  # new batch every N min, AND the publish deadline
  WARM_ARTICLES=12 \           # articles per batch
  WARM_RPM=3 \                 # Gemini calls/min, shared with live playback
  WARM_LANGS=te \              # comma-separated
  WARM_MIN_ARTICLES=4 \        # below this, don't publish at all
  WARM_TICK_SECONDS=60 \       # wall-clock budget per tick
  WARM_RETIRE_HOURS=24         # how long replaced audio survives
```

Any of these can also be overridden per-request in the POST body, which is what
the workflow's `workflow_dispatch` inputs use for one-off runs.

`WARM_INTERVAL_MINUTES` does double duty on purpose: it is both how often a new
batch starts and the deadline by which the current one publishes whatever it
has. That makes the cadence self-correcting — if synthesis can't keep up, the
feed still turns over on time with fewer articles, rather than drifting a full
cycle further behind on every turn.

## Rough budget

12 articles ≈ 48 chunks. At `WARM_RPM=3` that is ~16 min of pure call time, and
with a 10-minute tick and `WARM_TICK_SECONDS=60` roughly 3 calls land per tick,
so a batch completes in ~1.5h against a 2h interval. **Watch the requests-per-day
cap, not RPM** — 12 batches/day is ~576 TTS calls. If that exceeds the tier,
raise `WARM_INTERVAL_MINUTES` or lower `WARM_ARTICLES`; nothing else changes.

## Setup

1. `supabase db push` (adds `live_batches`, `live_batch_chunks`, `live_warm_lock`)
2. `supabase secrets set CRON_SECRET=... --project-ref jjoxowdvzmlchtfarpbs`
   — must match the `CRON_SECRET` repo secret; the workflow skips without it
3. Set the cadence vars above (all have defaults; none are required)
4. Deploy: `feeds-warm` and `feeds-articles` both ship on the next push to main

Until a batch is published, `feeds-articles` behaves exactly as before — the
live publisher fetch. Warming off, first deploy, or an unwarmed language all
degrade to the old behaviour rather than to an empty feed.

## Verifying

```
curl -X POST .../functions/v1/feeds-warm -H "x-cron-secret: $CRON_SECRET" \
  -H 'Content-Type: application/json' -d '{"force": true, "articles": 3}'
```

Returns the config it ran with plus a per-language action
(`built` / `draining` / `published` / `discarded` / `idle`). `feeds-articles`
responses carry `source: "batch" | "live"` so you can see which path served a
request.

---

# TTS provider: Google Cloud TTS (Standard)

**Status:** built 2026-09-02, not yet exercised against a real key.

## Why

The Gemini Developer API's free tier for `gemini-2.5-flash-preview-tts` is
**15 requests per day** — about three articles. Past that every call 429s,
`_advanceChunk` throws, and playback dies at the first chunk boundary. That is
a second, independent cause of the "stops at ~45s" report, and no amount of
pacing fixes it.

Cloud TTS is rate-limited **per minute** (1,000 RPM for Standard), with **4M
free characters a month**. The daily wall disappears.

`te-IN` offers exactly two tiers — confirmed via `voices.list`:

| Tier | Voices | Free/month | After |
| --- | --- | --- | --- |
| Standard | A, C (F) · B, D (M) | 4M chars | $4/1M |
| Chirp 3: HD | 30, incl. Kore & Puck | 1M chars | $30/1M |

Chirp 3: HD carries the same `Kore`/`Puck` voices this app shipped with, so it
would sound unchanged. **Standard was chosen deliberately for the 4M free
allowance**, and it is audibly flatter. Switching is a one-string change to
`googleVoice()`.

## Configuration

```
supabase secrets set GOOGLE_TTS_API_KEY=... --project-ref jjoxowdvzmlchtfarpbs
```

Setting that key switches the provider. To roll back, clear it — or set
`TTS_PROVIDER=gemini`, which wins over the key. No redeploy either way.

## Two things that bite

**Chunk boundaries are part of the cache key.** `article_chunks` stores audio
per chunk INDEX, and the boundaries are a function of the provider's size
limits, not of the text. A provider switch therefore repoints every cached
index at a different slice of the article while the text hash still matches.
`textHash` folds in the provider name so this is a clean miss and a
re-synthesis. Any future change to the chunk limits needs the same treatment.

**Cloud TTS caps a request at 5,000 BYTES, not characters.** Telugu is 3 bytes
per character, so a chunker measuring `String.length` passes every English test
and ships oversized requests on the only language this app serves. `chunkText`
takes a `byBytes` flag; the Google path sets it. Verified against real Telugu:
max chunk 3,885 bytes.

## Not verified

- **API-key auth is assumed.** The code calls `text:synthesize?key=...`. If
  Cloud TTS rejects API keys for this project it needs a service account and an
  OAuth token instead — a real change, not a config tweak. Test before deploy:
  ```
  curl -s -X POST "https://texttospeech.googleapis.com/v1/text:synthesize?key=$KEY" \
    -H 'Content-Type: application/json' \
    -d '{"input":{"text":"పరీక్ష"},"voice":{"languageCode":"te-IN","name":"te-IN-Standard-B"},"audioConfig":{"audioEncoding":"LINEAR16","sampleRateHertz":24000}}' \
    | head -c 200
  ```
- **The free tier still requires billing enabled** on the project.
- LINEAR16 responses are assumed to carry a 44-byte WAV header, which is what
  the duration maths divides out. A different header size skews duration by
  ~1ms — harmless, but it is an assumption.
