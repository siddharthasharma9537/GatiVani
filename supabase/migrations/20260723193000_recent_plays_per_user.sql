-- recent_plays had no user_id column at all — RLS granted SELECT/INSERT to
-- `public` with no ownership check, and the only uniqueness was a single
-- global index on article_id, so every user shared ONE row per article:
-- whoever played it last overwrote everyone else's position, and its
-- content/preview snapshot (up to 24h of full article text) was world
-- readable. Not "your history is visible to others" so much as "there was
-- never a your" — the table was never actually scoped per user.
--
-- Fix: add user_id, re-key uniqueness to (user_id, article_id) so each user
-- gets their own row per article, and restrict RLS to the owning row.
-- Existing rows get user_id = null (unattributable — there's no way to
-- retroactively know whose play produced a shared row) and simply become
-- invisible under the new policy; that's fine, this table is an explicitly
-- ephemeral ~24h cache, not permanent data.

alter table recent_plays add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table recent_plays alter column user_id set default auth.uid();

drop index if exists recent_plays_article_id_uidx;
create unique index if not exists recent_plays_user_article_uidx on recent_plays (user_id, article_id);

drop policy if exists recent_plays_select_public on recent_plays;
drop policy if exists recent_plays_insert_public on recent_plays;

create policy recent_plays_select_own on recent_plays
  for select
  using (auth.uid() = user_id);

create policy recent_plays_insert_own on recent_plays
  for insert
  with check (auth.uid() = user_id);

create policy recent_plays_update_own on recent_plays
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
