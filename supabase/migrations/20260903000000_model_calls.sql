-- Per-call cost ledger for every paid external call GatiVani makes.
--
-- Nothing in the app records what an edition costs. The ₹50-per-edition target
-- in docs/ORCHESTRATION_PLAN.md is therefore unverifiable today: every figure in
-- that document is an estimate read off the code. This table is the meter — one
-- row per Sarvam OCR job, per Gemini call, per TTS synthesis — so the estimates
-- can be replaced by measurements before any optimisation is judged.
--
-- Written only by edge functions holding the service role (which bypasses RLS).
-- No anon/authenticated policy: the app never reads this directly, and per-call
-- spend is operator data, not user data.

create table if not exists public.model_calls (
  id            uuid primary key default gen_random_uuid(),
  fn            text not null,               -- edge function name, e.g. 'documents-synthesize'
  kind          text not null                -- which cost line this belongs to
                  check (kind in ('llm', 'tts', 'ocr')),
  provider      text not null,               -- 'gemini' | 'sarvam' | 'google-tts'
  model         text not null,               -- exact model / voice id billed

  -- what it was for (all nullable: a Live-feed narration has no edition)
  job_id        uuid,
  newspaper_id  uuid,
  article_id    uuid,
  page          integer,

  -- billable units; only the ones a given provider charges for are set
  input_tokens  integer,
  output_tokens integer,
  chars         integer,                     -- TTS characters (Cloud TTS bills these)
  audio_seconds numeric,                     -- TTS audio produced (Gemini bills tokens = 25/s)
  pages         integer,                     -- OCR pages

  -- cost in paise (integer, so sums stay exact); ₹ = inr_paise / 100.0
  inr_paise     integer not null default 0,

  latency_ms    integer,
  ok            boolean not null default true,
  error         text,
  created_at    timestamptz not null default now()
);

create index if not exists model_calls_created_at   on public.model_calls (created_at desc);
create index if not exists model_calls_newspaper_id on public.model_calls (newspaper_id) where newspaper_id is not null;
create index if not exists model_calls_kind_time    on public.model_calls (kind, created_at desc);

alter table public.model_calls enable row level security;
-- deliberately no policies — service role only

comment on table public.model_calls is
  'Cost ledger: one row per paid external call (Gemini, Sarvam OCR, TTS). '
  'inr_paise is computed at call time from the price table in '
  'supabase/functions/_shared/usage.ts, so historical rows keep the price that '
  'was actually in force. See docs/ORCHESTRATION_PLAN.md.';

-- ── What did one edition cost? ───────────────────────────────────────────────
-- The headline number the ₹50 target is measured against.
create or replace view public.edition_cost as
select
  c.newspaper_id,
  n.title,
  n.publication_date,
  min(c.created_at)                                            as started_at,
  max(c.created_at)                                            as finished_at,
  count(*)                                                     as calls,
  count(*) filter (where not c.ok)                             as failed_calls,
  sum(c.inr_paise) filter (where c.kind = 'ocr') / 100.0       as ocr_inr,
  sum(c.inr_paise) filter (where c.kind = 'llm') / 100.0       as llm_inr,
  sum(c.inr_paise) filter (where c.kind = 'tts') / 100.0       as tts_inr,
  sum(c.inr_paise) / 100.0                                     as total_inr,
  sum(c.chars) filter (where c.kind = 'tts')                   as tts_chars,
  round(sum(c.audio_seconds) filter (where c.kind = 'tts') / 60.0, 1) as tts_minutes
from public.model_calls c
left join public.newspapers n on n.id = c.newspaper_id
where c.newspaper_id is not null
group by c.newspaper_id, n.title, n.publication_date;

comment on view public.edition_cost is
  'Rupee cost per processed edition, split by OCR / LLM / TTS. This is the '
  'ledger the under-₹50-per-edition goal is checked against.';

-- ── How much of each monthly free pool is spent? ─────────────────────────────
-- Google Cloud TTS free tiers are per voice type per calendar month (Standard
-- 4M chars, WaveNet 1M, Chirp 3 HD 1M). Narration is only free while usage
-- stays inside them, so this is the number the prewarm allowance and the 80%
-- alert in the plan are driven from.
create or replace view public.tts_pool_usage as
select
  date_trunc('month', created_at)::date as month,
  model                                 as voice,
  sum(chars)                            as chars_used,
  sum(inr_paise) / 100.0                as inr
from public.model_calls
where kind = 'tts' and chars is not null
group by 1, 2;

comment on view public.tts_pool_usage is
  'Characters synthesised per voice per calendar month — compare against each '
  'voice type''s free pool (Standard 4M, WaveNet 1M, Chirp 3 HD 1M).';
