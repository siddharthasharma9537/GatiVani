-- Per-chunk TTS audio cache, so the client can play the first chunk of an
-- article instantly instead of waiting for the whole article to synthesize.
-- Chunking is deterministic (same text + GEMINI_CHUNK_LIMIT always splits the
-- same way), so a chunk index is addressable directly without any job/session
-- state — the client just asks for "chunk N of article X" and this table
-- caches the result the same way articles.audio_url already caches the full
-- concatenated file. Public read/insert like the other content tables
-- (articles/newspapers) — this is shared synthesized audio, not per-user data.

create table if not exists public.article_chunks (
  article_id       uuid not null references public.articles(id) on delete cascade,
  target           text not null default 'audio_url'
                     check (target in ('audio_url', 'summary_audio_url')),
  chunk_index      integer not null,
  audio_url        text not null,
  duration_seconds numeric,
  created_at       timestamptz not null default current_timestamp,
  primary key (article_id, target, chunk_index)
);

alter table public.article_chunks enable row level security;

do $$ begin
  create policy article_chunks_select_public on public.article_chunks
    for select using (true);
  exception when duplicate_object then null; end $$;

-- Written only by the documents-synthesize edge function (service role),
-- which bypasses RLS — no anon/authenticated insert policy needed.
