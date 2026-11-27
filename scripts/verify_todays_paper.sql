-- Owner-run, read-only verification. Prints metadata/counts, never story text.
-- psql -X -v ON_ERROR_STOP=1 -v paper_date=2026-11-13 -f scripts/verify_todays_paper.sql "$GV_DATABASE_URL"
select d.edition, d.source_date, sec.title as section, count(s.source_id) as stories
from public.paper_days d
join public.paper_stories s using (edition, source_date)
join public.paper_sections sec on sec.id = s.section
where d.source_date = :'paper_date'::date
group by d.edition, d.source_date, sec.title, sec.sort_order
order by d.edition, sec.sort_order;

select edition, source_date, count(*) as stories,
       count(*) filter (where headline_is_graphic) as graphic_headlines,
       count(*) filter (where narration_text = '') as without_narration
from public.paper_stories where source_date = :'paper_date'::date
group by edition, source_date order by edition;

select relname, relrowsecurity
from pg_class join pg_namespace n on n.oid = relnamespace
where n.nspname = 'public' and relname in
  ('paper_editions', 'paper_sections', 'paper_days', 'paper_stories', 'story_publishers')
order by relname;

select has_table_privilege('anon', 'public.paper_stories', 'SELECT') as public_read,
       has_table_privilege('anon', 'public.paper_stories', 'INSERT') as public_insert,
       has_table_privilege('authenticated', 'public.story_publishers', 'INSERT') as self_enrollment,
       has_table_privilege('authenticated', 'public.paper_stories', 'TRUNCATE') as publisher_truncate;
-- Expected: true, false, false, false; every relrowsecurity above must be true.

-- After 20261125000000_paper_story_audio.sql the text and audio tables are owner-only:
select has_table_privilege('anon', 'public.paper_stories', 'SELECT') as anon_reads_text,
       has_table_privilege('anon', 'public.paper_days', 'SELECT') as anon_reads_days,
       has_table_privilege('anon', 'public.paper_story_audio', 'SELECT') as anon_reads_audio;
-- Expected: false, false, false. And: select policyname from pg_policies where tablename in
-- ('paper_days','paper_stories') must not list paper_read.
