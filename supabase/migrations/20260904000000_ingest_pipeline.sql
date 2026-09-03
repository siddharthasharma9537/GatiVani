-- Durable, parallel edition ingestion.
--
-- ── What this replaces ──────────────────────────────────────────────────────
-- `processing_jobs` + the self-fetch chain in documents-process-edition: page 1
-- finishes and fires page 2, which fires page 3, and so on. Two consequences:
--
--   * A 20-page edition takes ~14 minutes because nothing overlaps.
--   * If any single invocation dies — cold start, wall-clock limit, a Sarvam
--     poll that never returns — the chain simply stops. The job sits at
--     "processing" forever, no error is recorded, and the user watches a
--     progress bar that will never move again.
--
-- ── Why a table and not pgmq ────────────────────────────────────────────────
-- The plan called for pgmq. Building it, a table-as-queue turned out to be the
-- better fit at this scale, and the difference is worth stating rather than
-- silently deviating:
--
--   * Per-page state has to exist anyway — attempts, ocr_hash, last_error, the
--     step reached. With pgmq that state lives in two places (the message and
--     this table) and they can disagree.
--   * `FOR UPDATE SKIP LOCKED` is exactly the primitive a work queue needs and
--     Postgres has had it since 9.5. pgmq is a thin layer over it.
--   * Volume is a handful of editions a day, not thousands of messages a
--     second — the regime where pgmq's machinery earns its keep.
--   * A queue you can `select * from` is far easier to operate: "which page is
--     stuck and why" is one query, not a message peek.
--
-- Revisit pgmq if ingestion ever becomes high-throughput or multi-consumer.

-- ── Jobs ────────────────────────────────────────────────────────────────────
create table if not exists public.ingest_jobs (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references auth.users(id) on delete set null,
  filename      text not null,
  source_path   text,
  status        text not null default 'queued'
                  check (status in ('queued','splitting','pages','stitching','ready','failed')),
  total_pages   integer not null default 0,
  newspaper_id  uuid references public.newspapers(id),
  article_count integer not null default 0,
  error         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ── Pages: the unit of work, and the queue ──────────────────────────────────
create table if not exists public.ingest_pages (
  job_id        uuid not null references public.ingest_jobs(id) on delete cascade,
  page          integer not null,
  status        text not null default 'queued'
                  check (status in ('queued','processing','done','failed','skipped')),
  -- Last step that completed, so a retry can report where it got to.
  step          text,
  attempts      integer not null default 0,
  -- sha256 of this page's OCR text. The dedupe key: the same physical page,
  -- uploaded twice, is processed once (see find_duplicate_page below).
  ocr_hash      text,
  article_count integer not null default 0,
  last_error    text,
  -- When a worker claimed this row. A claim older than the sweep's timeout is
  -- assumed dead and returned to the queue.
  claimed_at    timestamptz,
  updated_at    timestamptz not null default now(),
  primary key (job_id, page)
);

create index if not exists ingest_pages_claimable
  on public.ingest_pages (status, claimed_at);
create index if not exists ingest_pages_ocr_hash
  on public.ingest_pages (ocr_hash) where ocr_hash is not null;
create index if not exists ingest_jobs_user
  on public.ingest_jobs (user_id, created_at desc);

-- ── Progress, for the client's poll ─────────────────────────────────────────
create or replace view public.ingest_job_progress as
select
  j.id,
  j.user_id,
  j.status,
  j.filename,
  j.total_pages,
  j.newspaper_id,
  j.article_count,
  j.error,
  j.created_at,
  j.updated_at,
  count(p.*) filter (where p.status in ('done','skipped','failed')) as done_pages,
  count(p.*) filter (where p.status = 'failed')                     as failed_pages,
  count(p.*) filter (where p.status = 'skipped')                    as deduped_pages
from public.ingest_jobs j
left join public.ingest_pages p on p.job_id = j.id
group by j.id;

-- Views run as their OWNER by default, which would bypass the row-level
-- security below entirely and expose every user's jobs to every caller —
-- exactly the hole that made processing_jobs world-readable. security_invoker
-- makes the view respect the querying user's policies instead.
alter view public.ingest_job_progress set (security_invoker = on);

comment on view public.ingest_job_progress is
  'What the app polls while an edition processes. done_pages counts every '
  'terminal page, so progress never stalls on a page that failed. '
  'security_invoker is ON: this view enforces the caller''s RLS, it does not '
  'bypass it.';

-- ── RLS ─────────────────────────────────────────────────────────────────────
-- Scoped to the owner, which closes the TODO left on processing_jobs (that
-- table was world-readable: anyone could enumerate every upload in the system).
-- Anonymous uploads have user_id null and are readable by no one; the client
-- holds the job id it was handed and polls through the edge function instead.
alter table public.ingest_jobs  enable row level security;
alter table public.ingest_pages enable row level security;

do $$ begin
  create policy ingest_jobs_select_own on public.ingest_jobs
    for select using (auth.uid() is not null and auth.uid() = user_id);
  exception when duplicate_object then null; end $$;

do $$ begin
  create policy ingest_pages_select_own on public.ingest_pages
    for select using (
      exists (
        select 1 from public.ingest_jobs j
        where j.id = ingest_pages.job_id
          and auth.uid() is not null
          and j.user_id = auth.uid()
      )
    );
  exception when duplicate_object then null; end $$;

-- Writes are service-role only (edge functions bypass RLS); no write policies.

-- ── Claiming work ───────────────────────────────────────────────────────────
-- SKIP LOCKED is what makes parallel workers safe: two dispatchers running at
-- once take disjoint sets of pages instead of blocking on each other or, worse,
-- both processing the same page and inserting its articles twice.
create or replace function public.claim_ingest_pages(p_job_id uuid, p_limit integer)
returns table (job_id uuid, page integer, attempts integer)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with claimed as (
    select p.job_id, p.page
    from public.ingest_pages p
    where p.job_id = p_job_id
      and p.status = 'queued'
    order by p.page
    for update skip locked
    limit p_limit
  )
  update public.ingest_pages t
     set status = 'processing',
         claimed_at = now(),
         attempts = t.attempts + 1,
         updated_at = now()
    from claimed c
   where t.job_id = c.job_id and t.page = c.page
  returning t.job_id, t.page, t.attempts;
end;
$$;

revoke execute on function public.claim_ingest_pages(uuid, integer) from public, anon, authenticated;
grant  execute on function public.claim_ingest_pages(uuid, integer) to service_role;

-- ── Recovering dead work ────────────────────────────────────────────────────
-- The durability guarantee. A page whose worker died stays 'processing' with a
-- stale claimed_at; this returns it to the queue, or fails it for good once it
-- has burned its attempts. Without this, one killed invocation strands a job —
-- which is exactly the failure the old chain had.
create or replace function public.requeue_stale_ingest_pages(
  p_timeout interval default '10 minutes',
  p_max_attempts integer default 3
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  with stale as (
    select p.job_id, p.page, p.attempts
    from public.ingest_pages p
    where p.status = 'processing'
      and p.claimed_at < now() - p_timeout
    for update skip locked
  )
  update public.ingest_pages t
     set status = case when s.attempts >= p_max_attempts then 'failed' else 'queued' end,
         last_error = case
           when s.attempts >= p_max_attempts
             then coalesce(t.last_error, 'worker died; out of attempts')
           else coalesce(t.last_error, 'worker died; requeued')
         end,
         claimed_at = null,
         updated_at = now()
    from stale s
   where t.job_id = s.job_id and t.page = s.page;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.requeue_stale_ingest_pages(interval, integer) from public, anon, authenticated;
grant  execute on function public.requeue_stale_ingest_pages(interval, integer) to service_role;

-- ── Page-level dedupe ───────────────────────────────────────────────────────
-- The same physical newspaper page, uploaded by a second user, has identical
-- OCR text. Processing it again costs another Sarvam page plus two or three
-- Gemini calls for an answer already sitting in the database. This finds an
-- earlier page whose articles can simply be copied.
--
-- Deliberately requires the source to belong to a DIFFERENT newspaper row: a
-- page must never dedupe against itself or against another page of the same
-- edition (two blank-ish pages in one paper can hash alike).
create or replace function public.find_duplicate_page(
  p_hash text,
  p_newspaper_id uuid
)
returns table (job_id uuid, page integer, newspaper_id uuid, article_count integer)
language sql
security definer
set search_path = public
as $$
  select p.job_id, p.page, j.newspaper_id, p.article_count
  from public.ingest_pages p
  join public.ingest_jobs j on j.id = p.job_id
  where p.ocr_hash = p_hash
    and p.status = 'done'
    and p.article_count > 0
    and j.newspaper_id is not null
    and j.newspaper_id is distinct from p_newspaper_id
  order by p.updated_at
  limit 1
$$;

revoke execute on function public.find_duplicate_page(text, uuid) from public, anon, authenticated;
grant  execute on function public.find_duplicate_page(text, uuid) to service_role;

-- ── The recovery sweep ──────────────────────────────────────────────────────
-- Normal flow does not depend on cron: each page worker claims the next page
-- when it finishes, so the pipeline sustains itself. Cron exists only to
-- rescue work whose worker died, which is why a one-minute cadence is ample.
--
-- pg_cron may need enabling from the dashboard (Database → Extensions) on some
-- projects. Guarded so this migration still applies where it cannot be created;
-- without it the pipeline still runs, it just cannot self-heal, so check for
-- the warning after applying.
do $$
begin
  create extension if not exists pg_cron;
exception when others then
  raise warning 'pg_cron unavailable (%): enable it from the dashboard, then run the cron.schedule below by hand', sqlerrm;
end $$;

do $$
begin
  perform cron.schedule(
    'requeue-stale-ingest-pages',
    '* * * * *',
    $cron$ select public.requeue_stale_ingest_pages(); $cron$
  );
exception when others then
  raise warning 'could not schedule the ingest sweep (%): schedule it manually once pg_cron is enabled', sqlerrm;
end $$;
