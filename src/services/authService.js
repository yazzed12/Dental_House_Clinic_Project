import { API_URL } from '../config/api.js';
import { readRuntimeConfig } from '../config/runtime.js';
import { getSupabaseClient } from '../lib/supabaseClient.js';

export class ApplicationAccessDeniedError extends Error {
  constructor(message = 'Application access is not approved.') {
    super(message);
    this.name = 'ApplicationAccessDeniedError';
  }
}

function toApplicationUser(profile) {
  return {
    name: profile.full_name,
    role: profile.role,
    id: profile.id,
    email: profile.email,
    phone: profile.phone,
    specialization: profile.specialization,
  };
}

export function createAuthService({
  provider = readRuntimeConfig().authProvider,
  apiUrl = API_URL,
  fetchImpl = globalThis.fetch,
  storage = typeof window !== 'undefined' ? window.localStorage : undefined,
  supabaseClient,
} = {}) {
  if (provider === 'legacy') {
    const fetchProfile = async (token) => {
      if (!token) return null;
      const response = await fetchImpl(`${apiUrl}/auth/me`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!response.ok) throw new ApplicationAccessDeniedError('Legacy session denied.');
      return toApplicationUser(await response.json());
    };

    return {
      provider,
      async loadApplicationUser() {
        try {
          return await fetchProfile(storage?.getItem('clinic_token'));
        } catch (error) {
          storage?.removeItem('clinic_token');
          throw error;
        }
      },
      async signIn(identifier, password) {
        const params = new URLSearchParams();
        params.append('username', identifier);
        params.append('password', password);
        const response = await fetchImpl(`${apiUrl}/auth/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: params,
        });
        if (!response.ok) throw new Error('Login failed');
        const data = await response.json();
        storage?.setItem('clinic_token', data.access_token);
        return fetchProfile(data.access_token);
      },
      async register(payload) {
        const response = await fetchImpl(`${apiUrl}/auth/register`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        const data = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(data.detail || 'Registration failed');
        return data;
      },
      async verify(payload) {
        const response = await fetchImpl(`${apiUrl}/auth/verify`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        const data = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(data.detail || 'Verification failed');
        storage?.setItem('clinic_token', data.access_token);
        return fetchProfile(data.access_token);
      },
      async requestPasswordReset(clinicEmail) {
        const response = await fetchImpl(`${apiUrl}/auth/forgot-password`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ clinic_email: clinicEmail }),
        });
        const data = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(data.detail || 'Failed to request recovery code');
        return data;
      },
      async resetPassword(payload) {
        const response = await fetchImpl(`${apiUrl}/auth/reset-password`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        const data = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(data.detail || 'Password reset failed');
        return data;
      },
      async signOut() {
        storage?.removeItem('clinic_token');
      },
      onAuthStateChange() {
        return () => {};
      },
    };
  }

  if (provider !== 'supabase') {
    throw new Error(`Unsupported Auth provider: ${provider}`);
  }

  const client = supabaseClient || getSupabaseClient();
  let authStateGeneration = 0;
  const resolveApplicationProfile = async (session) => {
    if (!session?.user?.id) return null;
    const { data, error } = await client.rpc('get_current_app_profile');
    const profile = Array.isArray(data) ? data[0] : data;

    if (error || !profile) {
      throw new ApplicationAccessDeniedError('No linked application profile.');
    }
    if (String(profile.supabase_user_id) !== String(session.user.id)) {
      throw new ApplicationAccessDeniedError('Application identity link mismatch.');
    }
    return toApplicationUser(profile);
  };

  return {
    provider,
    async loadApplicationUser() {
      const { data, error } = await client.auth.getSession();
      if (error) throw error;
      try {
        return await resolveApplicationProfile(data.session);
      } catch (accessError) {
        await client.auth.signOut();
        throw accessError;
      }
    },
    async signIn(clinicEmail, password, workspace) {
      // Invoke trusted Edge Function login bridge with clinic email
      const { data: fnData, error: fnError } = await client.functions.invoke('login', {
        body: { clinic_email: clinicEmail, password, workspace },
      });

      if (fnError || !fnData || fnData.error || !fnData.access_token || !fnData.refresh_token) {
        const message = fnData?.error || fnError?.message || 'Invalid login credentials';
        throw new Error(message);
      }

      // Install tokens to establish active browser session
      const { data: sessionData, error: sessionError } = await client.auth.setSession({
        access_token: fnData.access_token,
        refresh_token: fnData.refresh_token,
      });

      if (sessionError) throw sessionError;

      try {
        return await resolveApplicationProfile(sessionData.session);
      } catch (accessError) {
        await client.auth.signOut();
        throw accessError;
      }
    },
    async signOut() {
      authStateGeneration += 1;
      const { error } = await client.auth.signOut();
      if (error) throw error;
    },
    async register() {
      throw new Error('Supabase registration is not enabled in S2.');
    },
    async verify() {
      throw new Error('Supabase verification is not enabled in S2.');
    },
    async requestPasswordReset() {
      throw new Error('Supabase password recovery is not enabled in S2.');
    },
    async resetPassword() {
      throw new Error('Supabase password recovery is not enabled in S2.');
    },
    onAuthStateChange(callback) {
      const { data } = client.auth.onAuthStateChange((_event, session) => {
        const generation = ++authStateGeneration;
        Promise.resolve(resolveApplicationProfile(session))
          .then((nextUser) => {
            if (generation === authStateGeneration) callback(nextUser);
          })
          .catch(() => {
            if (generation === authStateGeneration) callback(null);
          });
      });
      return () => data.subscription.unsubscribe();
    },
  };
}

export const authService = createAuthService();
