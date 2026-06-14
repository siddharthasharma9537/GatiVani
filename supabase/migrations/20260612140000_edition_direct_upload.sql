-- Applied live 2026-06-12. Direct-to-storage edition upload + source cleanup.
alter table public.processing_jobs add column if not exists source_path text;

drop policy if exists uploads_insert_editions on storage.objects;
create policy uploads_insert_editions on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'uploads' and (name like 'editions/%'));
