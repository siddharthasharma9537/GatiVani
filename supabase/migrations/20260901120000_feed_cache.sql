-- Last-known-good cache for the upstream RSS feeds.
--
-- Google News answers 503 to roughly 40% of requests from the edge function's
-- IP range (datacenter throttling — the same request from a residential IP
-- returns 200 in 0.25s). feeds-news turned each 503 into a 502, so "Latest
-- stories" rendered empty on a bad roll of the dice, after a ~10s hang.
--
-- The Cache-Control: max-age=300 the function already sends does not help:
-- the app sends an Authorization header, and authenticated responses are not
-- shared-cached, so every load hit Google directly.
--
-- With this table a fetch failure is invisible — the previous payload is served
-- instead, and stale headlines are entirely acceptable for a news feed. It also
-- drops upstream request volume by ~95%, which reduces the throttling itself.
create table if not exists public.feed_cache (
  source      text not null,           -- 'news' | 'explains' | ... (per function)
  cache_key   text not null,           -- e.g. 'te:top' — whatever identifies a variant
  payload     jsonb not null,          -- the exact JSON body last served
  fetched_at  timestamptz not null default now(),
  primary key (source, cache_key)
);

alter table public.feed_cache enable row level security;

-- Written and read only by edge functions using the service role, which
-- bypasses RLS. No anon/authenticated policy: the app never touches this table
-- directly, it only ever sees the function's response.
