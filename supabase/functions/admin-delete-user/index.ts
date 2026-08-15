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

const databaseFailure = (error: { code?: string; message?: string } | null) => {
  const value = `${error?.code || ''} ${error?.message || ''}`;
  if (/SELF_DENIED/i.test(value)) return ['SELF_DELETE_DENIED', 403] as const;
  if (/LAST_ADMIN_DENIED/i.test(value)) return ['LAST_ADMIN_DENIED', 409] as const;
  if (/TARGET_NOT_FOUND|P4031/i.test(value)) return ['TARGET_ACCOUNT_NOT_FOUND', 404] as const;
  if (/AUTHORIZATION_DENIED|42501/i.test(value)) return ['ADMIN_AUTHORIZATION_DENIED', 403] as const;
  return ['ACCOUNT_DELETE_FAILED', 500] as const;
};
const authUserMissing = (error: { code?: string; message?: string; status?: number } | null) => Boolean(error && (
  error.status === 404 || /user[_ ]?not[_ ]?found|not found/i.test(`${error.code || ''} ${error.message || ''}`)
));

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return fail('METHOD_NOT_ALLOWED', 405);
  if (Number(req.headers.get('content-length') || 0) > 4096) return fail('DELETE_INPUT_INVALID', 400);

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authHeader = req.headers.get('Authorization') || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
  if (!url || !serviceKey) return fail('ACCOUNT_DELETE_FAILED', 500);
  if (!token) return fail('ADMIN_AUTHORIZATION_DENIED', 403);

  let body: Record<string, unknown>;
  try {
    const parsed = await req.json();
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return fail('DELETE_INPUT_INVALID', 400);
    body = parsed as Record<string, unknown>;
  } catch { return fail('DELETE_INPUT_INVALID', 400); }
  if (Object.keys(body).some(key => key !== 'userId')) return fail('DELETE_INPUT_INVALID', 400);
  const targetUserId = typeof body.userId === 'string' ? body.userId.trim() : '';
  if (!uuidPattern.test(targetUserId)) return fail('TARGET_ACCOUNT_NOT_FOUND', 404);

  const adminClient = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authResult, error: authError } = await adminClient.auth.getUser(token);
  if (authError || !authResult.user) return fail('ADMIN_AUTHORIZATION_DENIED', 403);
  const verifiedActorAuthUuid = authResult.user.id;

  const { data: actor, error: actorError } = await adminClient.from('users')
    .select('id, role, is_active, approved_at, deletion_status')
    .eq('supabase_user_id', verifiedActorAuthUuid).maybeSingle();
  if (actorError || !actor || String(actor.role).toLowerCase() !== 'admin' || !actor.is_active
      || !actor.approved_at || actor.deletion_status !== 'active') {
    return fail('ADMIN_AUTHORIZATION_DENIED', 403);
  }

  const { data: prepared, error: prepareError } = await adminClient.rpc('prepare_admin_account_deletion', {
    p_target_user_id: targetUserId,
    p_actor_supabase_user_id: verifiedActorAuthUuid,
  });
  if (prepareError || !prepared) {
    const [code, status] = databaseFailure(prepareError);
    return fail(code, status);
  }

  const targetAuthUuid = prepared.authUserId;
  if (targetAuthUuid) {
    const { error: deleteError } = await adminClient.auth.admin.deleteUser(targetAuthUuid);
    if (deleteError && !authUserMissing(deleteError)) {
      console.error('[ADMIN_DELETE_USER] AUTH_DELETE_FAILED');
      return fail('AUTH_DELETE_FAILED', 503);
    }
  }

  const { data: finalized, error: finalizeError } = await adminClient.rpc('finalize_admin_account_deletion', {
    p_target_user_id: targetUserId,
  });
  if (finalizeError || !finalized || finalized.status !== 'deleted') {
    console.error('[ADMIN_DELETE_USER] ACCOUNT_FINALIZE_FAILED');
    return fail('ACCOUNT_FINALIZE_FAILED', 503);
  }
  return reply({ success: true, status: 'deleted' });
});
