import { apiRequest } from './httpClient.js';
import { readRuntimeConfig } from '../config/runtime.js';
import { getSupabaseClient } from '../lib/supabaseClient.js';

export class ConsultationHistoryApiError extends Error {
  constructor(message, { code = 'CONSULTATION_HISTORY_FAILED', kind = 'transport', status, cause } = {}) {
    super(message, { cause });
    this.name = 'ConsultationHistoryApiError';
    this.code = code;
    this.kind = kind;
    if (status !== undefined) this.status = status;
  }
}

const historyError = error => {
  if (error?.code === '42501') {
    return new ConsultationHistoryApiError('You are not authorized to view consultation history.', {
      code: 'CONSULTATION_HISTORY_FORBIDDEN', kind: 'authorization', status: 403, cause: error,
    });
  }
  return new ConsultationHistoryApiError('Consultation history could not be loaded.', { cause: error });
};

export const normalizeConsultationHistoryItem = item => ({
  ...item,
  labItems: Array.isArray(item?.labItems) ? item.labItems : [],
  labNote: typeof item?.labNote === 'string' ? item.labNote : null,
  prescription: item?.prescription?.status === 'approved'
    ? { ...item.prescription, items: Array.isArray(item.prescription.items) ? item.prescription.items : [] }
    : null,
});

export function createConsultationHistoryService({
  provider = readRuntimeConfig().authProvider,
  supabaseClient,
  legacyRequest = apiRequest,
} = {}) {
  if (provider === 'legacy') {
    return { listDoctorConsultationHistory: () => legacyRequest('/doctor/consultations/history') };
  }
  if (provider !== 'supabase') throw new Error(`Unsupported Auth provider: ${provider}`);
  return {
    listDoctorConsultationHistory: async () => {
      const client = supabaseClient || getSupabaseClient();
      const { data, error } = await client.rpc('list_doctor_consultation_history');
      if (error) throw historyError(error);
      return (data || []).map(normalizeConsultationHistoryItem);
    },
  };
}

const consultationHistoryService = createConsultationHistoryService();
export const listDoctorConsultationHistory = consultationHistoryService.listDoctorConsultationHistory;
