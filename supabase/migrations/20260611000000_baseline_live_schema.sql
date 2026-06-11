-- Baseline snapshot of the LIVE gativani Supabase project (jjoxowdvzmlchtfarpbs)
-- Captured 2026-06-11 from production via information_schema / pg_policies.
-- Live migration history at capture time:
--   1779597506      fix_rls_policies
--   20260605124722  create_storage_buckets
--   20260605133030  enable_rls_on_newspapers
-- This file documents current state so the schema is version-controlled.
-- It is idempotent (IF NOT EXISTS) and safe to run against the live project.

create extension if not exists "uuid-ossp";

-- ── newspapers ──────────────────────────────────────────────────────────────
create table if not exists public.newspapers (
  id               uuid primary key default uuid_generate_v4(),
  title            text not null,
  publication_date date not null,
  issue_number     integer,
  language         text not null default 'en',
  storage_url      text,
  created_at       timestamptz default current_timestamp,
  updated_at       timestamptz default current_timestamp
);

-- ── articles ────────────────────────────────────────────────────────────────
create table if not exists public.articles (
  id                uuid primary key default uuid_generate_v4(),
  newspaper_id      uuid not null references public.newspapers(id),
  title             text not null,
  content_preview   text,
  full_content      text,
  section           text,
  page_number       integer,
  position_json     jsonb default '{}'::jsonb,
  image_url         text,
  audio_url         text,
  quality_score     numeric default 0,
  processing_status text default 'pending',
  created_at        timestamptz default current_timestamp,
  updated_at        timestamptz default current_timestamp
);

-- ── extracted_texts ─────────────────────────────────────────────────────────
create table if not exists public.extracted_texts (
  id           uuid primary key default gen_random_uuid(),
  filename     text not null,
  mime_type    text,
  file_size    integer,
  text         text not null,
  language     text default 'te',
  source       text default 'ocr',
  confidence   double precision default 0.8,
  extracted_at timestamptz default current_timestamp,
  created_at   timestamptz default current_timestamp
);
comment on table public.extracted_texts is
  'Stores raw text extracted from documents via OCR. Each extraction preserves the original text to avoid re-processing.';

-- ── user_articles ───────────────────────────────────────────────────────────
create table if not exists public.user_articles (
  id         uuid primary key default uuid_generate_v4(),
  user_id    uuid not null references auth.users(id),
  article_id uuid not null references public.articles(id),
  read_at    timestamptz,
  favorite   boolean default false,
  notes      text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.newspapers      enable row level security;
alter table public.articles        enable row level security;
alter table public.extracted_texts enable row level security;
alter table public.user_articles   enable row level security;

do $$ begin
  -- public read for content tables (anon app reads)
  create policy newspapers_select_public on public.newspapers
    for select using (true);
  exception when duplicate_object then null; end $$;
do $$ begin
  create policy articles_select_public on public.articles
    for select using (true);
  exception when duplicate_object then null; end $$;

do $$ begin
  create policy extracted_texts_select_public on public.extracted_texts
    for select using (true);
  exception when duplicate_object then null; end $$;
do $$ begin
  -- NOTE(audit 2026-06-11): live policy allows public INSERT (with_check=true).
  -- Edge functions use the service role (bypasses RLS), so this is wider than
  -- needed — candidate for tightening after confirming no anon writers.
  create policy extracted_texts_insert_public on public.extracted_texts
    for insert with check (true);
  exception when duplicate_object then null; end $$;
do $$ begin
  create policy extracted_texts_update_authenticated on public.extracted_texts
    for update with check (auth.role() = 'authenticated');
  exception when duplicate_object then null; end $$;
do $$ begin
  create policy extracted_texts_delete_authenticated on public.extracted_texts
    for delete using (auth.role() = 'authenticated');
  exception when duplicate_object then null; end $$;

do $$ begin
  create policy user_articles_select_own on public.user_articles
    for select using (auth.uid() = user_id);
  exception when duplicate_object then null; end $$;
do $$ begin
  create policy user_articles_insert_own on public.user_articles
    for insert with check (auth.uid() = user_id);
  exception when duplicate_object then null; end $$;
do $$ begin
  create policy user_articles_update_own on public.user_articles
    for update using (auth.uid() = user_id);
  exception when duplicate_object then null; end $$;
do $$ begin
  create policy user_articles_delete_own on public.user_articles
    for delete using (auth.uid() = user_id);
  exception when duplicate_object then null; end $$;

-- ── storage buckets ─────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('uploads', 'uploads', false)
on conflict (id) do nothing;
insert into storage.buckets (id, name, public)
values ('audio', 'audio', true)
on conflict (id) do nothing;
