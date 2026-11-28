-- WM-07: Wiggle Move schema.
--
-- Mirrors the app models in lib/shared/backend/content_models.dart,
-- lib/features/profile/profile_store.dart and lib/shared/pose/pose_math.dart.
-- Every table has row level security enabled here, so no table is ever
-- exposed without RLS. Policies and grants live in the next migration
-- (20260101000100_rls.sql, WM-08); until then RLS denies all client access.

-- ---------------------------------------------------------------------------
-- profiles: one row per auth user, created by trigger on auth.users insert.
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default ''
    check (char_length(display_name) <= 40),
  avatar text,
  goals text[] not null default '{}',
  styles text[] not null default '{}',
  -- Exact strings from lib/features/profile/personalize_screen.dart.
  level text
    check (level in ('Beginner', 'Intermediate', 'Advanced')),
  onboarded boolean not null default false,
  created_at timestamptz not null default now()
);

comment on table public.profiles is
  'Per-user profile and personalization answers. Row created by public.handle_new_user().';

-- ---------------------------------------------------------------------------
-- Content tables (trainers -> routines -> moves). Written by admins /
-- service role only (seeded in WM-11); clients only read.
-- ---------------------------------------------------------------------------
create table public.trainers (
  id text primary key,
  name text not null,
  style text not null,
  -- Flutter Color as a 32-bit ARGB value (Color.toARGB32(), e.g. 0xFFFF7F3F).
  -- Unsigned 32-bit values exceed Postgres int (max 2^31-1), hence bigint.
  color bigint not null
    check (color between 0 and 4294967295),
  sort_order int not null default 0
);

create table public.routines (
  id text primary key,
  trainer_id text not null references public.trainers (id),
  name text not null,
  -- Free text, as in trainer_data.dart today ('Easy', 'Medium').
  level text not null,
  -- Path inside the routine-videos Storage bucket (WM-11); null = no video.
  video_path text,
  -- Sum of the routine's moves.duration_ms (Routine.durationMs in the app).
  duration_ms int not null check (duration_ms > 0),
  sort_order int not null default 0
);

create index routines_trainer_id_idx on public.routines (trainer_id);

create table public.moves (
  routine_id text not null references public.routines (id) on delete cascade,
  idx int not null check (idx >= 0),
  name text not null,
  instruction text not null,
  duration_ms int not null check (duration_ms > 0),
  target_angles jsonb not null
    check (jsonb_typeof(target_angles) = 'object'),
  primary key (routine_id, idx)
);

comment on column public.moves.target_angles is
  'MoveTarget.angles: JSON object mapping Joint enum name (Dart Joint.name: '
  'leftElbow, rightElbow, leftShoulder, rightShoulder, leftHip, rightHip, '
  'leftKnee, rightKnee) to the target angle in degrees (number), e.g. '
  '{"leftShoulder": 165, "rightShoulder": 165, "leftElbow": 170, "rightElbow": 170}.';

-- ---------------------------------------------------------------------------
-- Play history. Written only by the submit_session Edge Function (WM-10)
-- with the service role; clients read their own rows.
-- ---------------------------------------------------------------------------
create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  routine_id text not null references public.routines (id),
  score int not null check (score between 0 and 100),
  duration_ms int not null check (duration_ms >= 0),
  played_at timestamptz not null default now(),
  -- Client-generated id so a retried submit does not create a duplicate.
  client_nonce uuid,
  unique (user_id, client_nonce)
);

-- User history (newest first).
create index sessions_user_played_at_idx
  on public.sessions (user_id, played_at desc);

-- Leaderboard (WM-09).
create index sessions_routine_score_idx
  on public.sessions (routine_id, score desc);

create table public.move_results (
  session_id uuid not null references public.sessions (id) on delete cascade,
  move_idx int not null check (move_idx >= 0),
  score int not null check (score between 0 and 100),
  -- Dart Joint.name of MoveResult.worstJoint; null if none.
  worst_joint text
    check (worst_joint in (
      'leftElbow', 'rightElbow', 'leftShoulder', 'rightShoulder',
      'leftHip', 'rightHip', 'leftKnee', 'rightKnee'
    )),
  -- MoveResult.worstSignedDeviation in degrees (measured - target).
  deviation double precision,
  primary key (session_id, move_idx)
);

-- ---------------------------------------------------------------------------
-- Row level security on for every table (policies in WM-08 migration).
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.trainers enable row level security;
alter table public.routines enable row level security;
alter table public.moves enable row level security;
alter table public.sessions enable row level security;
alter table public.move_results enable row level security;

-- ---------------------------------------------------------------------------
-- Create a profile row whenever an auth user is created.
-- display_name comes from sign-up metadata (user-controlled), so it is
-- trimmed and cut to the 40-char limit instead of failing the sign-up.
-- ---------------------------------------------------------------------------
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    left(btrim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), 40)
  );
  return new;
end;
$$;

-- Only the trigger should run this; keep it out of the client RPC surface.
revoke all on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
