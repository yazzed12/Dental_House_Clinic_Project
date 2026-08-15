import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function genericAuthError(reasonCode: string, status = 400) {
  // Sanitized logging: Reason codes ONLY. Zero PII, emails, UUIDs, or credentials.
  console.error(`[AUTH_BRIDGE_FAILURE] ${reasonCode}`);
  return jsonResponse({ error: 'Invalid login credentials' }, status);
}

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return genericAuthError('AUTH_BRIDGE_METHOD_NOT_ALLOWED', 405);
  }

  // Input Size Guard: Limit payload body size to 10KB
  const contentLength = parseInt(req.headers.get('content-length') || '0', 10);
  if (contentLength > 10240) {
    return genericAuthError('AUTH_BRIDGE_PAYLOAD_TOO_LARGE');
  }

  let body: { clinic_email?: string; password?: string; workspace?: string };
  try {
    body = await req.json();
  } catch {
    return genericAuthError('AUTH_BRIDGE_MALFORMED_JSON');
  }

  const { clinic_email, password, workspace } = body;
  if (
    !clinic_email || typeof clinic_email !== 'string' ||
    !password || typeof password !== 'string' ||
    !workspace || typeof workspace !== 'string'
  ) {
    return genericAuthError('AUTH_BRIDGE_MISSING_FIELDS');
  }

  const normalizedClinicEmail = clinic_email.trim().toLowerCase();
  const normalizedWorkspace = workspace.trim().toLowerCase();
  if (!['doctor', 'admin', 'receptionist'].includes(normalizedWorkspace)) {
    return genericAuthError('AUTH_BRIDGE_WORKSPACE_INVALID');
  }

  // Environment Secrets: Strict separation of admin key (db lookup) and anon key (auth login)
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');

  // Strict check: Anon key must be explicitly provided (no fallback to service_role)
  if (!supabaseUrl || !serviceRoleKey || !anonKey) {
    console.error('[AUTH_BRIDGE_FAILURE] AUTH_BRIDGE_CONFIG_ERROR');
    return jsonResponse({ error: 'Authentication service temporarily unavailable' }, 500);
  }

  // Trusted Server-Side Admin Client (Service Role) for DB Profile Lookup
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Step 1: Look up active, approved application user by clinic email
  const { data: userProfile, error: dbError } = await adminClient
    .from('users')
    .select('id, email, personal_email, role, is_active, approved_at, supabase_user_id')
    .eq('email', normalizedClinicEmail)
    .maybeSingle();

  if (
    dbError ||
    !userProfile ||
    !userProfile.is_active ||
    !userProfile.approved_at ||
    !userProfile.supabase_user_id ||
    !userProfile.personal_email ||
    String(userProfile.role).toLowerCase() !== normalizedWorkspace
  ) {
    return genericAuthError('AUTH_BRIDGE_USER_NOT_ELIGIBLE');
  }

  // Step 2: Authenticate with Supabase Auth using personal_email + password via ANON KEY
  const authClient = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: authData, error: authError } = await authClient.auth.signInWithPassword({
    email: userProfile.personal_email,
    password,
  });

  if (authError || !authData?.session || !authData?.user) {
    return genericAuthError('AUTH_BRIDGE_PASSWORD_AUTH_FAILED');
  }

  // Step 3: Strict Identity Link Verification
  if (String(authData.user.id) !== String(userProfile.supabase_user_id)) {
    return genericAuthError('AUTH_BRIDGE_IDENTITY_MISMATCH');
  }

  // Step 4: Return minimal session token material to browser (Zero personal_email leakage)
  return jsonResponse({
    access_token: authData.session.access_token,
    refresh_token: authData.session.refresh_token,
    token_type: authData.session.token_type,
    expires_in: authData.session.expires_in,
  });
});
