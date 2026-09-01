-- Keep the seed fixtures out of the retention sweep.
--
-- A dry run of storage-cleanup reported 288 candidates where 281 was correct:
-- stale_audio_objects matched on age alone, so the seven
-- articles/00000000-0000-0000-0000-0000000000* fixtures were included. Those
-- are demo audio with no source to regenerate from — unlike every other object
-- in the bucket, which is cached TTS that re-synthesizes on next play. Deleting
-- them would have been silent and unrecoverable.
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
    and o.name not like 'articles/00000000-0000-0000-0000-0000000000%'
  order by o.created_at
$$;

revoke execute on function public.stale_audio_objects(integer) from public, anon, authenticated;
grant execute on function public.stale_audio_objects(integer) to service_role;
