import { getSupabaseClient } from '../lib/supabaseClient.js';

export class ClinicSettingsApiError extends Error {
  constructor(message, { code = 'CLINIC_SETTINGS_RPC_FAILED', cause } = {}) {
    super(message, { cause }); this.name = 'ClinicSettingsApiError'; this.code = code;
  }
}

const settingsError = error => {
  const mapping = {
    '42501': ['CLINIC_SETTINGS_FORBIDDEN', 'You are not authorized to access Clinic Settings.'],
    '22023': ['CLINIC_SETTINGS_INVALID', 'Check the entered Clinic Information.'],
    P4030: ['CLINIC_SETTINGS_NOT_FOUND', 'Clinic Information could not be found.'],
  };
  const [code, message] = mapping[error?.code] || ['CLINIC_SETTINGS_RPC_FAILED', 'Clinic Information could not be loaded.'];
  return new ClinicSettingsApiError(message, { code, cause: error });
};

export function createClinicSettingsService({ supabaseClient } = {}) {
  const client = () => supabaseClient || getSupabaseClient();
  const rpc = async (name, args) => { const { data, error } = await client().rpc(name, args); if (error) throw settingsError(error); return data; };
  return {
    getClinicSettings: () => rpc('get_clinic_settings'),
    updateClinicSettings: ({ name, email, phone, address }) => rpc('update_clinic_settings', {
      p_name: name, p_email: email || null, p_phone: phone || null, p_address: address || null,
    }),
  };
}

const service = createClinicSettingsService();
export const getClinicSettings = service.getClinicSettings;
export const updateClinicSettings = service.updateClinicSettings;
