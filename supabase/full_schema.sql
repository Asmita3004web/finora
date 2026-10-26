-- Finora — FULL DATABASE SCHEMA
--
-- Run this ONCE in your Supabase project's SQL Editor if you're starting
-- from a brand-new/empty project (the "Could not find the table ... in
-- the schema cache" / PGRST205 errors mean exactly this: the tables the
-- app expects simply don't exist yet in this project).
--
-- This recreates every table the Flutter app's models actually read from
-- or write to — reconstructed directly from lib/models/*.dart and the
-- *_service.dart files, so column names match exactly what the app sends.
-- Safe to re-run: every statement uses IF NOT EXISTS.
--
-- Does NOT include spending_locks.enabled / last_warning_at or
-- spending_lock_events — those are in supabase/safelock_migration.sql,
-- which you should run right after this file.

-- ─────────────────────────────────────────────────────────────────────────
-- 1. profiles — basic account info (lib/models/profile.dart)
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  full_name      text not null default '',
  email          text not null default '',
  phone_number   text,
  profile_image  text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "Users can view their own profile" on public.profiles;
create policy "Users can view their own profile"
  on public.profiles for select using (auth.uid() = id);
drop policy if exists "Users can insert their own profile" on public.profiles;
create policy "Users can insert their own profile"
  on public.profiles for insert with check (auth.uid() = id);
drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
  on public.profiles for update using (auth.uid() = id);

-- ─────────────────────────────────────────────────────────────────────────
-- 2. onboarding — wizard answers (lib/models/onboarding_record.dart,
--    lib/models/onboarding_data.dart)
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists public.onboarding (
  id                           uuid primary key default gen_random_uuid(),
  user_id                      uuid not null references auth.users(id) on delete cascade,
  profession                   text,
  income_type                  text,
  monthly_income               numeric not null default 0,
  fixed_expenses               jsonb not null default '{}'::jsonb,
  spending_habit               text,
  financial_goal               text,
  saving_percentage            numeric,
  budget_discipline            text,
  expense_tracking_frequency   text,
  ai_budget_assistant          boolean not null default true,
  persona                      text,
  onboarding_completed         boolean not null default false,
  created_at                   timestamptz not null default now(),
  updated_at                   timestamptz not null default now()
);

create unique index if not exists onboarding_user_id_key on public.onboarding (user_id);

alter table public.onboarding enable row level security;

drop policy if exists "Users can view their own onboarding" on public.onboarding;
create policy "Users can view their own onboarding"
  on public.onboarding for select using (auth.uid() = user_id);
drop policy if exists "Users can insert their own onboarding" on public.onboarding;
create policy "Users can insert their own onboarding"
  on public.onboarding for insert with check (auth.uid() = user_id);
drop policy if exists "Users can update their own onboarding" on public.onboarding;
create policy "Users can update their own onboarding"
  on public.onboarding for update using (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────
-- 3. transactions — every expense (and, if you add income screens later,
--    income) row (lib/models/expense.dart)
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists public.transactions (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users(id) on delete cascade,
  transaction_date   date not null default current_date,
  transaction_type   text not null default 'Expense', -- 'Expense' | 'Income'
  category           text not null default 'Other',
  amount             numeric not null,
  payment_method     text,
  is_fixed_expense   boolean not null default false,
  merchant           text,
  description        text,
  created_at         timestamptz not null default now()
);

create index if not exists transactions_user_id_date_idx
  on public.transactions (user_id, transaction_date desc);

alter table public.transactions enable row level security;

drop policy if exists "Users can view their own transactions" on public.transactions;
create policy "Users can view their own transactions"
  on public.transactions for select using (auth.uid() = user_id);
drop policy if exists "Users can insert their own transactions" on public.transactions;
create policy "Users can insert their own transactions"
  on public.transactions for insert with check (auth.uid() = user_id);
drop policy if exists "Users can update their own transactions" on public.transactions;
create policy "Users can update their own transactions"
  on public.transactions for update using (auth.uid() = user_id);
drop policy if exists "Users can delete their own transactions" on public.transactions;
create policy "Users can delete their own transactions"
  on public.transactions for delete using (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────
-- 4. spending_locks — SafeLock state (lib/models/spending_lock.dart)
--    (base columns only — run supabase/safelock_migration.sql right after
--    this file for `enabled` / `last_warning_at` / spending_lock_events)
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists public.spending_locks (
  user_id                  uuid primary key references auth.users(id) on delete cascade,
  budget_limit             numeric not null default 0,
  warning_count            int not null default 0,
  lock_status              boolean not null default false,
  emergency_count          int not null default 0,
  last_emergency_used_at   timestamptz,
  strict_mode              boolean not null default false,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

alter table public.spending_locks enable row level security;

drop policy if exists "Users can view their own SafeLock state" on public.spending_locks;
create policy "Users can view their own SafeLock state"
  on public.spending_locks for select using (auth.uid() = user_id);
drop policy if exists "Users can insert their own SafeLock state" on public.spending_locks;
create policy "Users can insert their own SafeLock state"
  on public.spending_locks for insert with check (auth.uid() = user_id);
drop policy if exists "Users can update their own SafeLock state" on public.spending_locks;
create policy "Users can update their own SafeLock state"
  on public.spending_locks for update using (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────
-- Done. Next step: run supabase/safelock_migration.sql, then restart the
-- app (full restart, not hot reload) and the PGRST205 errors will be gone.
-- ─────────────────────────────────────────────────────────────────────────
