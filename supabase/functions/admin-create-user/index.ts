import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const reply = (body: Record<string, unknown>, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
});
const fail = (code: string, status: number) => reply({ error: code }, status);
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const normalizedEmail = (value: unknown) => String(value || '').trim().toLowerCase();
const authEmailConflict = (error: { code?: string; message?: string; status?: number } | null) => Boolean(error && (
  error.status === 422 || /email.*(exists|registered)|already.*registered|user_already_exists/i.test(`${error.code || ''} ${error.message || ''}`)
));

async function findAuthEmail(adminClient: ReturnType<typeof createClient>, email: string) {
  const perPage = 1000;
  for (let page = 1; ; page += 1) {
    const { data, error } = await adminClient.auth.admin.listUsers({ page, perPage });
    if (error) return { exists: false, error };
    if (data.users.some(user => normalizedEmail(user.email) === email)) return { exists: true, error: null };
    if (data.users.length < perPage) return { exists: false, error: null };
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return fail('METHOD_NOT_ALLOWED', 405);
  if (Number(req.headers.get('content-length') || 0) > 16384) return fail('PAYLOAD_TOO_LARGE', 413);

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authHeader = req.headers.get('Authorization') || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
  if (!url || !serviceKey) return fail('SERVICE_CONFIGURATION_ERROR', 500);
  if (!token) return fail('ADMIN_AUTH_REQUIRED', 401);

  const adminClient = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authResult, error: authError } = await adminClient.auth.getUser(token);
  if (authError || !authResult.user) return fail('ADMIN_AUTH_REQUIRED', 401);

  const { data: actor, error: actorError } = await adminClient.from('users')
    .select('id, role, is_active, approved_at')
    .eq('supabase_user_id', authResult.user.id).maybeSingle();
  if (actorError || !actor || String(actor.role).toLowerCase() !== 'admin' || !actor.is_active || !actor.approved_at) {
    return fail('ADMIN_AUTHORIZATION_DENIED', 403);
  }

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return fail('STAFF_INPUT_INVALID', 400); }
  const fullName = String(body.fullName || '').trim();
  const clinicEmail = normalizedEmail(body.clinicEmail);
  const personalEmail = normalizedEmail(body.personalEmail);
  const phone = String(body.phone || '').trim();
  const role = String(body.role || '').trim().toLowerCase();
  const specialization = String(body.specialization || '').trim();
  const password = typeof body.password === 'string' ? body.password : '';
  if (!['doctor', 'receptionist'].includes(role)) return fail('INVALID_ROLE', 400);
  if (role === 'doctor' && !specialization) return fail('DOCTOR_SPECIALIZATION_REQUIRED', 400);
  if (!fullName || fullName.length > 200 || !emailPattern.test(clinicEmail) || !emailPattern.test(personalEmail)
    || phone.length > 50 || specialization.length > 200) {
    return fail('STAFF_INPUT_INVALID', 400);
  }
  if (password.length < 8) return fail('PASSWORD_POLICY_INVALID', 400);

  const [clinicConflict, personalConflict, authConflict] = await Promise.all([
    adminClient.from('users').select('id').ilike('email', clinicEmail).maybeSingle(),
    adminClient.from('users').select('id').ilike('personal_email', personalEmail).maybeSingle(),
    findAuthEmail(adminClient, personalEmail),
  ]);
  if (clinicConflict.error || personalConflict.error || authConflict.error) return fail('STAFF_VALIDATION_FAILED', 500);
  if (clinicConflict.data) return fail('CLINIC_EMAIL_ALREADY_EXISTS', 409);
  if (personalConflict.data) return fail('PERSONAL_EMAIL_ALREADY_EXISTS', 409);
  if (authConflict.exists) return fail('AUTH_EMAIL_ALREADY_EXISTS', 409);

  const { data: createdAuth, error: createAuthError } = await adminClient.auth.admin.createUser({
    email: personalEmail, password, email_confirm: true,
  });
  if (createAuthError || !createdAuth.user) {
    return fail(authEmailConflict(createAuthError) ? 'AUTH_EMAIL_ALREADY_EXISTS' : 'AUTH_ACCOUNT_CREATION_FAILED', authEmailConflict(createAuthError) ? 409 : 500);
  }

  const { data: createdUser, error: applicationError } = await adminClient.rpc('create_admin_managed_staff', {
    p_supabase_user_id: createdAuth.user.id,
    p_full_name: fullName,
    p_clinic_email: clinicEmail,
    p_personal_email: personalEmail,
    p_role: role,
    p_phone: phone || null,
    p_specialization: role === 'doctor' ? specialization : null,
  });
  if (applicationError || !createdUser) {
    // Resolve an ambiguous RPC transport failure before compensating a completed insert.
    const { data: linkedUser, error: linkedLookupError } = await adminClient.from('users')
      .select('id, full_name, email, role, phone, specialization, is_active, approved_at, supabase_user_id')
      .eq('supabase_user_id', createdAuth.user.id).maybeSingle();
    if (linkedLookupError) return fail('ACCOUNT_CREATION_STATE_UNKNOWN', 500);
    if (linkedUser) {
      return reply({ user: {
        id: linkedUser.id, fullName: linkedUser.full_name, clinicEmail: linkedUser.email,
        role: linkedUser.role, phone: linkedUser.phone, specialization: linkedUser.specialization,
        isActive: linkedUser.is_active, approvedAt: linkedUser.approved_at, isLinked: true,
      } }, 201);
    }
    // A concurrent request may have won either normalized application-email
    // constraint after our precheck. Resolve the safe conflict code before cleanup.
    const [clinicRace, personalRace] = await Promise.all([
      adminClient.from('users').select('id').ilike('email', clinicEmail).maybeSingle(),
      adminClient.from('users').select('id').ilike('personal_email', personalEmail).maybeSingle(),
    ]);
    const { error: rollbackError } = await adminClient.auth.admin.deleteUser(createdAuth.user.id);
    if (rollbackError) {
      console.error('[ADMIN_CREATE_USER] COMPENSATION_FAILED');
      return fail('ACCOUNT_CREATION_COMPENSATION_FAILED', 500);
    }
    if (!clinicRace.error && clinicRace.data) return fail('CLINIC_EMAIL_ALREADY_EXISTS', 409);
    if (!personalRace.error && personalRace.data) return fail('PERSONAL_EMAIL_ALREADY_EXISTS', 409);
    return fail('APPLICATION_ACCOUNT_CREATION_FAILED', applicationError?.code === '23505' ? 409 : 500);
  }
  return reply({ user: createdUser }, 201);
});
