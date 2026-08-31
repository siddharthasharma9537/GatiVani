# Migrating the `audio` bucket to Cloudflare R2

**Status:** planned, not started. Written 2026-08-31, during the Supabase storage
lockout.

## Why

The `audio` bucket held 306 objects / 1238 MB of cached TTS with no retention
policy, growing ~600 MB/month. It crossed the Free plan's 1 GB storage cap and put
the whole Supabase project into `exceed_storage_size_quota`, where **every** edge
function returns 402 — the news feeds, the database APIs, everything. A bucket of
regenerable audio took down services that have nothing to do with audio.

R2 fixes both halves of that:

| | Supabase Free | R2 Free |
| --- | --- | --- |
| Storage | 1 GB | 10 GB-month |
| Egress | 5 GB, counts toward quota | free, unmetered |
| Over quota | 402 on every service | billed $0.015/GB-month |

The blast radius is the real prize. After this, a storage problem can only ever
break audio playback.

Note this is a return to an existing pattern, not a new one: `voxnews-audio`,
`newscast` and `chanttracker-audio` were all R2 buckets. gativani is the only
project that put audio in Supabase Storage, and the only one that hit a wall.

## Scope

**In:** the `audio` bucket only — synthesized article/brief audio and cached AIR
bulletins.

**Out:** the `uploads` bucket (37 objects / 107 MB of source PDFs). The Dart client
uploads to it directly with a signed session in `document_service.dart:102`, and
moving it means reworking browser upload auth for no benefit — it isn't growing.
Postgres, Auth, and the edge functions all stay on Supabase; see the "why not a
full migration" note at the end.

## The one architectural constraint

**Supabase Edge Functions cannot have R2 bindings.** Bindings (`env.BUCKET.put()`)
exist only inside Cloudflare Workers. Our functions run on Deno on Supabase's
runtime, so they must talk to R2 over its **S3-compatible API** with signed
requests.

Two ways to do that:

- **A. S3 API from the existing functions** (recommended) — add
  [`aws4fetch`](https://github.com/mhart/aws4fetch) (tiny, Deno-compatible) and sign
  requests to `https://<account-id>.r2.cloudflarestorage.com/gativani-audio/<key>`.
  Everything stays where it is; only the storage calls change.
- **B. Move the audio-writing functions to Workers** — native bindings, no signing,
  but `documents-synthesize` is the largest and most intricate function we have
  (chunking, rate limits, content-match checks, the Gemini calls). Porting it to
  get slightly nicer storage syntax is not a trade worth making now.

Go with **A**. Revisit B only if we later move functions to Workers for other
reasons.

## Serving audio publicly

The Flutter app treats `audio_url` as an opaque absolute URL — it fetches whatever
the database gives it (`playback_service.dart`, `audio_download_service.dart`,
`downloads_store.dart`). So **no app changes are needed** as long as the new URLs
are publicly fetchable over HTTPS with byte-range support. That is the single
biggest reason this migration is cheap.

Two ways to expose the bucket:

- **Custom domain (required for production).** Cloudflare's docs are explicit that
  the `r2.dev` development URL "is not intended for production usage", is rate
  limited to hundreds of requests/second with `429`s, and may have bandwidth
  throttled. Audio streaming is exactly the workload that trips this.
- **`r2.dev` public development URL** — fine for the first end-to-end test, not for
  real traffic.

**Blocker to resolve first:** a custom domain requires the zone to live in the same
Cloudflare account as the bucket. `sohum.cloud` currently has its DNS at GoDaddy
(that's where the Google site-verification TXT record lives). So one of:

1. Move the `sohum.cloud` zone to Cloudflare — cleanest, but changes nameservers and
   affects the Vercel deployment and the Google verification TXT record. Not to be
   done casually.
2. Add `sohum.cloud` to Cloudflare with a **partial (CNAME) setup**, which is
   designed exactly for this and leaves GoDaddy authoritative.
3. Use a different domain already on Cloudflare, if one exists.

Target hostname: `audio.gativani.sohum.cloud` (or `audio.sohum.cloud`).

**Decide this before writing code** — the public URL prefix is baked into every
`audio_url` we write, and changing it later means rewriting rows again.

## Call sites to change

All R2 reads/writes go through one new helper, `supabase/functions/_shared/r2.ts`,
exposing `put`, `remove`, `list`, `head`, and `publicUrl`. Only that file knows
about signing.

| File | Line | What it does now | After |
| --- | --- | --- | --- |
| `documents-synthesize/index.ts` | 482–489 | uploads `articles/{id}{.brief}.chunk{n}.wav`, then `getPublicUrl` | `r2.put` + `r2.publicUrl` |
| `documents-synthesize/index.ts` | 538–545 | uploads the full `articles/{id}{suffix}` | same |
| `feeds-podcasts/index.ts` | 231 | caches the AIR bulletin mp3 at `air/{date}-{hhmm}.mp3` | `r2.put` |
| `feeds-podcasts/index.ts` | 192 | `getPublicUrl` + `HEAD` to test cache hit | `r2.publicUrl` + `r2.head` |
| `feeds-podcasts/index.ts` | 297 | `.list("air", …)` to find the newest bulletin | `r2.list("air/")` — **note the shape change**, S3 `ListObjectsV2` returns XML with `Key`/`Size`/`LastModified`, not Supabase's JSON. This is the fiddliest edit in the migration. |
| `feeds-podcasts/index.ts` | 312 | `getPublicUrl` for the listed file | `r2.publicUrl` |
| `storage-cleanup/index.ts` | — | `storage.from("audio").remove(batch)` | `r2.remove(batch)`; the `stale_audio_objects` SQL lookup is replaced by an `r2.list` over the whole bucket filtered on `LastModified` |
| `documents-synthesize/alignment.ts` | 142–144 | writes `articles/{id}.timings.json` | leave alone — STT alignment is disabled for cost; migrate only if it's ever re-enabled |

Keep the key layout identical (`articles/…`, `air/…`). Same paths, different host,
which keeps the backfill a straight copy and makes rollback trivial.

## Sequencing

Steps 1–4 can be done now, while the project is still restricted. Steps 5–6 need
Supabase storage reads to work again.

1. **Create the bucket and credentials.** `gativani-audio` in R2. Generate an R2 API
   token scoped to *that bucket only*, Object Read & Write. Set
   `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_PUBLIC_BASE`
   via `supabase secrets set`.
2. **Resolve the custom domain** per the section above, and point it at the bucket.
3. **Write `_shared/r2.ts`** and unit-test `put`/`head`/`list` against a throwaway
   key before touching any caller.
4. **Switch the writers.** New audio goes to R2 from here on. Because `audio_url`
   is stored absolute, old rows keep pointing at Supabase and keep working — the
   system runs dual-source with no flag day. **This is the point at which the
   growth problem stops.**
5. **Backfill** the existing objects (~141 to delete first, then whatever remains —
   likely ~700 MB) with `rclone` Supabase → R2, preserving keys. Then rewrite the
   stored URLs:
   ```sql
   update articles set audio_url = replace(audio_url,
     'https://jjoxowdvzmlchtfarpbs.supabase.co/storage/v1/object/public/audio/',
     'https://audio.gativani.sohum.cloud/')
   where audio_url like '%/object/public/audio/%';
   ```
   Repeat for `articles.summary_audio_url`, `edition_page_items` (both columns),
   and `article_chunks.audio_url`. Do it in a transaction and count rows first.
6. **Verify, then empty the Supabase bucket** — which also permanently ends the
   quota problem that started all this.

## Retention still matters

R2's 10 GB is 10× the headroom, not infinite, and R2 also bills storage as a
GB-month average. At ~600 MB/month with no retention we would reach 10 GB in about
16 months and start paying. Keep `storage-cleanup` (committed in `fefcb14`), just
repointed at R2. The consequence of ignoring it becomes a small bill rather than a
total outage — which is the improvement we actually want.

## Risks

- **Losing the 402-blast-radius benefit by accident.** If the R2 credentials are
  wrong, `documents-synthesize` fails and no audio is produced. Make the upload
  failure non-fatal and keep the existing `console.warn` path so synthesis degrades
  to "no cached audio" rather than erroring the request.
- **`r2.dev` in production.** Easy to leave enabled after testing and never notice
  until traffic gets `429`s. Disable the development URL once the custom domain is
  live.
- **The AIR `.list()` rewrite** is the one place where behaviour can silently change
  — Supabase's `list` sorts and paginates differently from S3 `ListObjectsV2`. Test
  that the newest-bulletin selection still picks the right file.
- **Range requests.** Playback seeking depends on HTTP range support. R2 supports
  it, but verify through the custom domain (and through Cloudflare's cache) before
  declaring done.
- **Public bucket = public audio.** Same exposure as today's public Supabase bucket,
  so no regression — but it does mean anyone with a URL can fetch. If that ever
  matters, custom domains support WAF token auth; `r2.dev` does not.

## Why not migrate everything to Cloudflare

Considered and rejected on 2026-08-31. Auth is the blocker: Cloudflare has no
Supabase Auth equivalent, and replacing it means a new Google OAuth client and
redoing the brand verification completed in July ("to continue to Gativani").
Second, 23 RLS policies would become hand-written checks in Worker code, and
hand-rolled authorization fails open where RLS fails closed. Third, D1 is SQLite —
no `jsonb`, no `uuid_generate_v4()`, no security-definer functions — so the 14
migrations and much of 5,817 lines of function code would need reworking.

That is weeks of risk to fix a problem whose cause was one bucket without a
retention policy. Move the storage; leave the rest.
