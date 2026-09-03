# Setup checklist — what to do on your machine

Everything in `docs/ORCHESTRATION_PLAN.md` was written and committed in a
sandbox with **no Deno, no Flutter and no Supabase CLI**. The code is
typechecked and parse-checked, and the tricky pure functions were executed
against Node, but nothing has been run against a real project. This is the list
of things only you can do.

Ordered so that each step is verifiable before the next one depends on it.
**Nothing in this branch changes behaviour until step 4** — every new capability
is behind a secret or a flag.

---

## 0 · Toolchain (one time)

```bash
brew install supabase/tap/supabase deno
supabase --version && deno --version && flutter --version
```

`deno` matters more than it looks: it is the only thing that can truly check the
edge functions. CI typechecks them with `tsc` and stubbed module specifiers,
which catches undefined identifiers but not a wrong import path into a real
package.

---

## 1 · Get the branch and check what CI cannot

```bash
git fetch origin
git checkout claude/gativani-analysis-design-3ate8o

# The real check on the edge functions — resolves npm:/jsr: for real.
deno check --node-modules-dir=auto supabase/functions/*/index.ts supabase/functions/_shared/*.ts

# The Flutter side, neither of which has been run.
cd packages/app && flutter pub get && flutter analyze && flutter test && cd ../..
```

> **Ran 2026-09-03, and it found four more.** `deno check` caught a NaN scale
> factor and a swapped red/blue channel in `raster.ts`, plus two typing gaps;
> `flutter analyze` caught a test that imported the wrong package name and so
> had never compiled. All fixed in `ba17cfa` — both checks are now clean, and
> `flutter test` passes 14/14. Re-run them anyway after any further change.
>
> **Two runtime-fatal bugs shipped on this branch before a typechecker existed**
> (a call to an undefined `renderAudio`, and a `CONT_FROM` regex whose
> declaration an extraction dropped). Both are fixed and CI now runs `tsc`, but
> `deno check` is strictly stronger. Run it before deploying.

---

## 2 · Google Cloud — already done, nothing to do

~~The free narration lane needs Cloud TTS, and Cloud TTS needs **OAuth, not an
API key** — which is why the function signs a service-account JWT.~~

**That was wrong, and this whole section is now obsolete.** Cloud TTS accepts
API-key auth on both `voices.list` and `text:synthesize`. The project already
has the `GatiVani Cloud TTS` key, restricted to the Cloud Text-to-Speech API and
stored as the `GOOGLE_TTS_API_KEY` secret, so there is no service account to
create, no JSON key to download, and no `GOOGLE_SERVICE_ACCOUNT_JSON` to set.
`_shared/gcloud_auth.ts` was deleted.

### 2a · Telugu voice names — verified 2026-09-03

Done, and it found a bug. The API's actual te-IN inventory:

| Tier | Voices | Rate | Free pool |
|---|---|---|---|
| Standard | `te-IN-Standard-A` … `-D` | $4/1M chars | 4M/month |
| Chirp3-HD | `te-IN-Chirp3-HD-*`, 30 of them | $30/1M chars | 1M/month |

**There is no WaveNet and no Neural2 for Telugu.** `te-IN-Wavenet-A` — which
`VOICE_BY_SURFACE` pinned to `live_article` *and* `live_ticker`, the two
most-heard surfaces — does not exist:

```
te-IN-Wavenet-A            HTTP 400  Voice 'te-IN-Wavenet-A' does not exist. Is it misspelled?
te-IN-Standard-A           HTTP 200  17152 bytes
te-IN-Chirp3-HD-Achernar   HTTP 200   8832 bytes
```

Both live surfaces moved to `te-IN-Standard-A`. The comment justifying WaveNet
("better voice at the same paid rate as Standard") was wrong twice over —
WaveNet bills $16/1M, not $4/1M, and for Telugu it is not offered at all. With
no mid tier to promote to, the only upgrade is Chirp3-HD at 7.5x the rate and a
quarter of the free headroom, so that stays reserved for `edition_top`. Whether
the live surfaces are worth it is a question for `edition_cost` once it has real
numbers.

To re-check after any voice change:

```bash
curl -s "https://texttospeech.googleapis.com/v1/voices?languageCode=te-IN&key=$GOOGLE_TTS_API_KEY" \
  | jq -r '.voices[] | "\(.name)\t\(.ssmlGender)"' | sort
```

---

## 3 · Link the project

```bash
supabase login
supabase link --project-ref jjoxowdvzmlchtfarpbs
```

---

## 4 · Secrets

`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` and `SUPABASE_ANON_KEY` are injected
by the platform — never set those yourself.

### Already set (verify, don't re-set)

```bash
supabase secrets list
```

Expect `GEMINI_API_KEY`, `SARVAM_API_KEY`, `CRON_SECRET`, and the `R2_*` group.

### Required for the free narration lane — already done

Nothing to set. `GOOGLE_TTS_API_KEY` is present on the project and holds the
console's `GatiVani Cloud TTS` key, restricted to the Cloud Text-to-Speech API.

There is **no service account and no `GOOGLE_SERVICE_ACCOUNT_JSON`**. An
earlier draft of this checklist said Cloud TTS needs OAuth and that an API key
would not work; that was wrong. Both `voices.list` and `text:synthesize` accept
`?key=`, verified against the live API on 2026-09-03, so `_shared/gcloud_auth.ts`
and its JWT signing were deleted rather than configured.

Without the key the free lane logs a warning and falls back to Gemini TTS, so
deploying is safe either way — just not cheaper.

### New — optional, all have working defaults

| Variable | Default | Set it when |
|---|---|---|
| `AUDIO_LANE` | `free` | you need to force everything back to Gemini (`premium`) |
| `AUDIO_FORMAT` | `wav` | after you have watched CPU under `mp3` — see §7 |
| `RASTER_PAGES` | off | after comparing `input_tokens` — see §7 |
| `GEMINI_MODEL_FAST` | `gemini-2.5-flash-lite` | **before 16 Oct** — see §6 |
| `GEMINI_MODEL_STRONG` | `gemini-2.5-flash` | **before 16 Oct** — see §6 |
| `GEMINI_TTS_MODEL` | `gemini-2.5-flash-preview-tts` | **before 16 Oct** — easy to forget, different file |
| `INGEST_CONCURRENCY` | `4` | pages are queueing or Sarvam is rate-limiting |
| `DAILY_CHIRP_CHARS` | `32000` | you change how much is prewarmed |
| `PREWARM_PER_SECTION` | `3` | same |

---

## 5 · Migrate and deploy

```bash
supabase db push
```

**Read the output.** The migration tries to enable `pg_cron` and schedule the
recovery sweep, and *warns rather than fails* if it cannot. If you see that
warning, the pipeline still runs but cannot recover a page whose worker died —
enable pg_cron from Database → Extensions, then:

```sql
select cron.schedule('requeue-stale-ingest-pages', '* * * * *',
                     $$ select public.requeue_stale_ingest_pages(); $$);
```

Then deploy. `_shared` is a directory of modules, not a function — the existing
`deploy-functions.yml` workflow already skips `_*`, and pushing to `main` will
deploy everything for you. To do it by hand:

```bash
supabase functions deploy pipeline-start pipeline-page pipeline-finalize pipeline-status \
  documents-synthesize documents-process-edition documents-ask documents-summarize \
  documents-process feeds-explains cricket-live
```

Finally, check the security linter — the migration adds RLS policies and a
`security_invoker` view, and this is what catches a mistake in either:

```bash
supabase inspect db  # or: Dashboard → Advisors → Security
```

---

## 6 · Before 16 October — the hard deadline

Google retires the Gemini 2.5 line. Every model id now resolves from an env var,
so migrating is a secrets change — but only after you have measured which
successor is good enough.

1. Build a golden set at `eval/pages/<name>/` with `page.pdf`, `ocr.html`
   (Sarvam's output, captured once so runs are deterministic and free) and
   `expected.json` listing the correct headlines. Seed it from the page
   validated during the engine rewrite, and add any page that has misbehaved in
   production — a regression suite of real failures beats a large synthetic one.
2. Score the candidates. **This calls the real API and costs real money.**

```bash
export GEMINI_API_KEY=...
deno run --allow-net --allow-read --allow-env scripts/eval_structure.ts \
  --fixtures eval/pages \
  --models gemini-2.5-flash-lite,gemini-3.1-flash-lite,gemini-3.5-flash-lite
```

3. **Recall is the number that decides it** — a missing article is a story the
   reader never hears. Ship the cheapest model whose recall matches the 2.5
   baseline, not the cheapest overall.
4. Set the vars, including `GEMINI_TTS_MODEL`. When you change that one, add the
   new rate to `GEMINI_TTS_USD_PER_MTOK` in `_shared/usage.ts` or the ledger
   will silently price narration at zero.

---

## 7 · Prove it works, then decide the flags from data

Upload one edition through the app, then:

```sql
-- The ₹50 meter.
select * from edition_cost order by started_at desc limit 5;

-- Free-pool consumption, per voice, this month.
select * from tts_pool_usage;

-- Did any page fail or get retried?
select page, status, attempts, step, last_error
from ingest_pages where job_id = '<job-uuid>' order by page;
```

Only now are the two deferred flags decidable:

- **`RASTER_PAGES=true`** — process one edition with it off, one with it on,
  compare `input_tokens` in `model_calls`. The plan estimates it halves
  structuring input cost; the ledger will say.
- **`AUDIO_FORMAT=mp3`** — measured at 8× smaller and 27× realtime, so a typical
  article costs 2–5s of CPU. Supabase enforces a per-invocation CPU budget that
  is not measurable from a laptop. Flip it, then watch the function logs for
  CPU-limit errors before trusting it.

---

## 8 · Doing this from Claude Code instead of the CLI

You have the Supabase MCP connected, which covers most of the above without a
terminal:

| Task | MCP tool |
|---|---|
| Apply a migration | `apply_migration` |
| Run the queries in §7 | `execute_sql` |
| Deploy one function | `deploy_edge_function` |
| Read the security linter | `get_advisors` |
| Debug a failing function | `query_logs` |

Two cautions. **`apply_migration` writes directly to the remote project** —
there is no local stack in between, so prefer `supabase db push` against a
branch project for anything you want to rehearse. And **the MCP cannot set
secrets**; `supabase secrets set` or the dashboard is the only route, which is
appropriate for a service-account key.

For a rehearsal that cannot touch production, `create_branch` gives you a
throwaway Supabase project with the schema, and `merge_branch` promotes it.
