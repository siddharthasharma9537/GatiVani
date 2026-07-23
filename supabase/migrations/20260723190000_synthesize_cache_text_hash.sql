-- documents-synthesize's audio caches (article_chunks, and articles.audio_url /
-- summary_audio_url) were keyed purely on the caller-supplied articleId, with
-- no check that the caller-supplied text actually matched that article. Any
-- caller with a Gemini key (BYOK, free, no gate) could POST a real article's
-- id alongside arbitrary text and permanently overwrite the shared public
-- cache — a content-poisoning vector affecting every future listener of that
-- article.
--
-- Fix: record a hash of the text that produced each cached entry, and have
-- the edge function require it to match on read. A mismatch is treated as a
-- cache miss (re-synthesize from the caller's own text), so a poisoned entry
-- self-corrects the next time a listener with the real text requests it,
-- instead of the poisoning being silent and permanent. This doesn't require
-- an unrelated migration to full per-request auth to close the exploit.

alter table article_chunks add column if not exists text_hash text;

alter table articles add column if not exists audio_text_hash text;
alter table articles add column if not exists summary_audio_text_hash text;
