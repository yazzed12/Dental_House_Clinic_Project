import { getSupabaseClient } from '../lib/supabaseClient.js';

export class ProfileApiError extends Error {
  constructor(message, { code = 'PROFILE_RPC_FAILED', cause } = {}) {
    super(message, { cause }); this.name = 'ProfileApiError'; this.code = code;
  }
}

const profileError = error => {
  const mapping = {
    '42501': ['PROFILE_FORBIDDEN', 'You are not authorized to update this profile.'],
    '22023': ['PROFILE_INVALID', 'Check the entered profile information.'],
    P4031: ['PROFILE_NOT_FOUND', 'Your application profile could not be found.'],
  };
  const [code, message] = mapping[error?.code] || ['PROFILE_RPC_FAILED', 'The profile request could not be completed.'];
  return new ProfileApiError(message, { code, cause: error });
};

export function createProfileService({ supabaseClient } = {}) {
  const client = () => supabaseClient || getSupabaseClient();
  const rpc = async (name, args) => { const { data, error } = await client().rpc(name, args); if (error) throw profileError(error); return Array.isArray(data) ? data[0] : data; };
  return {
    getCurrentProfile: () => rpc('get_current_app_profile'),
    updateCurrentProfile: ({ fullName, phone, specialization }) => rpc('update_current_app_profile', {
      p_full_name: fullName, p_phone: phone || null, p_specialization: specialization ?? null,
    }),
    updatePassword: async password => {
      const { data, error } = await client().auth.updateUser({ password });
      if (error) throw new ProfileApiError(error.message || 'Password could not be updated.', { code: 'PASSWORD_UPDATE_FAILED', cause: error });
      return data;
    },
  };
}

const service = createProfileService();
export const getCurrentProfile = service.getCurrentProfile;
export const updateCurrentProfile = service.updateCurrentProfile;
export const updatePassword = service.updatePassword;
