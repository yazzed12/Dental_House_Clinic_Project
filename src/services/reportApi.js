/**
 * Report API Service — Handles AI report generation, humanization, and CRUD
 */
import { API_URL } from '../config/api.js';
import { apiBlobRequest } from './httpClient.js';
import { readRuntimeConfig } from '../config/runtime.js';
import { getSupabaseClient } from '../lib/supabaseClient.js';
import { normalizePrescriptionSnapshot } from './medicationApi.js';

function legacyHeaders() {
  const token = localStorage.getItem('clinic_token');
  return { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' };
}

export async function getAiAuthHeaders({
  provider = readRuntimeConfig().authProvider,
  supabaseClient,
} = {}) {
  if (provider === 'legacy') return legacyHeaders();
  if (provider !== 'supabase') throw new Error(`Unsupported Auth provider: ${provider}`);
  const client = supabaseClient || getSupabaseClient();
  const { data, error } = await client.auth.getSession();
  const token = data?.session?.access_token;
  if (error || !token) {
    const authError = new Error('A valid Supabase session is required for AI reports.', {
      cause: error || undefined,
    });
    authError.status = 401;
    throw authError;
  }
  return { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}

async function responseError(res, action) {
  let detail = '';
  try {
    const body = await res.json();
    detail = typeof body?.detail === 'string' ? body.detail : '';
  } catch {
    // Preserve the HTTP status when the backend has no JSON error envelope.
  }
  const error = new Error(`${action} failed (${res.status})${detail ? `: ${detail}` : ''}`);
  error.status = res.status;
  return error;
}

export function buildClinicalReportPayload({
  patientId,
  consultationId,
  appointmentId,
  toothId,
  toothStatus,
  symptoms,
  doctorNotes,
  aiDraftReport,
  finalMedicalReport,
  humanizedReport = '',
  status = 'approved',
}) {
  return {
    patient_id: String(patientId),
    consultation_id: consultationId || null,
    appointment_id: appointmentId || null,
    tooth_id: toothId,
    tooth_status: toothStatus,
    symptoms,
    doctor_notes: doctorNotes,
    ai_draft_report: aiDraftReport,
    final_medical_report: finalMedicalReport,
    humanized_report: humanizedReport,
    status,
  };
}

/** Generate AI clinical report from consultation data */
export async function generateAIReport(data) {
  try {
    const res = await fetch(`${API_URL}/ai/generate-report`, {
      method: 'POST', headers: await getAiAuthHeaders(), body: JSON.stringify(data)
    });
    if (!res.ok) throw await responseError(res, 'AI report generation');
    return await res.json();
  } catch (err) {
    console.error('AI Report API Error:', err);
    throw err;
  }
}

export function buildAIReportGenerationPayload({
  patient,
  consultationId,
  consultationDate,
  examinationDate,
  reportDate,
  clinicalFindings,
  consultationNote,
  performedProcedures,
  doctor,
  aiInstructions,
  approvedPrescription,
}) {
  return {
    consultationId: consultationId || null,
    patient: {
      id: patient?.id ?? null,
      name: patient?.name || '',
      age: patient?.age ?? null,
      gender: patient?.gender || null,
    },
    examinationDate: examinationDate || consultationDate || null,
    reportDate: reportDate || null,
    clinicalFindings: Array.isArray(clinicalFindings) ? clinicalFindings : [],
    consultationNote: consultationNote || '',
    performedProcedures: (performedProcedures || []).map(item => ({
      id: item.id ?? null,
      procedureId: item.procedureId,
      name: item.name,
      quantity: item.quantity,
    })),
    doctor: {
      name: doctor?.name || '',
      specialty: doctor?.specialty || doctor?.specialization || null,
      clinic: doctor?.clinic || null,
    },
    aiInstructions: aiInstructions?.trim() || null,
    approvedPrescription: approvedPrescription?.status === 'approved'
      ? normalizePrescriptionSnapshot(approvedPrescription) : null,
  };
}

/** Humanize a medical report into patient-friendly language */
export async function humanizeReport(report, patientName) {
  try {
    const res = await fetch(`${API_URL}/ai/humanize-report`, {
      method: 'POST', headers: await getAiAuthHeaders(),
      body: JSON.stringify({ report, patient_name: patientName })
    });
    if (!res.ok) throw await responseError(res, 'Report humanization');
    return await res.json();
  } catch (err) {
    console.error('Humanize API Error:', err);
    throw err;
  }
}

const reportRpcError = error => {
  const mapping = {
    '42501': ['REPORT_FORBIDDEN', 'authorization', 403, 'You are not authorized to access this clinical report.'],
    P2201: ['REPORT_PATIENT_NOT_FOUND', 'not-found', 404, 'Patient record not found.'],
    P2202: ['REPORT_CONSULTATION_NOT_FOUND', 'not-found', 404, 'Consultation session not found.'],
    P2203: ['REPORT_NOT_FOUND', 'not-found', 404, 'Clinical report not found.'],
    P2204: ['REPORT_LINKAGE_MISMATCH', 'conflict', 409, 'The report does not match this consultation session.'],
    P2205: ['REPORT_FINALIZED', 'conflict', 409, 'This clinical report is finalized and immutable.'],
    '22023': ['REPORT_INVALID', 'validation', 400, 'The clinical report payload is invalid.'],
  };
  const [code, kind, status, message] = mapping[error?.code]
    || ['REPORT_RPC_FAILED', 'transport', undefined, 'The clinical report request could not be completed.'];
  const result = new Error(message, { cause: error });
  result.code = code;
  result.kind = kind;
  if (status !== undefined) result.status = status;
  return result;
};

export function createReportPersistenceService({
  provider = readRuntimeConfig().authProvider,
  supabaseClient,
  legacyFetch,
} = {}) {
  const fetchLegacy = (...args) => (legacyFetch || globalThis.fetch)(...args);
  if (provider === 'legacy') {
    return {
      saveReport: async reportData => {
        const res = await fetchLegacy(`${API_URL}/reports`, {
          method: 'POST', headers: legacyHeaders(), body: JSON.stringify(reportData),
        });
        if (!res.ok) throw await responseError(res, 'Report save');
        return res.json();
      },
      getPatientReports: async patientId => {
        const res = await fetchLegacy(`${API_URL}/reports/patient/${patientId}`, { headers: legacyHeaders() });
        if (!res.ok) throw await responseError(res, 'Patient report request');
        return res.json();
      },
      updateReport: async (reportId, updates) => {
        const res = await fetchLegacy(`${API_URL}/reports/${reportId}`, {
          method: 'PUT', headers: legacyHeaders(), body: JSON.stringify(updates),
        });
        if (!res.ok) throw await responseError(res, 'Report update');
        return res.json();
      },
      finalizeReport: async () => { throw new Error('Structured report finalization requires Supabase.'); },
    };
  }
  if (provider !== 'supabase') throw new Error(`Unsupported Auth provider: ${provider}`);
  const client = () => supabaseClient || getSupabaseClient();
  const rpc = async (name, args, preserveArray = false) => {
    const { data, error } = await client().rpc(name, args);
    if (error) throw reportRpcError(error);
    return Array.isArray(data) && !preserveArray ? data[0] : data;
  };
  return {
    saveReport: report => rpc('save_clinical_report', {
      p_patient_id: report.patient_id,
      p_consultation_id: report.consultation_id,
      p_appointment_id: report.appointment_id,
      p_tooth_id: report.tooth_id,
      p_tooth_status: report.tooth_status,
      p_symptoms: report.symptoms || [],
      p_doctor_notes: report.doctor_notes || '',
      p_ai_draft_report: report.ai_draft_report || '',
      p_final_medical_report: report.final_medical_report,
      p_humanized_report: report.humanized_report || '',
      p_status: report.status || 'approved',
    }),
    getPatientReports: patientId => rpc(
      'get_patient_clinical_reports',
      { p_patient_id: patientId },
      true,
    ),
    updateReport: (reportId, updates) => rpc('update_clinical_report', {
      p_report_id: reportId, p_updates: updates,
    }),
    finalizeReport: (reportId, assessments, clinicalSummary, finalNarrative) => rpc(
      'finalize_clinical_report', {
        p_report_id: reportId,
        p_assessments: assessments,
        p_clinical_summary: clinicalSummary,
        p_final_narrative: finalNarrative,
      },
    ),
  };
}

const reportPersistenceService = createReportPersistenceService();
export const saveReport = reportPersistenceService.saveReport;
export const getPatientReports = reportPersistenceService.getPatientReports;

export const downloadReportPdf = (reportId) => apiBlobRequest(`/reports/${reportId}/download`);

export const updateReport = reportPersistenceService.updateReport;
export const finalizeReport = reportPersistenceService.finalizeReport;
