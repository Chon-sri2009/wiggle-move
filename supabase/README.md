# Supabase backend

Database schema, row level security and tests for Wiggle Move. Needs the
[Supabase CLI](https://supabase.com/docs/guides/cli) and Docker.

| Path | What |
|---|---|
| `migrations/20260101000000_schema.sql` | WM-07 tables: `profiles`, `trainers`, `routines`, `moves`, `sessions`, `move_results`; trigger creating a profile per auth user. RLS is enabled on every table here. |
| `migrations/20260101000100_rls.sql` | WM-08 grants + RLS policies. |
| `migrations/20260101000200_leaderboard.sql` | WM-09 `public.leaderboard(...)` security-definer function; `sessions.client_nonce` made `not null`. |
| `migrations/20260101000300_storage.sql` | WM-11 `routine-videos` Storage bucket (public read, service-role-only writes). |
| `migrations/20260101000400_submit_session.sql` | WM-10 `public.submit_session_tx(...)`: atomic, idempotent session + move_results insert (service_role only). |
| `functions/delete_account/` | WM-16 Edge Function: deletes the calling user from Auth (profile, sessions and results cascade). Not run. |
| `functions/submit_session/` | WM-10 Edge Function: `index.ts` (Deno handler), `validate.ts` (pure validation), `validate.test.ts` (node tests). |
| `seed.sql` | WM-11 content seed: trainers, routines, moves mirroring `lib/features/trainers/trainer_data.dart`. |
| `tests/rls_test.sql` | WM-08 pgTAP tests (cross-user reads/writes, anon access, content writes). |
| `tests/leaderboard_test.sql` | WM-09 pgTAP tests (ranking, ties, weekly filter, caller row, privileges). |
| `tests/submit_session_test.sql` | WM-10 pgTAP tests (atomic insert, idempotent retry, rollback on bad data, privileges). |

> **Not executed yet.** These files were written without Postgres, Docker or
> the Supabase CLI available, so neither the migrations nor the tests have
> been run, nor has the Deno handler `functions/submit_session/index.ts`
> (only its pure validation is tested, with Node). The first person with the CLI should run the commands below and
> fix anything that fails before anything is pushed.

## Local workflow

```powershell
supabase init        # once, only if supabase/config.toml does not exist yet
supabase start       # local stack in Docker
supabase db reset    # recreate local DB: apply all migrations, then seed.sql
supabase test db     # run supabase/tests/*.sql with pgTAP
```

## Deploying

```powershell
supabase link --project-ref <ref>
supabase db push     # applies new migrations to the linked project
```

Edge Function:

```powershell
supabase functions deploy submit_session
supabase functions deploy delete_account
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are
injected into Edge Functions by Supabase; never set or commit them. JWT
verification stays on (the default), and the function also checks the user
itself.

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

## submit_session (WM-10)

The only way to store a play. `POST /functions/v1/submit_session` with
`Authorization: Bearer <user access token>` (the Flutter client does this via
`supabase.functions.invoke('submit_session', body: ...)`, WM-23).

Request body (JSON, max 32 KB, exactly these keys, no others):

```json
{
  "routine_id": "mia-pop-starter",
  "client_nonce": "3f2b8c1e-9a4d-4c7b-8e2f-1a2b3c4d5e6f",
  "duration_ms": 10000,
  "score": 70,
  "results": [
    {"move_idx": 0, "score": 60, "worst_joint": "leftElbow", "deviation": -12.5},
    {"move_idx": 1, "score": 80, "worst_joint": null, "deviation": null}
  ]
}
```

Rules (`functions/submit_session/validate.ts`):
- `routine_id`: existing routine (else 404), string up to 64 chars.
- `client_nonce`: UUID, generated once per play and reused on retries.
- `duration_ms`: integer within 0.8x..3x the routine's `duration_ms`.
- `results`: exactly one entry per move, `move_idx` 0..n-1 each once (any
  order); `score` integer 0..100; `worst_joint` null or a Dart `Joint.name`;
  `deviation` null or a finite signed number (degrees, measured - target)
  with |deviation| <= 360.
- `score`: integer 0..100 equal to round(mean of move scores) +-1
  (`SessionSummary.totalScore`).
- Rate limit: 30 sessions per user per rolling hour (then 429).

Responses: `200 {"session_id": "...", "score": 70, "duplicate": false}`;
a retry with the same nonce returns the stored session with
`"duplicate": true`. Errors are `{"error": "<code>"}`: 400 (validation code
from `ERR` in `validate.ts`, e.g. `score_mismatch`, or
`rejected_by_database`), 401 `unauthorized`, 404 `routine_not_found`,
405 `method_not_allowed`, 413 `payload_too_large`, 429 `rate_limited`,
500 `internal_error` / `server_error` / `server_misconfigured`.

Order: auth -> size cap + JSON parse -> `client_nonce` shape check ->
idempotency lookup -> routine + validation -> rate limit -> insert. A retry
of an already-stored play (same nonce) always returns `200` with
`"duplicate": true` and the stored score, even after the rate limit is hit or
the routine changed. The rate limit is best-effort (count, then insert; not
atomic).

Storage goes through `public.submit_session_tx(...)` (security definer,
`search_path = ''`, EXECUTE for `service_role` only): one call inserts the
session and its move_results atomically; `(user_id, client_nonce)` makes it
idempotent, including concurrent retries.

Tests: `node --test "supabase/functions/submit_session/*.test.ts"` (Node >=
22.18; also in CI) for validation. The Deno handler `index.ts` has no
automated test: run it with `supabase functions serve submit_session` and
call it with a signed-in user's token.

## Seed data

`seed.sql` holds the same trainers / routines / moves as
`lib/features/trainers/trainer_data.dart` (ids, names, styles, ARGB colors,
levels, move order, instructions, durations, target angles). **Change both
together.** Every insert is `on conflict ... do update`, so the seed can be
re-run; `routines.video_path` is left untouched on re-seed, and moves beyond a
routine's current length are deleted. A `do` block at the end fails the seed
if the move count or any `routines.duration_ms` (sum of its moves) is off.
`supabase db reset` runs it locally; for a hosted project run it once as an
admin (SQL editor or `psql`), never from the app.

There is no automated Dart-vs-SQL parity test yet (comparing the two would
need SQL parsing in a Dart test, which would be brittle); review both files
side by side when editing.

## Storage

Bucket `routine-videos` (public). Anyone can read/stream objects; only the
service role uploads/replaces/deletes (no write policies exist on
`storage.objects` for this bucket). Store the object path in
`routines.video_path`, e.g. `mia/pop-starter.mp4`.

## Notes

- `trainers.color` is `bigint`: the app stores Flutter ARGB colors
  (e.g. `0xFFFF7F3F` = 4294934335), which overflow Postgres `int`.
- `moves.target_angles` is a JSON object of Dart `Joint.name` → degrees, e.g.
  `{"leftShoulder": 165, "rightElbow": 170}` (`MoveTarget.angles`).
- `move_results.worst_joint` is constrained to the eight `Joint` names.
