-- WM-08: Row level security policies and table privileges.
--
-- Two layers, both required:
--   1. Privileges (GRANT/REVOKE). Supabase's default privileges grant ALL on
--      new public tables to anon and authenticated; we revoke that and grant
--      back only what clients need. This also blocks TRUNCATE, which RLS
--      does not cover, and stops clients changing profiles.id / created_at.
--   2. RLS policies, which pick the rows a granted privilege applies to.
-- service_role bypasses RLS and keeps its grants: it is used by admins,
-- the seed (WM-11) and the submit_session Edge Function (WM-10).
-- The leaderboard (WM-09) must expose other users' data through a
-- security-definer function/view, not by loosening anything here.

-- ---------------------------------------------------------------------------
-- Start from nothing for client roles.
-- ---------------------------------------------------------------------------
revoke all on table
  public.profiles,
  public.trainers,
  public.routines,
  public.moves,
  public.sessions,
  public.move_results
from anon, authenticated;

-- ---------------------------------------------------------------------------
-- profiles: a signed-in user reads and edits only their own row.
-- No INSERT (the auth trigger creates the row) and no DELETE (account
-- deletion goes through Supabase Auth and cascades). anon gets nothing.
-- UPDATE is column-scoped so id and created_at cannot be changed.
-- ---------------------------------------------------------------------------
grant select on table public.profiles to authenticated;
grant update (display_name, avatar, goals, styles, level, onboarded)
  on table public.profiles to authenticated;

create policy profiles_select_own
  on public.profiles
  for select
  to authenticated
  using ((select auth.uid()) = id);

create policy profiles_update_own
  on public.profiles
  for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- ---------------------------------------------------------------------------
-- Content: public read for everyone, no client writes (no write grants and
-- no write policies).
-- ---------------------------------------------------------------------------
grant select on table public.trainers to anon, authenticated;
grant select on table public.routines to anon, authenticated;
grant select on table public.moves to anon, authenticated;

create policy trainers_select_all
  on public.trainers
  for select
  to anon, authenticated
  using (true);

create policy routines_select_all
  on public.routines
  for select
  to anon, authenticated
  using (true);

create policy moves_select_all
  on public.moves
  for select
  to anon, authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- sessions / move_results: a signed-in user reads only their own history.
-- Writes come only from the submit_session Edge Function (service role),
-- so clients get no INSERT/UPDATE/DELETE privilege and no write policy.
-- ---------------------------------------------------------------------------
grant select on table public.sessions to authenticated;
grant select on table public.move_results to authenticated;

create policy sessions_select_own
  on public.sessions
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy move_results_select_own
  on public.move_results
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.sessions s
      where s.id = move_results.session_id
        and s.user_id = (select auth.uid())
    )
  );

-- Explicit, so a later "grant all" cannot be mistaken for intent.
revoke insert, update, delete, truncate on table public.sessions
  from anon, authenticated;
revoke insert, update, delete, truncate on table public.move_results
  from anon, authenticated;
