import { getSupabaseClient } from '../lib/supabaseClient.js';

export class FormatClinicError extends Error {
  constructor(message, code = 'FORMAT_CLINIC_FAILED') {
    super(message);
    this.name = 'FormatClinicError';
    this.code = code;
  }
}

export async function formatClinicData() {
  const { data, error } = await getSupabaseClient().rpc('format_clinic_data');
  if (error || data?.formatted !== true) {
    const raw = `${error?.code || ''} ${error?.message || ''}`;
    if (/AUTHORIZATION|42501/i.test(raw)) {
      throw new FormatClinicError('Admin authorization is required.', 'FORMAT_CLINIC_AUTHORIZATION_DENIED');
    }
    throw new FormatClinicError('Clinic data could not be formatted safely. No account settings were changed.');
  }
  return data;
}
