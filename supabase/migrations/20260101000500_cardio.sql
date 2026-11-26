-- WM-39: sets, reps and cardio.
--
-- Content: routines get a category (dance | cardio), a number of sets with a
-- rest between them and a MET value (calorie estimate, computed in the app
-- from MET and the measured play time, never stored). Moves may be counted:
-- `reps` per set, and the joint/angle thresholds the camera counts them with
-- (lib/shared/pose/rep_counter.dart: a rep is rep_joint reaching rep_low and
-- coming back up to rep_high).
--
-- Plays: sessions.sets (sets played) and move_results.reps (reps counted over
-- all sets). move_results stays one row per move: the app aggregates a move
-- over its sets (mean score, summed reps), so (session_id, move_idx) is still
-- the primary key and history shows no per-set breakdown.
--
-- routines.duration_ms keeps meaning ONE set (the sum of its moves). The
-- submit_session Edge Function judges a play against
-- duration_ms * sets + rest_ms * (sets - 1).
--
-- The functions below are dropped and recreated (new signatures), which resets
-- their privileges to the defaults, so every revoke/grant is repeated.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
alter table public.routines
  add column category text not null default 'dance'
    check (category in ('dance', 'cardio')),
  add column sets int not null default 1
    check (sets between 1 and 20),
  add column rest_ms int not null default 0
    check (rest_ms >= 0),
  add column met numeric not null default 3.5
    check (met > 0 and met <= 20);

comment on column public.routines.sets is
  'Times the move list is played. routines.duration_ms stays ONE set.';
comment on column public.routines.met is
  'Metabolic equivalent for the calorie estimate (kcal = met * 3.5 * 70 / 200 '
  '* minutes in the app, assuming a 70 kg body).';

alter table public.moves
  add column reps int check (reps is null or reps > 0),
  add column rep_joint text
    check (rep_joint in (
      'leftElbow', 'rightElbow', 'leftShoulder', 'rightShoulder',
      'leftHip', 'rightHip', 'leftKnee', 'rightKnee'
    )),
  add column rep_low double precision,
  add column rep_high double precision,
  add constraint moves_rep_all_or_none check (
    (reps is null and rep_joint is null and rep_low is null and rep_high is null)
    or (
      reps is not null and rep_joint is not null
      and rep_low is not null and rep_high is not null
      and rep_low < rep_high
    )
  );

comment on column public.moves.reps is
  'Reps per set for a counted (cardio) move; null for a timed pose. '
  'duration_ms is then the time allowed per set.';

alter table public.sessions
  add column sets int not null default 1
    check (sets between 1 and 20);

alter table public.move_results
  add column reps int not null default 0
    check (reps >= 0);

-- ---------------------------------------------------------------------------
-- leaderboard: optional category filter (p_category = 'dance' | 'cardio').
-- Same ranking rules as WM-09; the category only narrows which sessions count
-- (so a global cardio board is the sum of best scores over cardio routines).
-- ---------------------------------------------------------------------------
drop function public.leaderboard(text, text, int);

create function public.leaderboard(
  p_routine_id text default null,
  p_period text default 'all',
  p_limit int default 50,
  p_category text default null
)
returns table (
  rank bigint,
  display_name text,
  avatar text,
  score int,
  is_me boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_limit int := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_since timestamptz;
  v_me uuid := auth.uid();
begin
  if p_period is null or p_period not in ('all', 'week') then
    raise exception 'invalid leaderboard period: %', coalesce(p_period, 'null')
      using errcode = '22023',
            hint = 'Use ''all'' or ''week''.';
  end if;

  if p_category is not null and p_category not in ('dance', 'cardio') then
    raise exception 'invalid leaderboard category: %', p_category
      using errcode = '22023',
            hint = 'Use ''dance'', ''cardio'' or null.';
  end if;

  if p_period = 'week' then
    v_since := pg_catalog.date_trunc('week', pg_catalog.now());
  end if;

  return query
  with period_sessions as (
    select
      s.user_id as s_user_id,
      s.routine_id as s_routine_id,
      s.score as s_score,
      s.played_at as s_played_at,
      pg_catalog.row_number() over (
        partition by s.user_id, s.routine_id
        order by s.score desc, s.played_at asc
      ) as s_rn
    from public.sessions s
    join public.routines rt on rt.id = s.routine_id
    where (p_routine_id is null or s.routine_id = p_routine_id)
      and (p_category is null or rt.category = p_category)
      and (v_since is null or s.played_at >= v_since)
  ),
  totals as (
    select
      ps.s_user_id as t_user_id,
      sum(ps.s_score)::int as t_score,
      max(ps.s_played_at) as t_achieved_at
    from period_sessions ps
    where ps.s_rn = 1
    group by ps.s_user_id
  ),
  ranked as (
    select
      t.t_user_id as r_user_id,
      pg_catalog.rank() over (order by t.t_score desc) as r_rank,
      coalesce(nullif(pg_catalog.btrim(p.display_name), ''), 'Player')
        as r_name,
      p.avatar as r_avatar,
      t.t_score as r_score,
      pg_catalog.row_number() over (
        order by
          t.t_score desc,
          t.t_achieved_at asc,
          coalesce(nullif(pg_catalog.btrim(p.display_name), ''), 'Player') asc,
          t.t_user_id asc
      ) as r_pos
    from totals t
    join public.profiles p on p.id = t.t_user_id
  )
  select
    r.r_rank,
    r.r_name,
    r.r_avatar,
    r.r_score,
    coalesce(r.r_user_id = v_me, false)
  from ranked r
  where r.r_pos <= v_limit
     or r.r_user_id = v_me
  order by r.r_pos;
end;
$$;

comment on function public.leaderboard(text, text, int, text) is
  'WM-09/WM-39 ranked scores (security definer; returns no user ids/emails). '
  'p_routine_id null = global sum of best per routine; p_period all|week; '
  'p_limit clamped 1..100; p_category null|dance|cardio narrows the routines; '
  'caller''s row appended when outside the top.';

revoke all on function public.leaderboard(text, text, int, text) from public, anon;
grant execute on function public.leaderboard(text, text, int, text) to authenticated;

-- ---------------------------------------------------------------------------
-- submit_session_tx: stores sets and each move's reps. p_sets is last and
-- defaults to 1 so 6-argument callers keep working. Everything else is the
-- WM-10 behaviour (atomic, idempotent by (user, nonce)).
-- ---------------------------------------------------------------------------
drop function public.submit_session_tx(uuid, text, uuid, int, int, jsonb);

create function public.submit_session_tx(
  p_user uuid,
  p_routine_id text,
  p_nonce uuid,
  p_score int,
  p_duration_ms int,
  p_results jsonb,
  p_sets int default 1
)
returns table (session_id uuid, duplicate boolean)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if p_user is null or p_nonce is null then
    raise exception 'submit_session_tx: p_user and p_nonce are required'
      using errcode = '22023';
  end if;
  if p_results is null or pg_catalog.jsonb_typeof(p_results) <> 'array' then
    raise exception 'submit_session_tx: p_results must be a JSON array'
      using errcode = '22023';
  end if;

  insert into public.sessions as s
    (user_id, routine_id, score, duration_ms, client_nonce, sets)
  values
    (p_user, p_routine_id, p_score, p_duration_ms, p_nonce, coalesce(p_sets, 1))
  on conflict (user_id, client_nonce) do nothing
  returning s.id into v_id;

  if v_id is null then
    select s.id into v_id
    from public.sessions s
    where s.user_id = p_user
      and s.client_nonce = p_nonce;

    if v_id is null then
      raise exception 'submit_session_tx: conflicting session not found'
        using errcode = 'P0002';
    end if;

    return query select v_id, true;
    return;
  end if;

  -- A missing reps key counts as 0. Bad values fail the move_results checks
  -- and roll the session back too.
  insert into public.move_results
    (session_id, move_idx, score, reps, worst_joint, deviation)
  select
    v_id,
    (r.elem ->> 'move_idx')::int,
    (r.elem ->> 'score')::int,
    coalesce((r.elem ->> 'reps')::int, 0),
    r.elem ->> 'worst_joint',
    (r.elem ->> 'deviation')::double precision
  from pg_catalog.jsonb_array_elements(p_results) as r (elem);

  return query select v_id, false;
end;
$$;

comment on function public.submit_session_tx(uuid, text, uuid, int, int, jsonb, int) is
  'WM-10/WM-39 atomic insert of one session + its move_results (security '
  'definer, service_role only). p_results: [{move_idx, score, reps, '
  'worst_joint, deviation}]; p_sets = sets played. Same (p_user, p_nonce) '
  'again returns the stored session with duplicate=true.';

revoke all on function public.submit_session_tx(uuid, text, uuid, int, int, jsonb, int)
  from public, anon, authenticated;
grant execute on function public.submit_session_tx(uuid, text, uuid, int, int, jsonb, int)
  to service_role;
