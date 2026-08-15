import { apiRequest } from './httpClient.js';
import { getSupabaseClient } from '../lib/supabaseClient.js';

export const listAppointmentConditions = () => apiRequest('/appointment-conditions');
export const createAppointmentCondition = (name) => apiRequest('/appointment-conditions', { method: 'POST', body: { name } });

export class SymptomApiError extends Error {
  constructor(message, { code = 'SYMPTOM_RPC_FAILED', kind = 'transport', cause } = {}) {
    super(message, { cause });
    this.name = 'SymptomApiError';
    this.code = code;
    this.kind = kind;
  }
}

const symptomRpcError = (error, operation) => {
  if (error?.code === '42501') {
    return new SymptomApiError('You are not authorized to access clinical symptoms.', {
      code: 'SYMPTOM_FORBIDDEN', kind: 'authorization', cause: error,
    });
  }
  if (error?.code === '22023') {
    return new SymptomApiError('Symptom name is required.', {
      code: 'SYMPTOM_NAME_REQUIRED', kind: 'validation', cause: error,
    });
  }
  return new SymptomApiError(
    operation === 'create'
      ? 'The symptom could not be saved to the clinic database.'
      : 'Clinical symptoms could not be loaded from the clinic database.',
    { code: 'SYMPTOM_RPC_FAILED', kind: 'transport', cause: error },
  );
};

export function createSymptomService({ supabaseClient } = {}) {
  const client = () => supabaseClient || getSupabaseClient();

  return {
    async listSymptoms() {
      const { data, error } = await client().rpc('list_active_symptoms');
      if (error) throw symptomRpcError(error, 'list');
      return data || [];
    },

    async createSymptom(symptom) {
      const { data, error } = await client().rpc('create_or_reactivate_symptom', {
        p_name: symptom?.name,
      });
      if (error) throw symptomRpcError(error, 'create');
      return Array.isArray(data) ? data[0] : data;
    },
  };
}

const symptomService = createSymptomService();

export const listSymptoms = symptomService.listSymptoms;
export const createSymptom = symptomService.createSymptom;
