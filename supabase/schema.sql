-- Isekai Strategem - Supabase schema (combat-v2 section 15: accounts + XP).
--
-- Run this once in the Supabase dashboard: SQL Editor -> New query -> paste ->
-- Run. It is idempotent (safe to re-run). See docs/supabase_setup.md for the
-- full setup checklist (auth providers, redirect URLs, GitHub secrets).
--
-- Security model:
--   * Row Level Security is ON for every table, so a player can only ever read
--     or write their OWN row (auth.uid() gate).
--   * The XP ledger is append-only and cannot be written directly by clients.
--     All awards go through award_battle_xp(), which recomputes the inverse-TEG
--     multiplier SERVER-SIDE so the client can never set its own XP. (The
--     client reports the base XP + squad grade; the server owns the math and
--     the running total.)

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- One row per authenticated user (including anonymous "guest" users). Mirrors
-- auth.users and holds the display name, how they signed in, and the
-- authoritative running XP total.
create table if not exists public.accounts (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text        not null default 'Player',
  auth_method  text        not null default 'guest',
  total_xp     bigint      not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Append-only record of each finished battle's XP award. Written only by
-- award_battle_xp() (there is no client insert/update policy).
create table if not exists public.xp_ledger (
  id          bigint generated always as identity primary key,
  player_id   uuid        not null references public.accounts(id) on delete cascade,
  base_xp     int         not null,
  tier        text        not null,
  awarded_xp  int         not null,
  won         boolean     not null,
  ended_at    timestamptz not null,
  created_at  timestamptz not null default now()
);

create index if not exists xp_ledger_player_idx
  on public.xp_ledger (player_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.accounts  enable row level security;
alter table public.xp_ledger enable row level security;

-- accounts: a user sees and edits only their own row.
drop policy if exists accounts_select_own on public.accounts;
create policy accounts_select_own on public.accounts
  for select using (auth.uid() = id);

drop policy if exists accounts_insert_own on public.accounts;
create policy accounts_insert_own on public.accounts
  for insert with check (auth.uid() = id);

drop policy if exists accounts_update_own on public.accounts;
create policy accounts_update_own on public.accounts
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- xp_ledger: a user can READ only their own ledger. No client write policy
-- exists, so direct inserts/updates are rejected; awards flow through the
-- security-definer function below.
drop policy if exists ledger_select_own on public.xp_ledger;
create policy ledger_select_own on public.xp_ledger
  for select using (auth.uid() = player_id);

-- ---------------------------------------------------------------------------
-- Grants (auto-expose is OFF, so grant the Data API roles explicitly)
-- ---------------------------------------------------------------------------

grant usage on schema public to authenticated;
grant select, insert, update on public.accounts to authenticated;
grant select on public.xp_ledger to authenticated;

-- ---------------------------------------------------------------------------
-- New-user trigger: create the account row on sign-up (incl. anonymous guests)
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.accounts (id, display_name, auth_method)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name',
             split_part(coalesce(new.email, 'Player'), '@', 1)),
    case
      when new.is_anonymous then 'guest'
      when new.raw_app_meta_data->>'provider' is not null
        then new.raw_app_meta_data->>'provider'
      else 'email'
    end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Authoritative XP award (inverse-TEG multiplier, computed server-side)
-- ---------------------------------------------------------------------------
-- Mirrors app/lib/src/game/battle_xp.dart:
--   bonus% by tier: D 75, C 63, B 51, A 40, S 28, SS 16, SSS 5
--   awarded = round(base_xp * (1 + bonus%/100))
-- base_xp is clamped to [0, 1000] to bound client-side abuse. Full anti-cheat
-- (server replays the battle) is a later phase; v1 owns the multiplier and the
-- running total so a client can never set its XP directly.
create or replace function public.award_battle_xp(
  p_base_xp  int,
  p_tier     text,
  p_won      boolean,
  p_ended_at timestamptz default now()
)
returns table (base_xp int, awarded_xp int, total_xp bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_base    int  := greatest(0, least(p_base_xp, 1000));
  v_bonus   int;
  v_awarded int;
  v_total   bigint;
begin
  if v_uid is null then
    raise exception 'award_battle_xp: not authenticated';
  end if;

  v_bonus := case upper(p_tier)
    when 'D'   then 75
    when 'C'   then 63
    when 'B'   then 51
    when 'A'   then 40
    when 'S'   then 28
    when 'SS'  then 16
    when 'SSS' then 5
    else 40
  end;

  v_awarded := round(v_base * (1 + v_bonus / 100.0))::int;

  -- Make sure an account row exists (covers users created before the trigger).
  insert into public.accounts (id) values (v_uid)
  on conflict (id) do nothing;

  insert into public.xp_ledger (player_id, base_xp, tier, awarded_xp, won, ended_at)
  values (v_uid, v_base, upper(p_tier), v_awarded, p_won, p_ended_at);

  -- Alias the table so total_xp is unambiguous vs the RETURNS TABLE column of
  -- the same name (else Postgres raises 42702 "column reference is ambiguous").
  update public.accounts a
    set total_xp = a.total_xp + v_awarded, updated_at = now()
    where a.id = v_uid
    returning a.total_xp into v_total;

  return query select v_base, v_awarded, v_total;
end;
$$;

grant execute on function
  public.award_battle_xp(int, text, boolean, timestamptz) to authenticated;
