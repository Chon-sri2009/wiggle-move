-- Audit fix: store when a play happened, not when it was uploaded.
--
-- A play finished offline waits in the app's pending queue and is uploaded
-- later. sessions.played_at defaulted to now(), so it got the upload time:
-- History showed the wrong time and a Sunday-night play counted toward the
-- next week's leaderboard. submit_session_tx now takes the client's play time.
--
-- The Edge Function (validate.ts) accepts p_played_at only when it is not in
-- the future and not older than 30 days; this function trusts its caller
-- (service_role only), exactly like its other arguments. p_played_at defaults
-- to null (= now()), so older callers keep working.
--
-- The function is dropped and recreated (new signature), which resets its
-- privileges, so the revoke/grant is repeated.

drop function public.submit_session_tx(uuid, text, uuid, int, int, jsonb, int);

create function public.submit_session_tx(
  p_user uuid,
  p_routine_id text,
  p_nonce uuid,
  p_score int,
  p_duration_ms int,
  p_results jsonb,
  p_sets int default 1,
  p_played_at timestamptz default null
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
    (user_id, routine_id, score, duration_ms, client_nonce, sets, played_at)
  values
    (p_user, p_routine_id, p_score, p_duration_ms, p_nonce,
     coalesce(p_sets, 1), coalesce(p_played_at, pg_catalog.now()))
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

comment on function public.submit_session_tx(uuid, text, uuid, int, int, jsonb, int, timestamptz) is
  'WM-10/WM-39 atomic insert of one session + its move_results (security '
  'definer, service_role only). p_played_at = when the play happened (null = '
  'now). Same (p_user, p_nonce) again returns the stored session with '
  'duplicate=true.';

revoke all on function public.submit_session_tx(uuid, text, uuid, int, int, jsonb, int, timestamptz)
  from public, anon, authenticated;
grant execute on function public.submit_session_tx(uuid, text, uuid, int, int, jsonb, int, timestamptz)
  to service_role;
