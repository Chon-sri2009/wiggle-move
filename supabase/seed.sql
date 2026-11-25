-- WM-11: Content seed (trainers -> routines -> moves).
--
-- Mirrors lib/shared/backend/trainer_data.dart exactly: same ids, names,
-- styles, levels, move order, instructions, durations and target angles.
-- Keep the two in sync when either changes.
--
-- `supabase db reset` runs this after the migrations (as the postgres role,
-- which bypasses RLS). Every insert is an upsert, so re-running it against an
-- existing database is safe. routines.video_path is never overwritten, so a
-- path set after uploading a video survives a re-seed.

-- ---------------------------------------------------------------------------
-- Trainers. color = Flutter ARGB as an unsigned 32-bit int:
--   AppColors.accent    0xFFFF7F3F = 4294934335
--   AppColors.secondary 0xFF1ADBC1 = 4279950273
-- ---------------------------------------------------------------------------
insert into public.trainers (id, name, style, color, sort_order)
values
  ('mia', 'Coach Mia', 'Pop & disco', 4294934335, 0),
  ('jay', 'Coach Jay', 'Cardio burn', 4279950273, 1)
on conflict (id) do update set
  name = excluded.name,
  style = excluded.style,
  color = excluded.color,
  sort_order = excluded.sort_order;

-- ---------------------------------------------------------------------------
-- Routines. sort_order is the order within the trainer. duration_ms is the
-- sum of the routine's moves (checked at the end of this file).
-- ---------------------------------------------------------------------------
insert into public.routines (id, trainer_id, name, level, duration_ms, sort_order)
values
  ('pop-starter', 'mia', 'Pop Starter', 'Easy', 24000, 0),
  ('disco-fever', 'mia', 'Disco Fever', 'Medium', 32000, 1),
  ('cardio-burn', 'jay', 'Cardio Burn', 'Medium', 24000, 0)
on conflict (id) do update set
  trainer_id = excluded.trainer_id,
  name = excluded.name,
  level = excluded.level,
  duration_ms = excluded.duration_ms,
  sort_order = excluded.sort_order;

-- ---------------------------------------------------------------------------
-- Moves. `templates` = the shared _move(...) definitions in trainer_data.dart
-- (key = Dart variable name); `sequence` = each routine's moves list in order
-- (idx = list index).
-- ---------------------------------------------------------------------------
insert into public.moves (routine_id, idx, name, instruction, duration_ms, target_angles)
select s.routine_id, s.idx, t.name, t.instruction, t.duration_ms, t.target_angles
from (
  values
    ('pop-starter', 0, '_armsUp'),
    ('pop-starter', 1, '_tPose'),
    ('pop-starter', 2, '_handsOnHips'),
    ('pop-starter', 3, '_pointRight'),
    ('pop-starter', 4, '_pointLeft'),
    ('pop-starter', 5, '_armsUp'),

    ('disco-fever', 0, '_pointRight'),
    ('disco-fever', 1, '_pointLeft'),
    ('disco-fever', 2, '_flex'),
    ('disco-fever', 3, '_tPose'),
    ('disco-fever', 4, '_pointRight'),
    ('disco-fever', 5, '_pointLeft'),
    ('disco-fever', 6, '_armsUp'),
    ('disco-fever', 7, '_handsOnHips'),

    ('cardio-burn', 0, '_halfSquat'),
    ('cardio-burn', 1, '_armsUp'),
    ('cardio-burn', 2, '_halfSquat'),
    ('cardio-burn', 3, '_flex'),
    ('cardio-burn', 4, '_halfSquat'),
    ('cardio-burn', 5, '_tPose')
) as s (routine_id, idx, template)
join (
  values
    ('_armsUp', 'Arms Up', 'Reach both arms straight up', 4000,
     '{"leftShoulder": 165, "rightShoulder": 165, "leftElbow": 170, "rightElbow": 170}'::jsonb),
    ('_tPose', 'T-Pose', 'Arms straight out to the sides', 4000,
     '{"leftShoulder": 90, "rightShoulder": 90, "leftElbow": 170, "rightElbow": 170}'::jsonb),
    ('_handsOnHips', 'Hands on Hips', 'Hands on your hips, elbows out', 4000,
     '{"leftElbow": 80, "rightElbow": 80, "leftShoulder": 35, "rightShoulder": 35}'::jsonb),
    ('_pointRight', 'Disco Point Right', 'Right arm up high, left arm down', 4000,
     '{"rightShoulder": 165, "rightElbow": 170, "leftShoulder": 15, "leftElbow": 170}'::jsonb),
    ('_pointLeft', 'Disco Point Left', 'Left arm up high, right arm down', 4000,
     '{"leftShoulder": 165, "leftElbow": 170, "rightShoulder": 15, "rightElbow": 170}'::jsonb),
    ('_flex', 'Flex', 'Arms out, elbows bent, fists up', 4000,
     '{"leftShoulder": 90, "rightShoulder": 90, "leftElbow": 60, "rightElbow": 60}'::jsonb),
    ('_halfSquat', 'Half Squat', 'Bend your knees, sit back', 4000,
     '{"leftKnee": 125, "rightKnee": 125}'::jsonb)
) as t (template, name, instruction, duration_ms, target_angles)
  on t.template = s.template
on conflict (routine_id, idx) do update set
  name = excluded.name,
  instruction = excluded.instruction,
  duration_ms = excluded.duration_ms,
  target_angles = excluded.target_angles;

-- If a routine got shorter since the last seed, drop its leftover moves.
delete from public.moves m
using (
  values ('pop-starter', 6), ('disco-fever', 8), ('cardio-burn', 6)
) as c (routine_id, move_count)
where m.routine_id = c.routine_id
  and m.idx >= c.move_count;

-- ---------------------------------------------------------------------------
-- Self-check: 20 moves seeded and routines.duration_ms = sum of its moves.
-- Fails the seed if the tables above drift apart.
-- ---------------------------------------------------------------------------
do $$
declare
  v_bad text;
begin
  if (select count(*) from public.moves
       where routine_id in ('pop-starter', 'disco-fever', 'cardio-burn')) <> 20 then
    raise exception 'seed: expected 20 moves for the seeded routines';
  end if;

  select string_agg(r.id, ', ') into v_bad
  from public.routines r
  where r.id in ('pop-starter', 'disco-fever', 'cardio-burn')
    and r.duration_ms <> (
      select coalesce(sum(m.duration_ms), 0)
      from public.moves m
      where m.routine_id = r.id
    );

  if v_bad is not null then
    raise exception 'seed: routines.duration_ms <> sum(moves.duration_ms) for %', v_bad;
  end if;
end;
$$;
