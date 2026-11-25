# Supabase backend

Database schema, row level security and tests for Wiggle Move. Needs the
[Supabase CLI](https://supabase.com/docs/guides/cli) and Docker.

| Path | What |
|---|---|
| `migrations/20260101000000_schema.sql` | WM-07 tables: `profiles`, `trainers`, `routines`, `moves`, `sessions`, `move_results`; trigger creating a profile per auth user. RLS is enabled on every table here. |
| `migrations/20260101000100_rls.sql` | WM-08 grants + RLS policies. |
| `migrations/20260101000200_leaderboard.sql` | WM-09 `public.leaderboard(...)` security-definer function; `sessions.client_nonce` made `not null`. |
| `tests/rls_test.sql` | WM-08 pgTAP tests (cross-user reads/writes, anon access, content writes). |
| `tests/leaderboard_test.sql` | WM-09 pgTAP tests (ranking, ties, weekly filter, caller row, privileges). |

> **Not executed yet.** These files were written without Postgres, Docker or
> the Supabase CLI available, so neither the migrations nor the tests have
> been run. The first person with the CLI should run the commands below and
> fix anything that fails before anything is pushed.

## Local workflow

```powershell
supabase init        # once, only if supabase/config.toml does not exist yet
supabase start       # local stack in Docker
supabase db reset    # recreate local DB: apply all migrations (+ seed.sql once WM-11 adds it)
supabase test db     # run supabase/tests/*.sql with pgTAP
```

## Deploying

```powershell
supabase link --project-ref <ref>
supabase db push     # applies new migrations to the linked project
```

A human reviews every migration before `db push` — especially anything
touching RLS, grants or `security definer` functions. Never edit an applied
migration; add a new one.

## Access model

- **profiles** — signed-in user selects/updates only their own row
  (`auth.uid() = id`). Updatable columns: `display_name`, `avatar`, `goals`,
  `styles`, `level`, `onboarded` (not `id`/`created_at`). No client
  insert/delete: the `on_auth_user_created` trigger inserts, account deletion
  goes through Supabase Auth and cascades. anon: no access.
- **trainers / routines / moves** — read by anon + authenticated; written only
  by service role (admin, seed).
- **sessions / move_results** — signed-in user selects only their own rows. No
  client writes at all; the `submit_session` Edge Function (WM-10) writes with
  the service role. `sessions.client_nonce` (required since WM-09) +
  `unique (user_id, client_nonce)` makes retried submits idempotent.
- **leaderboard** — `public.leaderboard(p_routine_id text default null,
  p_period text default 'all', p_limit int default 50)`, callable by
  `authenticated` only (EXECUTE revoked from `public`/`anon`). It is
  `security definer` with `search_path = ''`, so it can rank everyone without
  loosening the policies above, and returns only
  `rank, display_name, avatar, score, is_me` (no user ids or emails).
  - `p_routine_id` set: each user's best session score on that routine.
    `null` (global): sum over routines of each user's best score per routine.
  - `p_period`: `'all'` or `'week'` (`played_at >= date_trunc('week', now())`,
    Monday 00:00 in the DB time zone, UTC on Supabase); anything else raises
    SQLSTATE `22023`.
  - Ranked with `rank()` (ties share a rank). Tied rows are ordered by who
    reached the score first, then display name. Empty names show as `Player`.
  - Top `p_limit` rows (clamped to 1..100), plus the caller's own row
    (`is_me = true`) if it is outside the top.
  - Client call: `supabase.rpc('leaderboard', params: {'p_routine_id': id,
    'p_period': 'week'})`.

## Notes

- `trainers.color` is `bigint`: the app stores Flutter ARGB colors
  (e.g. `0xFFFF7F3F` = 4294934335), which overflow Postgres `int`.
- `moves.target_angles` is a JSON object of Dart `Joint.name` → degrees, e.g.
  `{"leftShoulder": 165, "rightElbow": 170}` (`MoveTarget.angles`).
- `move_results.worst_joint` is constrained to the eight `Joint` names.
