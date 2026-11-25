// WM-10: submit_session Edge Function (Deno).
//
// POST a finished play; the function authenticates the caller, validates the
// payload against the routine (validate.ts, pure + node-tested), rate-limits,
// and stores session + move_results atomically via public.submit_session_tx.
// Clients never insert into sessions/move_results themselves (RLS, WM-08).
//
// Env (injected by Supabase, never hardcoded): SUPABASE_URL,
// SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY.
// Never log request bodies, headers or tokens.
import { createClient } from 'npm:@supabase/supabase-js@2';

import {
  ERR,
  isValidRoutineId,
  MAX_BODY_BYTES,
  RATE_LIMIT_PER_HOUR,
  rateLimitDecision,
  validateSubmission,
} from './validate.ts';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

function error(status: number, code: string): Response {
  return json(status, { error: code });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') return error(405, 'method_not_allowed');

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) {
    console.error('submit_session: missing env');
    return error(500, 'server_misconfigured');
  }

  // --- Auth ---------------------------------------------------------------
  const authorization = req.headers.get('Authorization') ?? '';
  const match = /^Bearer\s+(\S+)$/i.exec(authorization);
  if (!match) return error(401, 'unauthorized');
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser(match[1]);
  if (userError || !userData?.user) return error(401, 'unauthorized');
  const userId = userData.user.id;

  // --- Body (size-capped before parsing) ----------------------------------
  const declared = Number(req.headers.get('Content-Length') ?? '0');
  if (declared > MAX_BODY_BYTES) return error(413, 'payload_too_large');
  let payload: unknown;
  try {
    const raw = await req.text();
    if (new TextEncoder().encode(raw).length > MAX_BODY_BYTES) {
      return error(413, 'payload_too_large');
    }
    payload = JSON.parse(raw);
  } catch {
    return error(400, ERR.invalidPayload);
  }
  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) {
    return error(400, ERR.invalidPayload);
  }
  const routineId = (payload as Record<string, unknown>).routine_id;
  if (!isValidRoutineId(routineId)) return error(400, ERR.invalidRoutineId);

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // --- Routine + move count -----------------------------------------------
  const { data: routine, error: routineError } = await admin
    .from('routines')
    .select('id, duration_ms')
    .eq('id', routineId)
    .maybeSingle();
  if (routineError) {
    console.error('submit_session: routine lookup failed', routineError.code);
    return error(500, 'internal_error');
  }
  if (!routine) return error(404, 'routine_not_found');

  const { count: moveCount, error: movesError } = await admin
    .from('moves')
    .select('idx', { count: 'exact', head: true })
    .eq('routine_id', routineId);
  if (movesError || moveCount === null) {
    console.error('submit_session: move count failed', movesError?.code);
    return error(500, 'internal_error');
  }

  // --- Rate limit (sessions in the last hour) -----------------------------
  const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { count: recent, error: rateError } = await admin
    .from('sessions')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
    .gte('played_at', since);
  if (rateError || recent === null) {
    console.error('submit_session: rate count failed', rateError?.code);
    return error(500, 'internal_error');
  }
  if (!rateLimitDecision(recent, RATE_LIMIT_PER_HOUR).allowed) {
    return error(429, 'rate_limited');
  }

  // --- Validate -----------------------------------------------------------
  const result = validateSubmission(payload, {
    id: routine.id,
    durationMs: routine.duration_ms,
    moveCount,
  });
  if (!result.ok) {
    // A routine with no moves is a content problem, not a client error.
    return result.error === ERR.invalidRoutine
      ? error(500, 'internal_error')
      : error(400, result.error);
  }
  const v = result.value;

  // --- Store atomically ---------------------------------------------------
  const { data: rows, error: rpcError } = await admin.rpc('submit_session_tx', {
    p_user: userId,
    p_routine_id: v.routine_id,
    p_nonce: v.client_nonce,
    p_score: v.score,
    p_duration_ms: v.duration_ms,
    p_results: v.results,
  });
  if (rpcError) {
    console.error('submit_session: submit_session_tx failed', rpcError.code);
    // 23514 check / 23503 FK violations mean the data was rejected by the DB.
    if (rpcError.code === '23514' || rpcError.code === '23503') {
      return error(400, 'rejected_by_database');
    }
    return error(500, 'internal_error');
  }
  const row = Array.isArray(rows) ? rows[0] : rows;
  if (!row?.session_id) {
    console.error('submit_session: submit_session_tx returned no row');
    return error(500, 'internal_error');
  }

  const duplicate = row.duplicate === true;
  let score = v.score;
  if (duplicate) {
    // A retry returns what was stored the first time, not the new payload.
    const { data: stored } = await admin
      .from('sessions')
      .select('score')
      .eq('id', row.session_id)
      .maybeSingle();
    if (stored) score = stored.score;
  }

  return json(200, { session_id: row.session_id, score, duplicate });
});
