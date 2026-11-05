-- Allow signed-in users to create files only under their own edition prefix.
-- The application must send the user's session JWT with the upload.
create policy "gativani_insert_own_editions"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'uploads'
  and (storage.foldername(name))[1] = 'editions'
  and (storage.foldername(name))[2] = (select auth.uid())::text
);
