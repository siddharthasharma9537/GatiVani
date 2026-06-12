-- Applied to live 2026-06-11. Async multi-page edition processing job tracking.
create table if not exists public.processing_jobs (
  id uuid primary key default gen_random_uuid(),
  filename text not null,
  status text not null default 'pending',   -- pending | processing | completed | failed
  total_pages integer not null default 0,
  done_pages integer not null default 0,
  failed_pages jsonb not null default '[]'::jsonb,
  newspaper_id uuid references public.newspapers(id),
  article_count integer not null default 0,
  error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.processing_jobs enable row level security;
-- trial-phase: clients poll job progress directly; writes are service-role only.
-- TODO before public launch: scope to user_id (personal-utility data isolation).
create policy processing_jobs_select_public on public.processing_jobs
  for select using (true);
