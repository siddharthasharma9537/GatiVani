-- extracted_texts_insert_public (from the baseline migration) granted INSERT
-- to `public` with no check at all — the migration's own leftover comment
-- flags this as a known finding from a past audit that was never acted on.
-- Anyone could write directly into this table via the REST API.
--
-- The only real writer is documents-process, which uses the service-role key
-- and so bypasses RLS regardless — dropping the public policy costs it
-- nothing. extracted_texts is a write-only OCR audit log the client never
-- reads, so this closes an unnecessary public write hole rather than fixing
-- a content-facing exposure.

drop policy if exists extracted_texts_insert_public on public.extracted_texts;
