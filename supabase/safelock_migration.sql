-- Finora — SafeLock schema migration
--
-- The real database already has a `spending_locks` table (one row per
-- user), used by lib/services/spending_lock_service.dart:
--
-- spending_locks (existing, confirmed in app code — do not recreate)
--   user_id                  uuid references auth.users(id)
--   budget_limit             numeric
--   warning_count            int
--   lock_status              boolean
--   emergency_count          int
--   last_emergency_used_at   timestamptz
--   strict_mode              boolean
--
-- This migration only ADDS what SafeLock's redesigned page needs that
-- doesn't exist yet: an on/off switch, a timestamp for the last warning,
-- and a small event log so "Recent Safety Events" shows real history
-- instead of nothing. Both new spending_locks columns are safe additive
-- changes (nullable / defaulted) — no existing row or query breaks.
--
-- Run this once against your Supabase project (SQL editor or migration
-- tooling). Nothing in the Flutter app runs DDL automatically.

-- 1. New columns on the existing table ---------------------------------
alter table public.spending_locks
  add column if not exists enabled boolean not null default true;

alter table public.spending_locks
  add column if not exists last_warning_at timestamptz;

-- 2. New table for real warning history ---------------------------------
create table if not exists public.spending_lock_events (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null references auth.users(id) on delete cascade,
  reason                 text not null,
  warning_count_at_time  int not null default 0,
  created_at             timestamptz not null default now()
);

create index if not exists spending_lock_events_user_id_created_at_idx
  on public.spending_lock_events (user_id, created_at desc);

-- 3. RLS — mirrors the existing spending_locks policy pattern: a user can
-- only ever read/write their own row/rows. Never disables RLS on either
-- table.
alter table public.spending_lock_events enable row level security;

drop policy if exists "Users can view their own SafeLock events" on public.spending_lock_events;
create policy "Users can view their own SafeLock events"
  on public.spending_lock_events for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert their own SafeLock events" on public.spending_lock_events;
create policy "Users can insert their own SafeLock events"
  on public.spending_lock_events for insert
  with check (auth.uid() = user_id);

-- (No update/delete policy — events are an append-only log. If you ever
-- need users to clear their own history, add a delete policy scoped the
-- same way: using (auth.uid() = user_id).)
