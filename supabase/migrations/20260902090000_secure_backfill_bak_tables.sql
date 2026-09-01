-- Close public API access to two leftover backfill backup tables.
--
-- Supabase's security advisor flagged both as CRITICAL: they sat in the public
-- schema with RLS off, so the anon key that ships in the web app could read them
-- over the Data API. Verified before the fix — both returned HTTP 200 with rows
-- (article ids, titles, quality scores, position_json with page numbers and
-- Telugu subheadings).
--
-- Nothing in the app, the edge functions, or the migrations references either
-- table; they are orphaned artifacts of past backfills. RLS on with no policies
-- denies anon and authenticated outright while service_role (which bypasses RLS)
-- keeps access. The rows are untouched — dropping them is a separate decision.
alter table public.articles_review_backfill_bak enable row level security;
alter table public.articles_title_backfill_bak  enable row level security;
