-- WM-10: submit_session_tx tests. Run with `supabase test db` (pgTAP).
-- Everything runs in one transaction that is rolled back.
begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

-- ---------------------------------------------------------------------------
-- Fixtures (as the migration owner). Users A and B; routine with 2 moves.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-0000000002a1', 'st-a@example.test',
   '{"display_name": "Alice"}'),
  ('00000000-0000-0000-0000-0000000002b1', 'st-b@example.test',
   '{"display_name": "Bob"}');

insert into public.trainers (id, name, style, color, sort_order)
values ('st-test-trainer', 'Test Trainer', 'Test', 4294934335, 0);

insert into public.routines (id, trainer_id, name, level, duration_ms, sort_order)
values ('st-r1', 'st-test-trainer', 'Routine 1', 'Easy', 8000, 0);

insert into public.moves (routine_id, idx, name, instruction, duration_ms, target_angles)
values
  ('st-r1', 0, 'Arms Up', 'Reach up', 4000, '{"leftShoulder": 165}'),
  ('st-r1', 1, 'Squat', 'Bend knees', 4000, '{"leftKnee": 90}');

-- 1-4: privileges and definition.
select ok(
  not has_function_privilege('anon',
    'public.submit_session_tx(uuid, text, uuid, integer, integer, jsonb, integer)', 'execute'),
  'anon has no execute on submit_session_tx'
);
select ok(
  not has_function_privilege('authenticated',
    'public.submit_session_tx(uuid, text, uuid, integer, integer, jsonb, integer)', 'execute'),
  'authenticated has no execute on submit_session_tx'
);
select ok(
  has_function_privilege('service_role',
    'public.submit_session_tx(uuid, text, uuid, integer, integer, jsonb, integer)', 'execute'),
  'service_role has execute on submit_session_tx'
);
select is(
  (select prosecdef from pg_catalog.pg_proc
    where oid = 'public.submit_session_tx(uuid, text, uuid, integer, integer, jsonb, integer)'::regprocedure),
  true,
  'submit_session_tx is security definer'
);

-- 5-9: first submit inserts session + move_results.
select is(
  (select duplicate from public.submit_session_tx(
    '00000000-0000-0000-0000-0000000002a1', 'st-r1',
    '00000000-0000-0000-0000-0000000002f1', 70, 8000,
    '[{"move_idx": 0, "score": 60, "worst_joint": "leftElbow", "deviation": -12.5},
      {"move_idx": 1, "score": 80, "worst_joint": null, "deviation": null}]')),
  false,
  'first submit is not a duplicate'
);
select is(
  (select score from public.sessions
    where user_id = '00000000-0000-0000-0000-0000000002a1'
      and client_nonce = '00000000-0000-0000-0000-0000000002f1'),
  70,
  'session row stored with score'
);
select is(
  (select count(*) from public.move_results mr
    join public.sessions s on s.id = mr.session_id
    where s.client_nonce = '00000000-0000-0000-0000-0000000002f1'),
  2::bigint,
  'both move_results stored'
);
select is(
  (select deviation from public.move_results mr
    join public.sessions s on s.id = mr.session_id
    where s.client_nonce = '00000000-0000-0000-0000-0000000002f1'
      and mr.move_idx = 0),
  -12.5::double precision,
  'signed deviation stored'
);
select ok(
  (select mr.worst_joint is null and mr.deviation is null
    from public.move_results mr
    join public.sessions s on s.id = mr.session_id
    where s.client_nonce = '00000000-0000-0000-0000-0000000002f1'
      and mr.move_idx = 1),
  'JSON null worst_joint/deviation stored as SQL NULL'
);

-- 10-12: retry with the same nonce is idempotent.
select results_eq(
  $$ select session_id, duplicate from public.submit_session_tx(
       '00000000-0000-0000-0000-0000000002a1', 'st-r1',
       '00000000-0000-0000-0000-0000000002f1', 99, 8000,
       '[{"move_idx": 0, "score": 99, "worst_joint": null, "deviation": null},
         {"move_idx": 1, "score": 99, "worst_joint": null, "deviation": null}]') $$,
  $$ select id, true from public.sessions
       where user_id = '00000000-0000-0000-0000-0000000002a1'
         and client_nonce = '00000000-0000-0000-0000-0000000002f1' $$,
  'retry returns the same session id with duplicate = true'
);
select is(
  (select pg_catalog.string_agg(score::text, ',') from public.sessions
    where user_id = '00000000-0000-0000-0000-0000000002a1'),
  '70',
  'retry created no extra session and did not change the score'
);
select is(
  (select count(*) from public.move_results mr
    join public.sessions s on s.id = mr.session_id
    where s.user_id = '00000000-0000-0000-0000-0000000002a1'),
  2::bigint,
  'retry created no extra move_results'
);

-- 13: the nonce is unique per user, not globally.
select is(
  (select duplicate from public.submit_session_tx(
    '00000000-0000-0000-0000-0000000002b1', 'st-r1',
    '00000000-0000-0000-0000-0000000002f1', 50, 8000,
    '[{"move_idx": 0, "score": 50, "worst_joint": null, "deviation": null},
      {"move_idx": 1, "score": 50, "worst_joint": null, "deviation": null}]')),
  false,
  'same nonce from another user is a new session'
);

-- 14-15: atomicity. The session insert succeeds, then a move score of 150
-- violates move_results' check; the whole call must roll back.
select throws_ok(
  $$ select * from public.submit_session_tx(
       '00000000-0000-0000-0000-0000000002a1', 'st-r1',
       '00000000-0000-0000-0000-0000000002f2', 70, 8000,
       '[{"move_idx": 0, "score": 70, "worst_joint": null, "deviation": null},
         {"move_idx": 1, "score": 150, "worst_joint": null, "deviation": null}]') $$,
  '23514',
  null,
  'bad move score violates the move_results check'
);
select is(
  (select count(*) from public.sessions
    where client_nonce = '00000000-0000-0000-0000-0000000002f2'),
  0::bigint,
  'failed submit left no session row'
);

-- 18-22: sets and reps (WM-39).
select is(
  (select duplicate from public.submit_session_tx(
    '00000000-0000-0000-0000-0000000002a1', 'st-r1',
    '00000000-0000-0000-0000-0000000002f5', 60, 24000,
    '[{"move_idx": 0, "score": 60, "reps": 30, "worst_joint": null, "deviation": null},
      {"move_idx": 1, "score": 60, "reps": 0, "worst_joint": null, "deviation": null}]',
    3)),
  false,
  'a play with sets and reps is stored'
);
select is(
  (select sets from public.sessions
    where client_nonce = '00000000-0000-0000-0000-0000000002f5'),
  3,
  'sets stored on the session'
);
select is(
  (select mr.reps from public.move_results mr
    join public.sessions s on s.id = mr.session_id
    where s.client_nonce = '00000000-0000-0000-0000-0000000002f5'
      and mr.move_idx = 0),
  30,
  'reps stored on the move result'
);
select is(
  (select s.sets * 100 + mr.reps from public.move_results mr
    join public.sessions s on s.id = mr.session_id
    where s.client_nonce = '00000000-0000-0000-0000-0000000002f1'
      and s.user_id = '00000000-0000-0000-0000-0000000002a1'
      and mr.move_idx = 0),
  100,
  'a 6-argument call with no reps key stores 1 set and 0 reps'
);
select throws_ok(
  $$ select * from public.submit_session_tx(
       '00000000-0000-0000-0000-0000000002a1', 'st-r1',
       '00000000-0000-0000-0000-0000000002f6', 60, 24000,
       '[{"move_idx": 0, "score": 60, "reps": -1, "worst_joint": null, "deviation": null},
         {"move_idx": 1, "score": 60, "reps": 0, "worst_joint": null, "deviation": null}]',
       3) $$,
  '23514',
  null,
  'negative reps violate the move_results check'
);

-- 16: authenticated cannot execute.
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000002a1", "role": "authenticated"}';

select throws_ok(
  $$ select * from public.submit_session_tx(
       '00000000-0000-0000-0000-0000000002a1', 'st-r1',
       '00000000-0000-0000-0000-0000000002f3', 70, 8000, '[]') $$,
  '42501',
  null,
  'authenticated cannot execute submit_session_tx'
);

reset role;

-- 17: anon cannot execute.
set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

select throws_ok(
  $$ select * from public.submit_session_tx(
       '00000000-0000-0000-0000-0000000002a1', 'st-r1',
       '00000000-0000-0000-0000-0000000002f4', 70, 8000, '[]') $$,
  '42501',
  null,
  'anon cannot execute submit_session_tx'
);

reset role;

select * from finish();
rollback;
