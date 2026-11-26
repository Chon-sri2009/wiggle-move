// WM-16: delete_account Edge Function (Deno).
//
// POST (no body) with the user's session token deletes that user from
// Supabase Auth. profiles, sessions and move_results go with them
// (on delete cascade). Clients cannot delete auth users themselves, so this
// runs with the service role; the user id comes only from the verified
// token, never from the request.
//
// Env (injected by Supabase): SUPABASE_URL, SUPABASE_ANON_KEY,
// SUPABASE_SERVICE_ROLE_KEY. Never log tokens or headers.
import { createClient } from 'npm:@supabase/supabase-js@2';

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

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) {
    console.error('delete_account: missing env');
    return json(500, { error: 'server_misconfigured' });
  }

  const authorization = req.headers.get('Authorization') ?? '';
  const match = /^Bearer\s+(\S+)$/i.exec(authorization);
  if (!match) return json(401, { error: 'unauthorized' });
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error: userError } = await userClient.auth.getUser(match[1]);
  if (userError || !data?.user) return json(401, { error: 'unauthorized' });

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { error } = await admin.auth.admin.deleteUser(data.user.id);
  if (error) {
    console.error('delete_account: delete failed', error.status);
    return json(500, { error: 'server_error' });
  }
  return json(200, { deleted: true });
});
