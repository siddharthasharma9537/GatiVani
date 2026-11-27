-- Prepared audio for the Paper tab: one row per story, owner-only (no public SELECT).
-- Contract: sohum-contracts docs/PAPER_AUDIO_SHAPE.md (proposed, not approved).
-- Rows hold R2 object KEYS and metadata only, never audio and never a URL.
-- Code only until the owner applies it. Depends on 20261113000000_todays_paper.sql
-- (public.story_publishers, public.paper_editions).
begin;

create table if not exists public.paper_story_audio (
  edition text not null references public.paper_editions(id),
  source_date date not null,
  story_id text not null check (story_id ~ '^[a-z0-9][a-z0-9_-]*$' and length(story_id) <= 80),
  rank integer not null check (rank >= 1),
  page integer not null check (page >= 1),
  headline text not null check (length(headline) > 0),
  object_key text not null check (object_key ~ '^paper/[A-Z][A-Z0-9-]*/[0-9]{2}-[0-9]{2}-[0-9]{4}/[0-9]{3}_[a-z0-9][a-z0-9_-]*\.m4a$'),
  bucket text not null check (bucket ~ '^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$'),
  content_type text not null check (content_type = 'audio/mp4'),
  bytes bigint not null check (bytes >= 1),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  duration_seconds numeric not null check (duration_seconds > 0),
  voice text not null check (length(voice) > 0),
  model text not null check (length(model) > 0),
  characters integer not null check (characters >= 1),
  created_at timestamptz not null,
  primary key (edition, source_date, story_id),
  unique (edition, source_date, rank)
);
create index if not exists paper_story_audio_day on public.paper_story_audio(source_date desc, edition, rank);

alter table public.paper_story_audio enable row level security;
revoke all on public.paper_story_audio from anon, authenticated;
grant select, insert, update, delete on public.paper_story_audio to authenticated;
drop policy if exists paper_audio_owner on public.paper_story_audio;
-- Reads AND writes require membership in story_publishers (the owner). The Worker has its own
-- allowlist (OWNER_USER_IDS); keep the two in step by hand.
create policy paper_audio_owner on public.paper_story_audio for all to authenticated
  using (exists (select 1 from public.story_publishers where user_id = (select auth.uid())))
  with check (exists (select 1 from public.story_publishers where user_id = (select auth.uid())));

-- Eenadu text is copyrighted: remove the PUBLIC read that 20261113000000 gave paper_days and
-- paper_stories. After this, only story_publishers members (the owner) can read them; the
-- paper_publish policy ("for all") already covers owner reads. paper_editions and paper_sections
-- (edition and section labels, no Eenadu text) stay readable so the edition picker still renders.
do $$ declare tbl text; begin
  foreach tbl in array array['paper_days','paper_stories'] loop
    execute format('drop policy if exists paper_read on public.%I', tbl);
    execute format('revoke select on public.%I from anon', tbl);
  end loop;
end $$;

commit;
