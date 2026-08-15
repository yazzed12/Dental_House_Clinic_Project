import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { createAuthService } from './authService.js';

function createMockSupabaseClient(responses = {}) {
  const calls = {
    invoke: [],
    rpc: [],
    setSession: [],
    from: [],
    sequence: [],
  };
  let authStateCallback;
  return {
    calls,
    functions: {
      async invoke(funcName, { body }) {
        assert.equal(funcName, 'login');
        calls.invoke.push(body);
        if (responses.invokeError) return { data: null, error: responses.invokeError };
        if (responses.invokeData) return { data: responses.invokeData, error: null };

        if (body.clinic_email === 'receptionist1@receptionist.com' && body.password === 'validpass') {
          return {
            data: {
              access_token: 'mock-access-token',
              refresh_token: 'mock-refresh-token',
              expires_in: 3600,
              token_type: 'bearer',
            },
            error: null,
          };
        }
        return { data: { error: 'Invalid login credentials' }, error: null };
      },
    },
    auth: {
      async setSession({ access_token, refresh_token }) {
        calls.sequence.push('setSession');
        calls.setSession.push({ access_token, refresh_token });
        if (responses.setSessionError) return { data: null, error: responses.setSessionError };
        return {
          data: {
            session: {
              access_token,
              refresh_token,
              user: { id: responses.userId || '09f043e8-493f-4a25-9f18-a89fdcc93437' },
            },
          },
          error: null,
        };
      },
      async signOut() {
        return { error: null };
      },
      async getSession() {
        return { data: { session: responses.session || null }, error: null };
      },
      onAuthStateChange(callback) {
        authStateCallback = callback;
        return { data: { subscription: { unsubscribe() {} } } };
      },
    },
    emitAuthState(event, session) {
      authStateCallback?.(event, session);
    },
    async rpc(functionName) {
      calls.sequence.push(`rpc:${functionName}`);
      calls.rpc.push(functionName);
      assert.equal(functionName, 'get_current_app_profile');
      if (responses.profileError) return { data: null, error: responses.profileError };
      if (responses.profileData === null) return { data: [], error: null };
      return {
        data: [responses.profileData || {
          id: 'user-rec-1',
          full_name: 'Receptionist One',
          role: 'receptionist',
          email: 'receptionist1@receptionist.com',
          phone: null,
          specialization: null,
          supabase_user_id: responses.userId || '09f043e8-493f-4a25-9f18-a89fdcc93437',
        }],
        error: null,
      };
    },
    from(table) {
      calls.from.push(table);
      throw new Error(`Unexpected direct table read: ${table}`);
    },
  };
}

test('authService does not expose service-role secret or fetch personal email on client', async () => {
  const source = await readFile(new URL('./authService.js', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /service_role|SUPABASE_SERVICE_ROLE_KEY/i);
  assert.doesNotMatch(source, /personal_email/);
  assert.match(source, /functions\.invoke\('login'/);
  assert.match(source, /rpc\('get_current_app_profile'\)/);
  assert.doesNotMatch(source, /\.from\('users'\)/);
});

test('browser Supabase client persists and refreshes the session installed by setSession', async () => {
  const source = await readFile(new URL('../lib/supabaseClient.js', import.meta.url), 'utf8');
  assert.match(source, /persistSession:\s*true/);
  assert.match(source, /autoRefreshToken:\s*true/);
});

test('Edge Function code enforces strict credential separation and sanitized reason-code logging', async () => {
  const source = await readFile(new URL('../../supabase/functions/login/index.ts', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /SUPABASE_ANON_KEY \|\| serviceRoleKey/);
  assert.match(source, /AUTH_BRIDGE_USER_NOT_ELIGIBLE/);
  assert.match(source, /AUTH_BRIDGE_PASSWORD_AUTH_FAILED/);
  assert.match(source, /AUTH_BRIDGE_IDENTITY_MISMATCH/);
  assert.match(source, /AUTH_BRIDGE_CONFIG_ERROR/);
});

test('signIn successfully routes clinic email to Edge Function and establishes session', async () => {
  const client = createMockSupabaseClient();
  const service = createAuthService({ provider: 'supabase', supabaseClient: client });

  const user = await service.signIn('receptionist1@receptionist.com', 'validpass', 'receptionist');
  assert.equal(user.id, 'user-rec-1');
  assert.equal(user.role, 'receptionist');
  assert.equal(user.email, 'receptionist1@receptionist.com');
  assert.deepEqual(client.calls.setSession, [{
    access_token: 'mock-access-token',
    refresh_token: 'mock-refresh-token',
  }]);
  assert.deepEqual(client.calls.invoke, [{
    clinic_email: 'receptionist1@receptionist.com',
    password: 'validpass',
    workspace: 'receptionist',
  }]);
  assert.deepEqual(client.calls.rpc, ['get_current_app_profile']);
  assert.deepEqual(client.calls.from, []);
  assert.deepEqual(client.calls.sequence, [
    'setSession',
    'rpc:get_current_app_profile',
  ]);
});

test('signIn fails with generic Invalid login credentials on invalid credentials', async () => {
  const client = createMockSupabaseClient();
  const service = createAuthService({ provider: 'supabase', supabaseClient: client });

  await assert.rejects(
    service.signIn('receptionist1@receptionist.com', 'wrongpass'),
    /Invalid login credentials/
  );
});

test('signIn fails with generic error on unknown clinic email', async () => {
  const client = createMockSupabaseClient();
  const service = createAuthService({ provider: 'supabase', supabaseClient: client });

  await assert.rejects(
    service.signIn('unknown@clinic.com', 'validpass'),
    /Invalid login credentials/
  );
});

test('signIn enforces active and approved gating in application profile resolution', async () => {
  const client = createMockSupabaseClient({
    profileData: null,
  });
  const service = createAuthService({ provider: 'supabase', supabaseClient: client });

  await assert.rejects(
    service.signIn('receptionist1@receptionist.com', 'validpass'),
    /No linked application profile/
  );
});

test('signIn enforces identity UUID match between Auth user and public.users', async () => {
  const client = createMockSupabaseClient({
    userId: 'mismatched-uuid-1111',
    profileData: {
      id: 'user-rec-1',
      full_name: 'Mismatched User',
      role: 'receptionist',
      email: 'receptionist1@receptionist.com',
      supabase_user_id: '09f043e8-493f-4a25-9f18-a89fdcc93437',
    },
  });
  const service = createAuthService({ provider: 'supabase', supabaseClient: client });

  await assert.rejects(
    service.signIn('receptionist1@receptionist.com', 'validpass'),
    /Application identity link mismatch/
  );
});

test('selected workspace is sent to the trusted login bridge for server-side matching', async () => {
  const client = createMockSupabaseClient();
  const service = createAuthService({ provider: 'supabase', supabaseClient: client });

  await service.signIn('receptionist1@receptionist.com', 'validpass', 'admin');
  assert.equal(client.calls.invoke[0].workspace, 'admin');
});

test('auth state sequencing drops a stale profile result after logout', async () => {
  let releaseProfile;
  const client = createMockSupabaseClient();
  client.rpc = async () => new Promise((resolve) => {
    releaseProfile = () => resolve({
      data: [{
        id: 'stale-user',
        full_name: 'Stale User',
        role: 'doctor',
        email: 'stale@doctor.com',
        supabase_user_id: 'stale-auth-id',
      }],
      error: null,
    });
  });
  const service = createAuthService({ provider: 'supabase', supabaseClient: client });
  const observed = [];
  service.onAuthStateChange((nextUser) => observed.push(nextUser));

  client.emitAuthState('SIGNED_IN', { user: { id: 'stale-auth-id' } });
  client.emitAuthState('SIGNED_OUT', null);
  await Promise.resolve();
  releaseProfile();
  await Promise.resolve();
  await Promise.resolve();

  assert.deepEqual(observed, [null]);
});

test('legacy provider signIn operates unchanged', async () => {
  const mockFetch = async () => ({
    ok: true,
    json: async () => ({ access_token: 'legacy-token-123' }),
  });
  let profileFetched = false;
  const mockFetchProfile = async (url) => {
    if (url.includes('/auth/me')) {
      profileFetched = true;
      return {
        ok: true,
        json: async () => ({
          id: 'legacy-1',
          full_name: 'Legacy Admin',
          role: 'admin',
          email: 'admin@admin.com',
        }),
      };
    }
    return mockFetch(url);
  };

  const service = createAuthService({
    provider: 'legacy',
    fetchImpl: mockFetchProfile,
    apiUrl: 'http://localhost:8000/api',
  });

  const user = await service.signIn('admin@admin.com', 'password123');
  assert.equal(user.role, 'admin');
  assert.equal(profileFetched, true);
});
