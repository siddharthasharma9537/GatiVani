-- Per-account Gemini BYOK key, so signing in with the same account on a new
-- device (or after a reinstall) doesn't re-prompt for a key that's already
-- registered. The raw key is never stored in a plain column: it's held in
-- Supabase Vault (pgsodium-encrypted) and only reachable through the
-- SECURITY DEFINER functions below, each of which checks auth.uid() itself,
-- so one account can never read or overwrite another's key via RPC.

-- ── user_settings ────────────────────────────────────────────────────────────
create table if not exists public.user_settings (
  user_id             uuid primary key references auth.users(id) on delete cascade,
  gemini_key_secret_id uuid references vault.secrets(id) on delete set null,
  updated_at          timestamptz not null default current_timestamp
);

alter table public.user_settings enable row level security;

do $$ begin
  create policy user_settings_select_own on public.user_settings
    for select using (auth.uid() = user_id);
  exception when duplicate_object then null; end $$;

do $$ begin
  create policy user_settings_insert_own on public.user_settings
    for insert with check (auth.uid() = user_id);
  exception when duplicate_object then null; end $$;

do $$ begin
  create policy user_settings_update_own on public.user_settings
    for update using (auth.uid() = user_id);
  exception when duplicate_object then null; end $$;

do $$ begin
  create policy user_settings_delete_own on public.user_settings
    for delete using (auth.uid() = user_id);
  exception when duplicate_object then null; end $$;

-- ── RPCs: the only way in or out of vault for this data ─────────────────────
-- All three run as SECURITY DEFINER (so they can reach the vault schema, which
-- authenticated/anon roles can't query directly) but every one of them scopes
-- itself to auth.uid() internally, so a caller can only ever touch their own
-- row/secret regardless of the elevated privilege.

create or replace function public.set_gemini_key(p_key text)
returns void
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_uid       uuid := auth.uid();
  v_secret_id uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select gemini_key_secret_id into v_secret_id
    from public.user_settings where user_id = v_uid;

  if v_secret_id is not null then
    perform vault.update_secret(v_secret_id, p_key);
  else
    v_secret_id := vault.create_secret(p_key, 'gemini_key_' || v_uid::text);
  end if;

  insert into public.user_settings (user_id, gemini_key_secret_id, updated_at)
  values (v_uid, v_secret_id, current_timestamp)
  on conflict (user_id) do update
    set gemini_key_secret_id = excluded.gemini_key_secret_id,
        updated_at = current_timestamp;
end;
$$;

create or replace function public.get_gemini_key()
returns text
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_uid       uuid := auth.uid();
  v_secret_id uuid;
  v_key       text;
begin
  if v_uid is null then
    return null;
  end if;

  select gemini_key_secret_id into v_secret_id
    from public.user_settings where user_id = v_uid;

  if v_secret_id is null then
    return null;
  end if;

  select decrypted_secret into v_key
    from vault.decrypted_secrets where id = v_secret_id;

  return v_key;
end;
$$;

create or replace function public.clear_gemini_key()
returns void
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_uid       uuid := auth.uid();
  v_secret_id uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select gemini_key_secret_id into v_secret_id
    from public.user_settings where user_id = v_uid;

  if v_secret_id is not null then
    delete from vault.secrets where id = v_secret_id;
  end if;

  delete from public.user_settings where user_id = v_uid;
end;
$$;

grant execute on function public.set_gemini_key(text) to authenticated;
grant execute on function public.get_gemini_key()      to authenticated;
grant execute on function public.clear_gemini_key()    to authenticated;
