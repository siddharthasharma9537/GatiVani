-- Applied to live 2026-06-11. Per-IP rate limiting for expensive endpoints.
create table if not exists public.request_log (
  id uuid primary key default gen_random_uuid(),
  ip text not null,
  endpoint text not null,
  created_at timestamptz not null default now()
);
create index if not exists request_log_ip_time on public.request_log (ip, endpoint, created_at desc);
alter table public.request_log enable row level security;
-- no policies: only the service role (edge functions) reads/writes
