-- Applied to live 2026-06-12. Recently-played history (trial: public RLS).
create table if not exists public.recent_plays (
  id uuid primary key default gen_random_uuid(),
  article_id uuid,
  title text,
  category text,
  page integer,
  played_at timestamptz not null default now()
);
create index if not exists recent_plays_time on public.recent_plays (played_at desc);
alter table public.recent_plays enable row level security;
create policy recent_plays_insert_public on public.recent_plays for insert with check (true);
create policy recent_plays_select_public on public.recent_plays for select using (true);
