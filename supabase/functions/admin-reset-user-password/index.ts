import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const reply = (body: Record<string, unknown>, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
});
const fail = (code: string, status: number) => reply({ error: code }, status);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return fail('ADMIN_AUTHORIZATION_DENIED', 403);
  if (Number(req.headers.get('content-length') || 0) > 8192) return fail('PASSWORD_POLICY_INVALID', 400);

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authHeader = req.headers.get('Authorization') || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
  if (!url || !serviceKey) return fail('PASSWORD_RESET_FAILED', 500);
  if (!token) return fail('ADMIN_AUTHORIZATION_DENIED', 403);

  const adminClient = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authResult, error: authError } = await adminClient.auth.getUser(token);
  if (authError || !authResult.user) return fail('ADMIN_AUTHORIZATION_DENIED', 403);

  const { data: actor, error: actorError } = await adminClient.from('users')
    .select('id, role, is_active, approved_at, deletion_status')
    .eq('supabase_user_id', authResult.user.id).maybeSingle();
  if (actorError || !actor || String(actor.role).toLowerCase() !== 'admin' || !actor.is_active
      || !actor.approved_at || actor.deletion_status !== 'active') {
    return fail('ADMIN_AUTHORIZATION_DENIED', 403);
  }

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return fail('PASSWORD_POLICY_INVALID', 400); }
  const userId = typeof body.userId === 'string' ? body.userId.trim() : '';
  const newPassword = typeof body.newPassword === 'string' ? body.newPassword : '';
  if (!uuidPattern.test(userId)) return fail('TARGET_ACCOUNT_NOT_FOUND', 404);
  if (newPassword.length < 8 || newPassword.length > 256) return fail('PASSWORD_POLICY_INVALID', 400);

  const { data: target, error: targetError } = await adminClient.from('users')
    .select('id, supabase_user_id, deletion_status').eq('id', userId).maybeSingle();
  if (targetError) return fail('PASSWORD_RESET_FAILED', 500);
  if (!target) return fail('TARGET_ACCOUNT_NOT_FOUND', 404);
  if (target.deletion_status !== 'active') return fail('ACCOUNT_DELETION_PENDING', 409);
  if (!target.supabase_user_id) return fail('ACCOUNT_NOT_LINKED_TO_AUTH', 409);

  const { error: resetError } = await adminClient.auth.admin.updateUserById(target.supabase_user_id, { password: newPassword });
  if (resetError) {
    console.error('[ADMIN_RESET_USER_PASSWORD] PASSWORD_RESET_FAILED');
    return fail('PASSWORD_RESET_FAILED', 500);
  }
  return reply({ success: true });
});
