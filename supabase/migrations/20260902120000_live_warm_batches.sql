-- Batched pre-synthesis for the Live feed.
--
-- The Live feed used to be a straight pass-through of feeds-articles: whatever
-- the publisher RSS had at that second, narrated on demand. That put TTS
-- synthesis on the critical path of playback, so the first play of any article
-- paid the full synthesis wait.
--
-- Instead: stage a batch out of band, synthesize every article in it while
-- nobody is watching (paced under the provider's rate limit), and only then
-- swap it in front of readers. Until that swap the previous batch keeps
-- serving, so the feed is never empty and never half-narrated. An article
-- reaches the feed only once its audio is cached, which makes "audio is ready"
-- an invariant of the published feed rather than something playback has to race.
--
-- The second prize is retention. Audio here is regenerable and short-lived, and
-- an unbounded `audio` bucket is what put the whole project into
-- exceed_storage_size_quota once already (docs/R2_AUDIO_MIGRATION.md) — where
-- every edge function 402s, feeds included. Double-buffering makes garbage
-- identifiable instead of guessed at: when a batch is replaced, its audio is
-- provably nobody's current feed, so it can be dropped on a fixed delay rather
-- than swept for by age.

create table if not exists public.live_batches (
  id            uuid primary key default gen_random_uuid(),
  lang          text not null,
  -- staging   → being synthesized, not visible to anyone
  -- published → what the Live feed is currently serving (one per lang)
  -- retired   → superseded; its audio is deletable once retired_at is old enough
  status        text not null default 'staging'
                check (status in ('staging', 'published', 'retired')),
  -- The feeds-articles payload this batch was built from, verbatim. Published
  -- reads filter it down to the articles that actually finished synthesizing,
  -- so a partial batch degrades to a shorter feed, never a stalling one.
  items         jsonb not null,
  created_at    timestamptz not null default now(),
  published_at  timestamptz,
  retired_at    timestamptz
);

create index if not exists live_batches_lang_status_idx
  on public.live_batches (lang, status, created_at desc);

-- One row per (batch, article) of synthesis work, all enqueued when the batch
-- is created.
create table if not exists public.live_batch_items (
  batch_id     uuid not null references public.live_batches(id) on delete cascade,
  article_id   uuid not null,
  status       text not null default 'pending'
               check (status in ('pending', 'done', 'failed')),
  attempts     int  not null default 0,
  audio_url    text,
  error        text,
  updated_at   timestamptz not null default now(),
  primary key (batch_id, article_id)
);

create index if not exists live_batch_items_pending_idx
  on public.live_batch_items (batch_id, status, article_id);

-- Single-row advisory lock. Ticks are driven by an external scheduler, and a
-- manual dispatch can land on top of a scheduled run; two ticks draining the
-- same queue would double-spend the synthesis budget on identical work. Claimed
-- with a conditional UPDATE, which is atomic, so the loser simply does nothing.
create table if not exists public.live_warm_lock (
  id           int primary key default 1 check (id = 1),
  locked_until timestamptz not null default now(),
  holder       text
);
insert into public.live_warm_lock (id, locked_until)
  values (1, now()) on conflict (id) do nothing;

-- Service-role only, like feed_cache: the app never reads these tables
-- directly, it only ever sees what feeds-articles returns. RLS on with no
-- policy means the anon and authenticated keys get nothing.
alter table public.live_batches     enable row level security;
alter table public.live_batch_items enable row level security;
alter table public.live_warm_lock   enable row level security;
