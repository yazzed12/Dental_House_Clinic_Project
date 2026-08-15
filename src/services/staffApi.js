import { apiRequest } from './httpClient.js';
import { readRuntimeConfig } from '../config/runtime.js';
import { getSupabaseClient } from '../lib/supabaseClient.js';

const mapDoctorSelector = (doctor) => ({
  id: doctor.id,
  name: doctor.full_name,
  specialization: doctor.specialization,
});

export function createDoctorListService({
  provider = readRuntimeConfig().authProvider,
  supabaseClient,
  legacyRequest = apiRequest,
} = {}) {
  if (provider === 'legacy') {
    return () => legacyRequest('/doctors');
  }
  if (provider !== 'supabase') {
    throw new Error(`Unsupported Auth provider: ${provider}`);
  }

  return async () => {
    const client = supabaseClient || getSupabaseClient();
    const { data, error } = await client.rpc('get_eligible_doctors');
    if (error) throw new Error(error.message || 'Failed to fetch Doctors');
    return (data || []).map(mapDoctorSelector);
  };
}

export const listDoctors = createDoctorListService();
export const listReceptionists = () => apiRequest('/receptionists');
export const createStaff = (staff) => apiRequest('/staff', { method: 'POST', body: staff });
export const updateStaff = (id, updates) => apiRequest(`/staff/${id}`, { method: 'PUT', body: updates });
export const deleteStaff = (id) => apiRequest(`/staff/${id}`, { method: 'DELETE' });
