/** Current-consultation and read-only patient-history transport. */
import { API_URL } from '../config/api.js';
import { readRuntimeConfig } from '../config/runtime.js';
import { getSupabaseClient } from '../lib/supabaseClient.js';

export class ConsultationApiError extends Error {
  constructor(message, { code = 'CONSULTATION_ERROR', kind = 'load', status, cause } = {}) {
    super(message, { cause });
    this.name = 'ConsultationApiError';
    this.code = code;
    this.kind = kind;
    if (status !== undefined) this.status = status;
  }
}

const errorFromRpc = (error, operation) => {
  const code = error?.code;
  if (code === 'P2001') {
    return new ConsultationApiError('Patient record not found.', {
      code: 'PATIENT_NOT_FOUND', kind: 'patient-not-found', status: 404, cause: error,
    });
  }
  if (code === 'P2101') {
    return new ConsultationApiError('Patient record not found.', {
      code: 'CONSULTATION_HISTORY_PATIENT_NOT_FOUND', kind: 'patient-not-found', status: 404, cause: error,
    });
  }
  if (code === 'P2002') {
    return new ConsultationApiError('No eligible current appointment exists for this consultation.', {
      code: 'NO_CURRENT_APPOINTMENT', kind: 'no-current-appointment', status: 404, cause: error,
    });
  }
  if (code === '42501') {
    return new ConsultationApiError('You are not authorized to access this consultation.', {
      code: 'CONSULTATION_FORBIDDEN', kind: 'authorization', status: 403, cause: error,
    });
  }
  if (code === '40001') {
    return new ConsultationApiError(
      'CONFLICT: Another clinician updated this consultation. Your unsaved changes are preserved.',
      { code: 'VERSION_CONFLICT', kind: 'conflict', status: 409, cause: error },
    );
  }
  if (code === 'P2003') {
    return new ConsultationApiError('The consultation does not belong to the selected appointment.', {
      code: 'CONSULTATION_OWNERSHIP_MISMATCH', kind: 'authorization', status: 403, cause: error,
    });
  }
  if (code === '22023') {
    return new ConsultationApiError('The consultation payload is invalid.', {
      code: 'CONSULTATION_INVALID', kind: operation, status: 400, cause: error,
    });
  }
  return new ConsultationApiError(
    operation === 'save'
      ? 'The consultation could not be saved to the clinic database.'
      : operation === 'history'
        ? 'Consultation history could not be loaded from the clinic database.'
        : 'The consultation could not be loaded from the clinic database.',
    {
      code: operation === 'save'
        ? 'CONSULTATION_SAVE_FAILED'
        : operation === 'history' ? 'CONSULTATION_HISTORY_FAILED' : 'CONSULTATION_LOAD_FAILED',
      kind: operation,
      cause: error,
    },
  );
};

const legacyAuthHeaders = () => ({
  'Content-Type': 'application/json',
  Authorization: `Bearer ${localStorage.getItem('clinic_token')}`,
});

const legacySaveError = async (response) => {
  let detail = '';
  try {
    const body = await response.json();
    detail = typeof body?.detail === 'string' ? body.detail : '';
  } catch {
    // Preserve the status-based message if the legacy backend has no JSON body.
  }
  return new ConsultationApiError(
    response.status === 409
      ? `CONFLICT: ${detail || 'Another doctor has updated this record. Please refresh.'}`
      : `Save failed with ${response.status}${detail ? `: ${detail}` : ''}`,
    {
      code: response.status === 409 ? 'VERSION_CONFLICT' : 'CONSULTATION_SAVE_FAILED',
      kind: response.status === 409 ? 'conflict' : 'save',
      status: response.status,
    },
  );
};

const firstResult = (data) => (Array.isArray(data) ? data[0] : data);
const scopedKey = (patientId, sessionScope = '') => `${sessionScope || 'default'}:${patientId}`;

export function createConsultationService({
  provider = readRuntimeConfig().authProvider,
  supabaseClient,
  legacyFetch,
} = {}) {
  const consultationLoads = new Map();
  const consultationSaveQueues = new Map();
  const client = () => supabaseClient || getSupabaseClient();
  const fetchLegacy = (...args) => (legacyFetch || globalThis.fetch)(...args);

  if (provider !== 'legacy' && provider !== 'supabase') {
    throw new Error(`Unsupported Auth provider: ${provider}`);
  }

  const queueFor = (patientId, sessionScope) => {
    const key = scopedKey(patientId, sessionScope);
    if (!consultationSaveQueues.has(key)) {
      consultationSaveQueues.set(key, {
        tail: Promise.resolve(), pending: 0, version: null,
        dentalStateVersion: null, blocked: false, authoritative: null,
      });
    }
    return consultationSaveQueues.get(key);
  };

  const primeConsultationSaveQueue = (
    patientId, version, dentalStateVersion = 0, sessionScope,
  ) => {
    const queue = queueFor(patientId, sessionScope);
    if (queue.pending === 0) {
      queue.version = version;
      queue.dentalStateVersion = dentalStateVersion;
      queue.blocked = false;
      queue.authoritative = null;
    }
  };

  const resumeConsultationSaveQueue = (
    patientId, version, dentalStateVersion = 0, sessionScope,
  ) => {
    const queue = queueFor(patientId, sessionScope);
    queue.version = version;
    queue.dentalStateVersion = dentalStateVersion;
    queue.blocked = false;
    queue.authoritative = null;
  };

  const fetchConsultationRequest = async (patientId) => {
    if (provider === 'supabase') {
      const { data, error } = await client().rpc('get_or_initialize_consultation', {
        p_patient_id: patientId,
      });
      if (error) throw errorFromRpc(error, 'load');
      const current = firstResult(data);
      if (!current?.consultationId) return current;
      const { data: history, error: historyError } = await client().rpc(
        'get_patient_consultation_history',
        { p_patient_id: patientId },
      );
      if (historyError) throw errorFromRpc(historyError, 'load');
      const historyItem = (history || []).find(
        item => String(item.consultationId) === String(current.consultationId),
      );
      return {
        ...current,
        clinicalFindings: historyItem?.clinicalFindings ?? null,
      };
    }

    let response;
    try {
      response = await fetchLegacy(`${API_URL}/consultations/${patientId}`, {
        headers: legacyAuthHeaders(),
      });
    } catch (error) {
      throw new ConsultationApiError('The consultation could not be loaded from the clinic database.', {
        code: 'CONSULTATION_LOAD_FAILED', kind: 'load', cause: error,
      });
    }
    if (response.status === 404) return null;
    if (response.status === 401) {
      throw new ConsultationApiError('Unauthorized: Please login again.', {
        code: 'CONSULTATION_FORBIDDEN', kind: 'authorization', status: 401,
      });
    }
    if (!response.ok) {
      throw new ConsultationApiError(`Server returned ${response.status}`, {
        code: 'CONSULTATION_LOAD_FAILED', kind: 'load', status: response.status,
      });
    }
    return response.json();
  };

  const fetchConsultation = (patientId, sessionScope) => {
    const key = scopedKey(patientId, sessionScope);
    const existing = consultationLoads.get(key);
    if (existing) return existing;
    const request = fetchConsultationRequest(patientId)
      .then((data) => {
        if (data) {
          primeConsultationSaveQueue(
            patientId, data.version ?? 0, data.dentalStateVersion ?? 0, sessionScope,
          );
        }
        return data;
      })
      .finally(() => consultationLoads.delete(key));
    consultationLoads.set(key, request);
    return request;
  };

  const saveConsultationRequest = async (
    patientId, toothData, version, sessionNote, dentalStateVersion, symptomsSnapshot,
    clinicalFindingsSnapshot,
  ) => {
    if (provider === 'supabase') {
      const { data, error } = await client().rpc('save_current_consultation', {
        p_patient_id: patientId,
        p_tooth_data: toothData,
        p_version: version,
        p_dental_state_version: dentalStateVersion,
        p_session_note: sessionNote ?? null,
        p_session_note_supplied: sessionNote !== undefined,
        p_symptoms_snapshot: symptomsSnapshot ?? [],
        p_symptoms_supplied: symptomsSnapshot !== undefined,
        p_clinical_findings_snapshot: clinicalFindingsSnapshot ?? null,
        p_clinical_findings_supplied: clinicalFindingsSnapshot !== undefined,
      });
      if (error) throw errorFromRpc(error, 'save');
      return firstResult(data);
    }

    const payload = { toothData, version };
    if (sessionNote !== undefined) payload.sessionNote = sessionNote;
    if (dentalStateVersion !== undefined) payload.dentalStateVersion = dentalStateVersion;
    if (symptomsSnapshot !== undefined) payload.symptoms = symptomsSnapshot;
    const response = await fetchLegacy(`${API_URL}/consultations/${patientId}`, {
      method: 'POST', headers: legacyAuthHeaders(), body: JSON.stringify(payload),
    });
    if (!response.ok) throw await legacySaveError(response);
    return response.json();
  };

  const saveConsultationToApi = (
    patientId, toothData, version = 1, sessionNote,
    dentalStateVersion = 0, sessionScope, symptomsSnapshot, clinicalFindingsSnapshot,
  ) => {
    const queue = queueFor(patientId, sessionScope);
    queue.pending += 1;
    const operation = queue.tail
      .catch(() => undefined)
      .then(async () => {
        if (queue.blocked) {
          const conflict = new ConsultationApiError(
            'CONFLICT: Saving is paused. Your unsaved changes are preserved; review and retry.',
            { code: 'VERSION_CONFLICT', kind: 'conflict', status: 409 },
          );
          conflict.authoritative = queue.authoritative;
          throw conflict;
        }
        const effectiveVersion = queue.version ?? version;
        const effectiveDentalStateVersion = queue.dentalStateVersion ?? dentalStateVersion;
        try {
          const result = await saveConsultationRequest(
            patientId, toothData, effectiveVersion, sessionNote, effectiveDentalStateVersion,
            symptomsSnapshot, clinicalFindingsSnapshot,
          );
          queue.version = result.version;
          queue.dentalStateVersion = result.dentalStateVersion ?? effectiveDentalStateVersion;
          queue.authoritative = null;
          return result;
        } catch (error) {
          if (error?.status === 409) {
            let authoritative = null;
            try {
              authoritative = await fetchConsultationRequest(patientId);
            } catch {
              // The original conflict remains actionable if refresh also fails.
            }
            if (authoritative) {
              queue.version = authoritative.version ?? effectiveVersion;
              queue.dentalStateVersion = authoritative.dentalStateVersion ?? effectiveDentalStateVersion;
            }
            queue.authoritative = authoritative;
            queue.blocked = true;
            error.authoritative = authoritative;
          }
          throw error;
        }
      })
      .finally(() => { queue.pending -= 1; });
    queue.tail = operation;
    return operation;
  };

  const invalidateSessionState = () => {
    consultationLoads.clear();
    consultationSaveQueues.clear();
  };

  const rollbackOnlyError = (feature) => new ConsultationApiError(
    `${feature} has not been migrated to the Supabase consultation slice.`,
    { code: 'CONSULTATION_SLICE_NOT_MIGRATED', kind: 'load' },
  );

  const fetchConsultationHistory = async (patientId) => {
    if (provider === 'supabase') {
      const { data, error } = await client().rpc('get_patient_consultation_history', {
        p_patient_id: patientId,
      });
      if (error) throw errorFromRpc(error, 'history');
      return data || [];
    }
    const response = await fetchLegacy(`${API_URL}/consultations/${patientId}/history`, {
      headers: legacyAuthHeaders(),
    });
    if (!response.ok) throw new Error(`History request failed with ${response.status}`);
    return response.json();
  };

  const updateToothOnApi = async (patientId, toothId, updates, version = 1) => {
    if (provider === 'supabase') throw rollbackOnlyError('Single-tooth updates');
    const response = await fetchLegacy(
      `${API_URL}/consultations/${patientId}/tooth/${toothId}`,
      {
        method: 'PATCH', headers: legacyAuthHeaders(),
        body: JSON.stringify({ updates, version }),
      },
    );
    if (response.status === 409) throw new Error('CONFLICT: Tooth record was modified. Please refresh.');
    if (!response.ok) throw new Error(`Update failed with ${response.status}`);
    return response.json();
  };

  return {
    fetchConsultation,
    primeConsultationSaveQueue,
    resumeConsultationSaveQueue,
    saveConsultationToApi,
    invalidateSessionState,
    fetchConsultationHistory,
    updateToothOnApi,
  };
}

const consultationService = createConsultationService();

export const fetchConsultation = consultationService.fetchConsultation;
export const primeConsultationSaveQueue = consultationService.primeConsultationSaveQueue;
export const resumeConsultationSaveQueue = consultationService.resumeConsultationSaveQueue;
export const saveConsultationToApi = consultationService.saveConsultationToApi;
export const invalidateConsultationSessionState = consultationService.invalidateSessionState;
export const fetchConsultationHistory = consultationService.fetchConsultationHistory;
export const updateToothOnApi = consultationService.updateToothOnApi;
export const resetConsultationApiStateForTests = consultationService.invalidateSessionState;
