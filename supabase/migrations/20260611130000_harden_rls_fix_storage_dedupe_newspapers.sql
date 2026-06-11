-- Applied to live 2026-06-11 (audit follow-up). See AUDIT.md open issues 1,2,3 + dup fix.

update storage.buckets set public = true where id = 'uploads';

drop policy if exists extracted_texts_insert_public on public.extracted_texts;
drop policy if exists extracted_texts_update_authenticated on public.extracted_texts;
create policy extracted_texts_update_authenticated on public.extracted_texts
  for update using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

alter function public.update_timestamp() set search_path = '';

with dups as (
  select id,
         first_value(id) over (partition by title, publication_date order by created_at) as keep_id
  from public.newspapers
)
update public.articles a set newspaper_id = d.keep_id
from dups d where a.newspaper_id = d.id and d.id <> d.keep_id;

with dups as (
  select id,
         first_value(id) over (partition by title, publication_date order by created_at) as keep_id
  from public.newspapers
)
delete from public.newspapers n using dups d where n.id = d.id and d.id <> d.keep_id;
