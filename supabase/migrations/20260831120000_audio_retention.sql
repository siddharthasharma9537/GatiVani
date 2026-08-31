-- Retention support for the `audio` bucket.
--
-- Synthesized TTS is regenerable cache, but nothing ever removed it: the
-- bucket grew ~600 MB/month and eventually tripped the project's storage
-- quota, which restricts the whole project (every edge function starts
-- answering 402, including CORS preflights). The storage-cleanup edge
-- function calls this to find what to drop.
--
-- Security definer because storage.objects is not reachable from PostgREST;
-- execute is granted to service_role only, matching the cleanup function's key.
create or replace function public.stale_audio_objects(retention_days integer)
returns table (name text)
language sql
security definer
set search_path = storage, public
as $$
  select o.name
  from storage.objects o
  where o.bucket_id = 'audio'
    and o.created_at < now() - make_interval(days => retention_days)
  order by o.created_at
$$;

revoke execute on function public.stale_audio_objects(integer) from public, anon, authenticated;
grant execute on function public.stale_audio_objects(integer) to service_role;
