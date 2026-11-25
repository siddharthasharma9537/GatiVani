-- Published text is independent of uploads/OCR articles and their audio lifecycle.
-- This migration is code only until the owner applies it. No audio is stored.
begin;

create table if not exists public.story_publishers (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.story_publishers enable row level security;
revoke all on public.story_publishers from anon, authenticated;
grant select on public.story_publishers to authenticated;
drop policy if exists story_publishers_self on public.story_publishers;
create policy story_publishers_self on public.story_publishers for select
  to authenticated using (user_id = (select auth.uid()));
-- Only the database owner manages membership, never the public REST client.

create table if not exists public.paper_editions (
  id text primary key,
  title text not null
);
create table if not exists public.paper_sections (
  id text primary key,
  title text not null,
  sort_order integer not null unique
);
insert into public.paper_editions (id, title) values
  ('TELANGANA', 'Telangana'), ('ANDHRA-PRADESH', 'Andhra Pradesh'),
  ('GREATER-HYDERABAD', 'Greater Hyderabad') on conflict (id) do nothing;
insert into public.paper_sections (id, title, sort_order) values
  ('front', 'Front page', 0), ('editorial', 'Editorial news', 1),
  ('business', 'Business', 2), ('cinema', 'Cinema', 3),
  ('sports', 'Champion (sports)', 4), ('vasundhara', 'Vasundhara', 5),
  ('pratibha', 'Pratibha', 6), ('chaduvu', 'Chaduvu', 7),
  ('regional', 'Regional', 8), ('national', 'National', 9),
  ('back', 'Back page', 10), ('general', 'General news', 11)
on conflict (id) do nothing;

create table if not exists public.paper_days (
  edition text not null references public.paper_editions(id),
  source_date date not null,
  published_at timestamptz not null default now(),
  primary key (edition, source_date)
);
create or replace function public.valid_paper_items(items jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select jsonb_typeof(items) = 'array' and not exists (
    select 1 from jsonb_array_elements(
      case when jsonb_typeof(items) = 'array' then items else '[]'::jsonb end
    ) item where jsonb_typeof(item) is distinct from 'object'
      or coalesce(item->>'role', '') not in
        ('headline','kicker','deck','byline','subheading','body','caption','side')
      or jsonb_typeof(item->'text') is distinct from 'string'
  );
$$;
create table if not exists public.paper_stories (
  edition text not null,
  source_date date not null,
  source_id text not null,
  section text not null references public.paper_sections(id),
  sort_order integer not null,
  headline text not null default '',
  headline_is_graphic boolean not null default false,
  -- Optional already-hosted crop URL. Importer never uploads page images.
  headline_image_url text check (headline_image_url is null or headline_image_url ~ '^https://'),
  byline text not null default '',
  items jsonb not null check (public.valid_paper_items(items)),
  display_text text not null,
  narration_text text not null,
  page_numbers integer[] not null check (cardinality(page_numbers) > 0 and 0 < all(page_numbers)),
  continuation_info jsonb not null default '[]' check (jsonb_typeof(continuation_info) = 'array'),
  word_count integer not null check (word_count >= 0),
  primary key (edition, source_date, source_id),
  foreign key (edition, source_date) references public.paper_days(edition, source_date) on delete cascade
);
create index if not exists paper_stories_browse on public.paper_stories(edition, source_date, section, sort_order);
create index if not exists paper_days_latest on public.paper_days(source_date desc, edition);

-- Public reads; every mutation requires membership, including metadata mutations.
do $$ declare tbl text; begin
  foreach tbl in array array['paper_editions','paper_sections','paper_days','paper_stories'] loop
    execute format('alter table public.%I enable row level security', tbl);
    execute format('revoke all on public.%I from anon, authenticated', tbl);
    execute format('grant select on public.%I to anon, authenticated', tbl);
    execute format('grant insert, update, delete on public.%I to authenticated', tbl);
    execute format('drop policy if exists paper_read on public.%I', tbl);
    execute format('create policy paper_read on public.%I for select to anon, authenticated using (true)', tbl);
    execute format('drop policy if exists paper_publish on public.%I', tbl);
    execute format('create policy paper_publish on public.%I for all to authenticated using (exists (select 1 from public.story_publishers where user_id = (select auth.uid()))) with check (exists (select 1 from public.story_publishers where user_id = (select auth.uid())))', tbl);
  end loop;
end $$;

-- One REST transaction per edition/day: replaces stale rows and upserts retained
-- identities. The advisory lock serializes concurrent publishers of the same day.
-- Invoker security preserves RLS; no service-role token is needed.
create or replace function public.publish_paper_day(
  p_edition text, p_date date, p_stories jsonb
) returns void language plpgsql security invoker set search_path = '' as $$
begin
  if not exists (select 1 from public.story_publishers where user_id = (select auth.uid())) then
    raise exception 'Publisher membership required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_stories) is distinct from 'array' then
    raise exception 'Stories must be an array';
  end if;
  perform pg_advisory_xact_lock(hashtext(p_edition), hashtext(p_date::text));
  insert into public.paper_days(edition, source_date) values (p_edition, p_date)
    on conflict (edition, source_date) do update set published_at = now();
  delete from public.paper_stories where edition = p_edition and source_date = p_date
    and source_id not in (select value->>'source_id' from jsonb_array_elements(p_stories));
  insert into public.paper_stories (
    edition, source_date, source_id, section, sort_order, headline, headline_is_graphic,
    headline_image_url, byline, items, display_text, narration_text, page_numbers, continuation_info, word_count
  ) select p_edition, p_date, x.source_id, x.section, x.sort_order, x.headline, x.headline_is_graphic,
      x.headline_image_url, x.byline, x.items, x.display_text, x.narration_text, x.page_numbers, x.continuation_info, x.word_count
    from jsonb_to_recordset(p_stories) as x(source_id text, section text, sort_order integer,
      headline text, headline_is_graphic boolean, headline_image_url text, byline text, items jsonb,
      display_text text, narration_text text, page_numbers integer[], continuation_info jsonb, word_count integer)
  on conflict (edition, source_date, source_id) do update set
    section = excluded.section, sort_order = excluded.sort_order, headline = excluded.headline,
    headline_is_graphic = excluded.headline_is_graphic, headline_image_url = excluded.headline_image_url,
    byline = excluded.byline, items = excluded.items, display_text = excluded.display_text,
    narration_text = excluded.narration_text, page_numbers = excluded.page_numbers,
    continuation_info = excluded.continuation_info, word_count = excluded.word_count;
end $$;
revoke all on function public.publish_paper_day(text, date, jsonb) from public, anon;
grant execute on function public.publish_paper_day(text, date, jsonb) to authenticated;

-- Delete ONE edition/day (cascades to stories), using the owner's SQL tooling:
-- delete from public.paper_days where edition = 'TELANGANA' and source_date = date '2026-11-13';
commit;
