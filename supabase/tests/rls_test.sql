-- WM-08: RLS tests. Run with `supabase test db` (pgTAP, via pg_prove).
-- Everything runs in one transaction that is rolled back, so the fixture
-- rows below never persist.
begin;

create extension if not exists pgtap with schema extensions;

select plan(36);

-- ---------------------------------------------------------------------------
-- Fixtures (as the migration owner, which bypasses RLS).
-- Users A and B; the auth trigger creates their profiles.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-00000000000a', 'rls-a@example.test',
   '{"display_name": "Alice"}'),
  ('00000000-0000-0000-0000-00000000000b', 'rls-b@example.test',
   '{"display_name": "Bob"}');

insert into public.trainers (id, name, style, color, sort_order)
values ('rls-test-trainer', 'Test Trainer', 'Test', 4294934335, 0);

insert into public.routines (id, trainer_id, name, level, duration_ms, sort_order)
values ('rls-test-routine', 'rls-test-trainer', 'Test Routine', 'Easy', 4000, 0);

insert into public.moves (routine_id, idx, name, instruction, duration_ms, target_angles)
values ('rls-test-routine', 0, 'Arms Up', 'Reach up', 4000,
        '{"leftShoulder": 165, "rightShoulder": 165}');

insert into public.sessions (id, user_id, routine_id, score, duration_ms, client_nonce)
values ('00000000-0000-0000-0000-0000000000a1',
        '00000000-0000-0000-0000-00000000000a',
        'rls-test-routine', 80, 4000,
        '00000000-0000-0000-0000-0000000000f1');

insert into public.move_results (session_id, move_idx, score, worst_joint, deviation)
values ('00000000-0000-0000-0000-0000000000a1', 0, 80, 'leftShoulder', -12.5);

-- 1-2: trigger created both profiles, display_name from metadata.
select is(
  (select display_name from public.profiles
    where id = '00000000-0000-0000-0000-00000000000a'),
  'Alice',
  'trigger creates profile for A with display_name from metadata'
);
select is(
  (select count(*) from public.profiles
    where id = '00000000-0000-0000-0000-00000000000b'),
  1::bigint,
  'trigger creates profile for B'
);

-- ---------------------------------------------------------------------------
-- As user B.
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000000b", "role": "authenticated"}';

-- 3-4: profiles select.
select is(
  (select count(*) from public.profiles
    where id = '00000000-0000-0000-0000-00000000000a'),
  0::bigint,
  'B cannot select A''s profile'
);
select is(
  (select count(*) from public.profiles),
  1::bigint,
  'B sees exactly one profile (own)'
);

-- 5-6: profiles update.
select lives_ok(
  $$ update public.profiles set display_name = 'hacked'
     where id = '00000000-0000-0000-0000-00000000000a' $$,
  'B update of A''s profile runs but is filtered by RLS'
);
select lives_ok(
  $$ update public.profiles set display_name = 'Bobby', onboarded = true
     where id = '00000000-0000-0000-0000-00000000000b' $$,
  'B can update own display_name/onboarded'
);

-- 7-10: profiles id / insert / delete.
select throws_ok(
  $$ update public.profiles set id = '00000000-0000-0000-0000-00000000000a'
     where id = '00000000-0000-0000-0000-00000000000b' $$,
  '42501',
  null,
  'B cannot change profiles.id'
);
select throws_ok(
  $$ update public.profiles set created_at = now()
     where id = '00000000-0000-0000-0000-00000000000b' $$,
  '42501',
  null,
  'B cannot change profiles.created_at'
);
select throws_ok(
  $$ insert into public.profiles (id) values (gen_random_uuid()) $$,
  '42501',
  null,
  'B cannot insert a profile'
);
select throws_ok(
  $$ delete from public.profiles
     where id = '00000000-0000-0000-0000-00000000000b' $$,
  '42501',
  null,
  'B cannot delete own profile'
);

-- 11-12: sessions / move_results select.
select is(
  (select count(*) from public.sessions),
  0::bigint,
  'B cannot select A''s sessions'
);
select is(
  (select count(*) from public.move_results),
  0::bigint,
  'B cannot select A''s move_results'
);

-- 13-18: sessions / move_results writes.
select throws_ok(
  $$ insert into public.sessions (user_id, routine_id, score, duration_ms)
     values ('00000000-0000-0000-0000-00000000000b', 'rls-test-routine', 100, 4000) $$,
  '42501',
  null,
  'B cannot insert a session for self'
);
select throws_ok(
  $$ update public.sessions set score = 0
     where id = '00000000-0000-0000-0000-0000000000a1' $$,
  '42501',
  null,
  'B cannot update A''s session'
);
select throws_ok(
  $$ delete from public.sessions
     where id = '00000000-0000-0000-0000-0000000000a1' $$,
  '42501',
  null,
  'B cannot delete A''s session'
);
select throws_ok(
  $$ insert into public.move_results (session_id, move_idx, score)
     values ('00000000-0000-0000-0000-0000000000a1', 1, 100) $$,
  '42501',
  null,
  'B cannot insert move_results'
);
select throws_ok(
  $$ update public.move_results set score = 0
     where session_id = '00000000-0000-0000-0000-0000000000a1' $$,
  '42501',
  null,
  'B cannot update A''s move_results'
);
select throws_ok(
  $$ delete from public.move_results
     where session_id = '00000000-0000-0000-0000-0000000000a1' $$,
  '42501',
  null,
  'B cannot delete A''s move_results'
);

-- 19-21: content read.
select is(
  (select count(*) from public.trainers where id = 'rls-test-trainer'),
  1::bigint,
  'authenticated can read trainers'
);
select is(
  (select count(*) from public.routines where id = 'rls-test-routine'),
  1::bigint,
  'authenticated can read routines'
);
select is(
  (select count(*) from public.moves where routine_id = 'rls-test-routine'),
  1::bigint,
  'authenticated can read moves'
);

-- 22-24: content write.
select throws_ok(
  $$ insert into public.trainers (id, name, style, color)
     values ('evil', 'Evil', 'Evil', 0) $$,
  '42501',
  null,
  'authenticated cannot insert trainers'
);
select throws_ok(
  $$ update public.routines set name = 'hacked'
     where id = 'rls-test-routine' $$,
  '42501',
  null,
  'authenticated cannot update routines'
);
select throws_ok(
  $$ delete from public.moves where routine_id = 'rls-test-routine' $$,
  '42501',
  null,
  'authenticated cannot delete moves'
);

-- ---------------------------------------------------------------------------
-- As user A: owner can read own history but still not write it.
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000000a", "role": "authenticated"}';

-- 25-28
select is(
  (select count(*) from public.sessions),
  1::bigint,
  'A can select own session'
);
select is(
  (select count(*) from public.move_results),
  1::bigint,
  'A can select own move_results'
);
select throws_ok(
  $$ insert into public.sessions (user_id, routine_id, score, duration_ms)
     values ('00000000-0000-0000-0000-00000000000a', 'rls-test-routine', 100, 4000) $$,
  '42501',
  null,
  'A cannot insert own session directly'
);
select throws_ok(
  $$ update public.sessions set score = 100
     where id = '00000000-0000-0000-0000-0000000000a1' $$,
  '42501',
  null,
  'A cannot update own session score'
);

-- ---------------------------------------------------------------------------
-- As anon.
-- ---------------------------------------------------------------------------
set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

-- 29-31
select throws_ok(
  $$ select * from public.profiles $$,
  '42501',
  null,
  'anon cannot read profiles'
);
select throws_ok(
  $$ select * from public.sessions $$,
  '42501',
  null,
  'anon cannot read sessions'
);
select throws_ok(
  $$ select * from public.move_results $$,
  '42501',
  null,
  'anon cannot read move_results'
);

-- 32-33
select is(
  (select count(*) from public.trainers where id = 'rls-test-trainer'),
  1::bigint,
  'anon can read trainers'
);
select throws_ok(
  $$ insert into public.trainers (id, name, style, color)
     values ('evil', 'Evil', 'Evil', 0) $$,
  '42501',
  null,
  'anon cannot insert trainers'
);

-- ---------------------------------------------------------------------------
-- Back to the owner role: check nothing B/A tried actually changed data.
-- ---------------------------------------------------------------------------
reset role;

-- 34-36
select is(
  (select display_name from public.profiles
    where id = '00000000-0000-0000-0000-00000000000a'),
  'Alice',
  'A''s profile unchanged after B''s update attempt'
);
select is(
  (select display_name from public.profiles
    where id = '00000000-0000-0000-0000-00000000000b'),
  'Bobby',
  'B''s own profile update was applied'
);
select is(
  (select score from public.sessions
    where id = '00000000-0000-0000-0000-0000000000a1'),
  80,
  'A''s session score unchanged'
);

select * from finish();
rollback;
