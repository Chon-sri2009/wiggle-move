-- WM-10: atomic, idempotent session insert for the submit_session Edge
-- Function.
--
-- The Edge Function (supabase/functions/submit_session) authenticates the
-- caller, validates the payload and rate-limits, then calls this with the
-- service role. Everything here runs in the single transaction of the RPC
-- call, so a session row never exists without its move_results.
--
-- Idempotency: (user_id, client_nonce) is unique (WM-07, not null since
-- WM-09). A retry with the same nonce returns the stored session with
-- duplicate = true and writes nothing. Concurrent retries: the second insert
-- waits on the unique index, then "on conflict do nothing" skips it and the
-- re-select (a new statement, so a new snapshot under read committed) finds
-- the committed row.
--
-- No RLS change: clients still have no write privilege on sessions /
-- move_results, and cannot execute this function.

create function public.submit_session_tx(
  p_user uuid,
  p_routine_id text,
  p_nonce uuid,
  p_score int,
  p_duration_ms int,
  p_results jsonb
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
    (user_id, routine_id, score, duration_ms, client_nonce)
  values
    (p_user, p_routine_id, p_score, p_duration_ms, p_nonce)
  on conflict (user_id, client_nonce) do nothing
  returning s.id into v_id;

  if v_id is null then
    -- Already stored by an earlier (or concurrent, now committed) call.
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

  -- JSON null for worst_joint / deviation becomes SQL NULL via ->>.
  -- Bad values fail the move_results checks and roll back the session too.
  insert into public.move_results
    (session_id, move_idx, score, worst_joint, deviation)
  select
    v_id,
    (r.elem ->> 'move_idx')::int,
    (r.elem ->> 'score')::int,
    r.elem ->> 'worst_joint',
    (r.elem ->> 'deviation')::double precision
  from pg_catalog.jsonb_array_elements(p_results) as r (elem);

  return query select v_id, false;
end;
$$;

comment on function public.submit_session_tx(uuid, text, uuid, int, int, jsonb) is
  'WM-10 atomic insert of one session + its move_results (security definer, '
  'service_role only). p_results: [{move_idx, score, worst_joint, deviation}]. '
  'Same (p_user, p_nonce) again returns the stored session with duplicate=true.';

-- PUBLIC has EXECUTE on new functions by default and Supabase's default
-- privileges add anon/authenticated; only the Edge Function (service_role)
-- may call this.
revoke all on function public.submit_session_tx(uuid, text, uuid, int, int, jsonb)
  from public, anon, authenticated;
grant execute on function public.submit_session_tx(uuid, text, uuid, int, int, jsonb)
  to service_role;
