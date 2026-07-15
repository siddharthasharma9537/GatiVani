-- 24h temporary content cache on recent_plays, so a played article (Live or
-- Paper) can still be resumed/reopened for a day after playing it, even
-- once it's scrolled out of the in-memory Live feed pool — Live articles
-- have no other persisted copy anywhere (unlike Paper, which always has a
-- permanent row in public.articles). Refreshed to +24h every time the
-- article is (re)played, not just the first time.
--
-- Enforced purely as a read-time expiry check (content_expires_at < now())
-- — no cron job. Whoever reads an expired row is expected to also null the
-- content columns out then (lazy cleanup), since nothing else does it
-- proactively. Saving the article to a playlist makes it permanent through
-- a completely separate mechanism (a full client-side snapshot in the
-- Playlist itself, see PlaylistsStore/Playlist.toJson) — this cache is only
-- ever a stopgap for the window before that.

alter table public.recent_plays
  add column if not exists content text,
  add column if not exists preview text,
  add column if not exists language text,
  add column if not exists content_expires_at timestamptz;
