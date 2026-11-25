# Supabase backend

Database schema, row level security and tests for Wiggle Move. Needs the
[Supabase CLI](https://supabase.com/docs/guides/cli) and Docker.

| Path | What |
|---|---|
| `migrations/20260101000000_schema.sql` | WM-07 tables: `profiles`, `trainers`, `routines`, `moves`, `sessions`, `move_results`; trigger creating a profile per auth user. RLS is enabled on every table here. |
| `migrations/20260101000100_rls.sql` | WM-08 grants + RLS policies. |
| `tests/rls_test.sql` | WM-08 pgTAP tests (cross-user reads/writes, anon access, content writes). |

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
  the service role. `sessions.client_nonce` + `unique (user_id, client_nonce)`
  makes retried submits idempotent.
- The leaderboard (WM-09) must expose ranked data via a `security definer`
  function/view, not by loosening these policies.

## Notes

- `trainers.color` is `bigint`: the app stores Flutter ARGB colors
  (e.g. `0xFFFF7F3F` = 4294934335), which overflow Postgres `int`.
- `moves.target_angles` is a JSON object of Dart `Joint.name` → degrees, e.g.
  `{"leftShoulder": 165, "rightElbow": 170}` (`MoveTarget.angles`).
- `move_results.worst_joint` is constrained to the eight `Joint` names.
