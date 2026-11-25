-- WM-09: leaderboard tests. Run with `supabase test db` (pgTAP, via pg_prove).
-- Everything runs in one transaction that is rolled back.
--
-- Global (p_routine_id null) results assume the database has no other
-- sessions, which holds after `supabase db reset` (seed.sql adds content
-- only, no sessions).
begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

-- ---------------------------------------------------------------------------
-- Fixtures (as the migration owner, which bypasses RLS).
-- w = start of the current week; "old" sessions are before it.
--
--   user   lb-r1                          lb-r2
--   Alice  95 (old), 70 (w+1m)            80 (w+2m)
--   Bob    90 (w+3m)                      60 (w+4m)
--   Cara   90 (w+5m)
--   ''     40 (w+6m)   -> shown as 'Player'
--   Eve    10 (w+7m)
--   Finn   (no sessions)
--
-- Expected:
--   lb-r1 all : Alice 95 #1, Bob 90 #2, Cara 90 #2, Player 40 #4, Eve 10 #5
--   lb-r1 week: Bob 90 #1, Cara 90 #1, Alice 70 #3, Player 40 #4, Eve 10 #5
--   global all: Alice 175 #1, Bob 150 #2, Cara 90 #3, Player 40 #4, Eve 10 #5
--   global week: Alice 150 #1 (reached w+2m), Bob 150 #1 (w+4m), Cara 90 #3,
--               Player 40 #4, Eve 10 #5
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-0000000001a1', 'lb-a@example.test',
   '{"display_name": "Alice"}'),
  ('00000000-0000-0000-0000-0000000001b1', 'lb-b@example.test',
   '{"display_name": "Bob"}'),
  ('00000000-0000-0000-0000-0000000001c1', 'lb-c@example.test',
   '{"display_name": "Cara"}'),
  ('00000000-0000-0000-0000-0000000001d1', 'lb-d@example.test',
   '{}'),
  ('00000000-0000-0000-0000-0000000001e1', 'lb-e@example.test',
   '{"display_name": "Eve"}'),
  ('00000000-0000-0000-0000-0000000001f1', 'lb-f@example.test',
   '{"display_name": "Finn"}');

insert into public.trainers (id, name, style, color, sort_order)
values ('lb-test-trainer', 'Test Trainer', 'Test', 4294934335, 0);

insert into public.routines (id, trainer_id, name, level, duration_ms, sort_order)
values
  ('lb-r1', 'lb-test-trainer', 'Routine 1', 'Easy', 4000, 0),
  ('lb-r2', 'lb-test-trainer', 'Routine 2', 'Easy', 4000, 1);

insert into public.sessions (user_id, routine_id, score, duration_ms, played_at, client_nonce)
values
  ('00000000-0000-0000-0000-0000000001a1', 'lb-r1', 95, 4000,
   date_trunc('week', now()) - interval '30 days', gen_random_uuid()),
  ('00000000-0000-0000-0000-0000000001a1', 'lb-r1', 70, 4000,
   date_trunc('week', now()) + interval '1 minute', gen_random_uuid()),
  ('00000000-0000-0000-0000-0000000001a1', 'lb-r2', 80, 4000,
   date_trunc('week', now()) + interval '2 minutes', gen_random_uuid()),
  ('00000000-0000-0000-0000-0000000001b1', 'lb-r1', 90, 4000,
   date_trunc('week', now()) + interval '3 minutes', gen_random_uuid()),
  ('00000000-0000-0000-0000-0000000001b1', 'lb-r2', 60, 4000,
   date_trunc('week', now()) + interval '4 minutes', gen_random_uuid()),
  ('00000000-0000-0000-0000-0000000001c1', 'lb-r1', 90, 4000,
   date_trunc('week', now()) + interval '5 minutes', gen_random_uuid()),
  ('00000000-0000-0000-0000-0000000001d1', 'lb-r1', 40, 4000,
   date_trunc('week', now()) + interval '6 minutes', gen_random_uuid()),
  ('00000000-0000-0000-0000-0000000001e1', 'lb-r1', 10, 4000,
   date_trunc('week', now()) + interval '7 minutes', gen_random_uuid());

-- 1: result shape exposes no ids or emails.
select is(
  pg_get_function_result('public.leaderboard(text, text, integer)'::regprocedure),
  'TABLE(rank bigint, display_name text, avatar text, score integer, is_me boolean)',
  'leaderboard returns only rank, display_name, avatar, score, is_me'
);

-- 2-3: security definer with an empty search_path.
select is_definer(
  'public', 'leaderboard', array['text', 'text', 'integer'],
  'leaderboard is security definer'
);
select is(
  (select proconfig from pg_proc
    where oid = 'public.leaderboard(text, text, integer)'::regprocedure),
  array['search_path=""'],
  'leaderboard pins search_path to empty'
);

-- 4-5: execute privileges.
select ok(
  not has_function_privilege('anon', 'public.leaderboard(text, text, integer)', 'execute'),
  'anon has no execute on leaderboard'
);
select ok(
  has_function_privilege('authenticated', 'public.leaderboard(text, text, integer)', 'execute'),
  'authenticated has execute on leaderboard'
);

-- 6: client_nonce is now required.
select col_not_null('public', 'sessions', 'client_nonce',
  'sessions.client_nonce is not null');

-- ---------------------------------------------------------------------------
-- As Alice.
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000001a1", "role": "authenticated"}';

-- 7: per routine, all time: best-of per user, tie shares rank 2 (Bob reached
-- 90 first), rank 3 skipped, empty name shows as Player.
select results_eq(
  $$ select rank, display_name, score, is_me
     from public.leaderboard('lb-r1', 'all', 50) $$,
  $$ values (1::bigint, 'Alice'::text, 95, true),
            (2::bigint, 'Bob'::text, 90, false),
            (2::bigint, 'Cara'::text, 90, false),
            (4::bigint, 'Player'::text, 40, false),
            (5::bigint, 'Eve'::text, 10, false) $$,
  'lb-r1 all time: best score per user, ties share rank'
);

-- 8: per routine, this week: Alice's old 95 is excluded.
select results_eq(
  $$ select rank, display_name, score, is_me
     from public.leaderboard('lb-r1', 'week', 50) $$,
  $$ values (1::bigint, 'Bob'::text, 90, false),
            (1::bigint, 'Cara'::text, 90, false),
            (3::bigint, 'Alice'::text, 70, true),
            (4::bigint, 'Player'::text, 40, false),
            (5::bigint, 'Eve'::text, 10, false) $$,
  'lb-r1 this week: sessions before the week start are excluded'
);

-- 9: global, all time: sum of best per routine.
select results_eq(
  $$ select rank, display_name, score, is_me
     from public.leaderboard(null, 'all', 50) $$,
  $$ values (1::bigint, 'Alice'::text, 175, true),
            (2::bigint, 'Bob'::text, 150, false),
            (3::bigint, 'Cara'::text, 90, false),
            (4::bigint, 'Player'::text, 40, false),
            (5::bigint, 'Eve'::text, 10, false) $$,
  'global all time: sum of best score per routine'
);

-- 10: global, this week: Alice and Bob tie on 150; Alice reached it first.
select results_eq(
  $$ select rank, display_name, score, is_me
     from public.leaderboard(null, 'week', 50) $$,
  $$ values (1::bigint, 'Alice'::text, 150, true),
            (1::bigint, 'Bob'::text, 150, false),
            (3::bigint, 'Cara'::text, 90, false),
            (4::bigint, 'Player'::text, 40, false),
            (5::bigint, 'Eve'::text, 10, false) $$,
  'global this week: tie shares rank, earliest achievement listed first'
);

-- 11: defaults are global, all time.
select results_eq(
  $$ select rank, display_name, score, is_me from public.leaderboard() $$,
  $$ select rank, display_name, score, is_me
     from public.leaderboard(null, 'all', 50) $$,
  'leaderboard() defaults to global, all time'
);

-- 12: p_limit is clamped to at least 1 (Alice is #1, so nothing is appended).
select is(
  (select count(*) from public.leaderboard('lb-r1', 'all', 0)),
  1::bigint,
  'p_limit 0 is clamped to 1'
);

-- 13-14: invalid period raises.
select throws_ok(
  $$ select * from public.leaderboard('lb-r1', 'month', 50) $$,
  '22023',
  null,
  'invalid period raises 22023'
);
select throws_ok(
  $$ select * from public.leaderboard('lb-r1', null, 50) $$,
  '22023',
  null,
  'null period raises 22023'
);

-- ---------------------------------------------------------------------------
-- As Eve (rank 5 on lb-r1).
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000001e1", "role": "authenticated"}';

-- 15: caller outside the top is appended with is_me.
select results_eq(
  $$ select rank, display_name, score, is_me
     from public.leaderboard('lb-r1', 'all', 2) $$,
  $$ values (1::bigint, 'Alice'::text, 95, false),
            (2::bigint, 'Bob'::text, 90, false),
            (5::bigint, 'Eve'::text, 10, true) $$,
  'caller''s own row is appended when outside the top'
);

-- 16: caller inside the top is not duplicated.
select is(
  (select count(*) from public.leaderboard('lb-r1', 'all', 5)),
  5::bigint,
  'caller inside the top is listed once'
);

-- ---------------------------------------------------------------------------
-- As Finn (no sessions): nothing to append.
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000001f1", "role": "authenticated"}';

-- 17
select is(
  (select count(*) from public.leaderboard('lb-r1', 'all', 2)),
  2::bigint,
  'caller without sessions gets only the top rows'
);

-- ---------------------------------------------------------------------------
-- As anon.
-- ---------------------------------------------------------------------------
set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

-- 18
select throws_ok(
  $$ select * from public.leaderboard() $$,
  '42501',
  null,
  'anon cannot execute leaderboard'
);

select * from finish();
rollback;
