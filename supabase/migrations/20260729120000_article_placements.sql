-- Where a headline appeared, separately from where its body is stored.
--
-- articles.page_number is a single integer: one article, one page. But a story
-- is routinely printed in more than one place — a front-page teaser box
-- pointing at the full piece inside, or a lead whose body starts on page 1 and
-- resumes on page 8. With nowhere to record a second appearance, the pipeline
-- had to delete or absorb it, so the front page lost its teasers entirely and
-- a continued story vanished from the page it continued onto.
--
-- A placement records one appearance: which page, and the headline AS PRINTED
-- on that page (a teaser's headline is often not the full article's). Body text
-- still lives exactly once, on articles — nothing here duplicates content.

create table if not exists public.article_placements (
  id           uuid primary key default gen_random_uuid(),
  article_id   uuid not null references public.articles(id)   on delete cascade,
  newspaper_id uuid not null references public.newspapers(id) on delete cascade,
  page_number  int  not null,
  headline     text not null,
  -- primary      = the page the body actually lives on
  -- teaser       = a promo box elsewhere pointing at that body
  -- continuation = the page the story resumes on after a page break
  kind         text not null check (kind in ('primary', 'teaser', 'continuation')),
  created_at   timestamptz not null default now()
);

create index if not exists article_placements_newspaper_page_idx
  on public.article_placements (newspaper_id, page_number);
create index if not exists article_placements_article_idx
  on public.article_placements (article_id);
-- An article appears at most once per page in a given role; the pipeline
-- rebuilds placements per edition, so this also makes re-runs idempotent.
create unique index if not exists article_placements_unique_idx
  on public.article_placements (article_id, page_number, kind);

alter table public.article_placements enable row level security;

-- Same posture as articles/newspapers: world-readable, writes only via the
-- service role (which bypasses RLS) from the extraction pipeline.
drop policy if exists article_placements_select_public on public.article_placements;
create policy article_placements_select_public
  on public.article_placements for select using (true);

-- What a page listing should show. One row per printed appearance, resolving to
-- the single stored article. security_invoker so the reader's own RLS on
-- articles still applies rather than the view owner's.
drop view if exists public.edition_page_items;
create view public.edition_page_items
  with (security_invoker = true) as
select
  p.newspaper_id,
  p.page_number,
  p.headline,
  p.kind,
  p.article_id,
  a.page_number as article_page_number,
  a.section,
  a.content_preview,
  a.audio_url,
  a.summary_audio_url,
  a.created_at
from public.article_placements p
join public.articles a on a.id = p.article_id
where a.processing_status = 'ready';

grant select on public.edition_page_items to anon, authenticated;
