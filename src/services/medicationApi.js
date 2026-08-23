import { apiRequest } from './httpClient.js';
import { readRuntimeConfig } from '../config/runtime.js';
import { getSupabaseClient } from '../lib/supabaseClient.js';

export class MedicationApiError extends Error {
  constructor(message, { code = 'MEDICATION_REQUEST_FAILED', status, cause } = {}) {
    super(message, { cause });
    this.name = 'MedicationApiError';
    this.code = code;
    if (status !== undefined) this.status = status;
  }
}

const rpcError = error => {
  const mapping = {
    '42501': ['PRESCRIPTION_FORBIDDEN', 403, 'You are not authorized to access this prescription.'],
    '40001': ['PRESCRIPTION_VERSION_CONFLICT', 409, 'The prescription changed elsewhere. Reload and review it again.'],
    '22023': ['MEDICATION_VALIDATION_FAILED', 400, error?.message || 'Medication or prescription data is invalid.'],
    P3401: ['MEDICATION_NOT_AVAILABLE', 400, 'This medication is no longer available for prescribing.'],
    P3402: ['PRESCRIPTION_CONSULTATION_NOT_FOUND', 404, 'Consultation not found.'],
    P3405: ['APPROVED_PRESCRIPTION_IMMUTABLE', 409, 'The approved prescription is read-only.'],
    P3406: ['PRESCRIPTION_REVIEW_REQUIRED', 409, 'Review and approve the prescription before finishing.'],
  };
  const [code, status, message] = mapping[error?.code]
    || ['MEDICATION_REQUEST_FAILED', undefined, error?.message || 'Medication request failed.'];
  return new MedicationApiError(message, { code, status, cause: error });
};

const pickFields = (value, fields) => {
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(fields
    .filter(field => Object.prototype.hasOwnProperty.call(value, field))
    .map(field => [field, value[field]]));
};

const MEDICATION_FIELDS = [
  'id', 'brandName', 'genericName', 'strength', 'dosageForm', 'route', 'category',
  'manufacturer', 'market', 'catalogScope', 'isCustom', 'verificationStatus',
  'sourceType', 'sourceName', 'sourceReference', 'sourceVersion', 'sourceRecordId',
];
const PRESCRIPTION_FIELDS = [
  'id', 'consultationId', 'patientId', 'doctorId', 'appointmentId', 'status',
  'version', 'approvedBy', 'approvedAt', 'createdAt', 'updatedAt',
];
const PRESCRIPTION_ITEM_FIELDS = [
  'id', 'medicationId', 'clinicalPresetId', 'doctorPresetId', 'position',
  'brandName', 'genericName', 'strength', 'dosageForm', 'route', 'dose',
  'frequency', 'duration', 'instructions', 'doctorNotes', 'sourceType',
  'sourceName', 'sourceReference', 'sourceVersion', 'sourceRecordId',
  'verificationStatus',
];
const CLINICAL_PRESET_FIELDS = [
  'id', 'dose', 'frequency', 'duration', 'instructions', 'clinicalContext',
  'presetVersion',
];
const DOCTOR_PRESET_FIELDS = [
  'id', 'dose', 'frequency', 'duration', 'instructions', 'doctorNotes',
];
const EFFECTIVE_PRESET_FIELDS = [
  'dose', 'frequency', 'duration', 'instructions', 'doctorNotes',
  'clinicalPresetId', 'doctorPresetId',
];

export const normalizeMedication = value => pickFields(value, MEDICATION_FIELDS);

export const normalizePrescriptionSnapshot = value => {
  if (!value || typeof value !== 'object') return value;
  return {
    ...pickFields(value, PRESCRIPTION_FIELDS),
    items: Array.isArray(value.items)
      ? value.items.map(item => pickFields(item, PRESCRIPTION_ITEM_FIELDS))
      : [],
  };
};

const normalizeEffectivePreset = value => {
  if (!value || typeof value !== 'object') return value;
  return {
    medication: normalizeMedication(value.medication),
    clinicalPreset: value.clinicalPreset == null
      ? null : pickFields(value.clinicalPreset, CLINICAL_PRESET_FIELDS),
    doctorPreset: value.doctorPreset == null
      ? null : pickFields(value.doctorPreset, DOCTOR_PRESET_FIELDS),
    effectivePreset: value.effectivePreset == null
      ? null : pickFields(value.effectivePreset, EFFECTIVE_PRESET_FIELDS),
  };
};

export function createMedicationService({
  provider = readRuntimeConfig().authProvider,
  supabaseClient,
  legacyRequest = apiRequest,
} = {}) {
  if (provider === 'legacy') {
    return {
      searchMedications: async (query, limit = 20) => {
        const data = await legacyRequest(`/medications?q=${encodeURIComponent(query)}&limit=${limit}`);
        return Array.isArray(data) ? data.map(normalizeMedication) : [];
      },
      getMedicationDetails: async id => normalizeMedication(await legacyRequest(`/medications/${id}`)),
      createCustomMedication: async medication => normalizeMedication(
        await legacyRequest('/medications/custom', { method: 'POST', body: medication }),
      ),
      getEffectiveMedicationPreset: async id => normalizeEffectivePreset(
        await legacyRequest(`/medications/${id}/effective-preset`),
      ),
      saveDoctorMedicationPreset: (id, preset) => legacyRequest(`/medications/${id}/doctor-preset`, { method: 'PUT', body: preset }),
      deleteDoctorMedicationPreset: id => legacyRequest(`/medications/${id}/doctor-preset`, { method: 'DELETE' }),
      getConsultationPrescription: async id => normalizePrescriptionSnapshot(
        await legacyRequest(`/consultations/${id}/prescription`),
      ),
      savePrescriptionDraft: async (id, expectedVersion, items) => normalizePrescriptionSnapshot(
        await legacyRequest(`/consultations/${id}/prescription/draft`, {
          method: 'PUT', body: { expectedVersion, items },
        }),
      ),
      approvePrescription: async (id, expectedVersion) => normalizePrescriptionSnapshot(
        await legacyRequest(`/prescriptions/${id}/approve`, {
          method: 'POST', body: { expectedVersion },
        }),
      ),
    };
  }
  if (provider !== 'supabase') throw new Error(`Unsupported Auth provider: ${provider}`);
  const client = () => supabaseClient || getSupabaseClient();
  const rpc = async (name, args) => {
    const { data, error } = await client().rpc(name, args);
    if (error) throw rpcError(error);
    return data;
  };
  return {
    searchMedications: async (query, limit = 20) => {
      const data = await rpc('search_dental_medications', { p_query: query, p_limit: limit });
      return Array.isArray(data) ? data.map(normalizeMedication) : [];
    },
    getMedicationDetails: async id => normalizeMedication(
      (await rpc('get_effective_medication_preset', { p_medication_id: id }))?.medication,
    ),
    createCustomMedication: async medication => normalizeMedication(await rpc('create_custom_medication', {
      p_brand_name: medication.brand_name, p_generic_name: medication.generic_name || null,
      p_strength: medication.strength, p_dosage_form: medication.dosage_form,
      p_route: medication.route, p_category: medication.category || null,
      p_manufacturer: medication.manufacturer || null,
    })),
    getEffectiveMedicationPreset: async id => normalizeEffectivePreset(
      await rpc('get_effective_medication_preset', { p_medication_id: id }),
    ),
    saveDoctorMedicationPreset: (id, preset) => rpc('upsert_doctor_medication_preset', {
      p_medication_id: id, p_dose: preset.dose || null, p_frequency: preset.frequency || null,
      p_duration: preset.duration || null, p_instructions: preset.instructions || null,
      p_doctor_notes: preset.doctorNotes || null,
    }),
    deleteDoctorMedicationPreset: id => rpc('delete_doctor_medication_preset', { p_medication_id: id }),
    getConsultationPrescription: async id => normalizePrescriptionSnapshot(
      await rpc('get_consultation_prescription', { p_consultation_id: id }),
    ),
    savePrescriptionDraft: async (id, expectedVersion, items) => normalizePrescriptionSnapshot(await rpc('save_prescription_draft', {
      p_consultation_id: id, p_expected_version: expectedVersion, p_items: items,
    })),
    approvePrescription: async (id, expectedVersion) => normalizePrescriptionSnapshot(await rpc('approve_prescription', {
      p_prescription_id: id, p_expected_version: expectedVersion,
    })),
  };
}

const medicationService = createMedicationService();
export const searchMedications = medicationService.searchMedications;
export const getMedicationDetails = medicationService.getMedicationDetails;
export const createCustomMedication = medicationService.createCustomMedication;
export const getEffectiveMedicationPreset = medicationService.getEffectiveMedicationPreset;
export const saveDoctorMedicationPreset = medicationService.saveDoctorMedicationPreset;
export const deleteDoctorMedicationPreset = medicationService.deleteDoctorMedicationPreset;
export const getConsultationPrescription = medicationService.getConsultationPrescription;
export const savePrescriptionDraft = medicationService.savePrescriptionDraft;
export const approvePrescription = medicationService.approvePrescription;
