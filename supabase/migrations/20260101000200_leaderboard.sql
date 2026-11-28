-- WM-09: Leaderboard.
--
-- Clients can only read their own sessions (RLS, WM-08), so ranking across
-- users goes through this security-definer function. It returns only what a
-- leaderboard shows: rank, display name, avatar, score and whether the row is
-- the caller's. It never returns user ids or emails.
--
-- Written in PL/pgSQL rather than plain SQL only because an invalid p_period
-- must raise an error, which LANGUAGE sql cannot do. The body is a single
-- RETURN QUERY and the function is STABLE.

-- ---------------------------------------------------------------------------
-- sessions.client_nonce is now required: the submit_session Edge Function
-- (WM-10) always sends one, and unique (user_id, client_nonce) only makes
-- retries idempotent when it is never null. sessions has no rows yet.
-- ---------------------------------------------------------------------------
alter table public.sessions alter column client_nonce set not null;

comment on column public.sessions.client_nonce is
  'Client-generated id per play (required). unique (user_id, client_nonce) '
  'makes a retried submit_session call idempotent instead of duplicating it.';

-- ---------------------------------------------------------------------------
-- public.leaderboard(p_routine_id, p_period, p_limit)
--
--   p_routine_id  null = global; otherwise one routine id.
--   p_period      'all' | 'week' (played_at >= date_trunc('week', now()),
--                 i.e. since Monday 00:00 in the session time zone, UTC on
--                 Supabase). Anything else (including null) raises 22023.
--   p_limit       rows in the top list, clamped to 1..100 (null = 50).
--
-- Score per user: for one routine, the user's best session score in the
-- period; globally, the sum over routines of the user's best score per
-- routine in the period. Ranked by score desc with rank() (ties share a
-- rank, the next rank skips). Ties are listed by who reached the score
-- first (per routine: earliest session with the best score; global: the
-- latest of those per-routine times, i.e. when the total was reached), then
-- by display name. The caller's own row is appended when it is outside the
-- top p_limit. Users with an empty display name show as 'Player'.
-- ---------------------------------------------------------------------------
create function public.leaderboard(
  p_routine_id text default null,
  p_period text default 'all',
  p_limit int default 50
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
    where (p_routine_id is null or s.routine_id = p_routine_id)
      and (v_since is null or s.played_at >= v_since)
  ),
  totals as (
    -- One best session per (user, routine); summed per user. For a single
    -- routine there is one row per user, so the sum is that best score.
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

comment on function public.leaderboard(text, text, int) is
  'WM-09 ranked scores (security definer; returns no user ids/emails). '
  'p_routine_id null = global sum of best per routine; p_period all|week; '
  'p_limit clamped 1..100; caller''s row appended when outside the top.';

-- Supabase's default privileges grant EXECUTE on new public functions to
-- anon and authenticated (and PUBLIC has it by default), so revoke from all
-- and grant back only to signed-in users. service_role keeps its grant.
revoke all on function public.leaderboard(text, text, int) from public, anon;
grant execute on function public.leaderboard(text, text, int) to authenticated;
