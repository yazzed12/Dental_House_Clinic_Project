import { API_URL } from '../config/api.js';
import { readRuntimeConfig } from '../config/runtime.js';
import { getSupabaseClient } from '../lib/supabaseClient.js';

export class FinancialApiError extends Error {
  constructor(message, { code = 'FINANCIAL_RPC_FAILED', kind = 'transport', status, cause } = {}) {
    super(message, { cause });
    this.name = 'FinancialApiError';
    this.code = code;
    this.kind = kind;
    if (status !== undefined) this.status = status;
  }
}

const rpcError = (error) => {
  const mapping = {
    '42501': ['FINANCIAL_FORBIDDEN', 'authorization', 403, 'You are not authorized to access financial data.'],
    P3001: ['FINANCIAL_PATIENT_NOT_FOUND', 'not-found', 404, 'Patient not found.'],
    P3002: ['FINANCIAL_NO_CURRENT_APPOINTMENT', 'not-found', 404, 'No eligible current appointment exists.'],
    P3003: ['FINANCIAL_INVALID_PROCEDURE', 'validation', 400, 'Procedure not found.'],
    P3004: ['FINANCIAL_NO_CURRENT_CONSULTATION', 'not-found', 404, 'No current consultation exists.'],
    P3005: ['FINANCIAL_INACTIVE_PROCEDURE', 'validation', 400, 'An inactive procedure cannot be newly selected.'],
    P3006: ['FINANCIAL_NO_BILLED_PROCEDURES', 'validation', 400, 'Consultation has no billed procedures.'],
    P3007: ['FINANCIAL_PAYMENT_NOT_FOUND', 'not-found', 404, 'Payment not found.'],
    P3008: ['FINANCIAL_INVALID_QUANTITY', 'validation', 400, 'Procedure quantity must be a positive whole number.'],
    P3009: ['FINANCIAL_DUPLICATE_SELECTION', 'validation', 400, 'A procedure may be selected only once.'],
    P3010: ['FINANCIAL_PROCEDURES_VERSION_CONFLICT', 'conflict', 409, 'Procedure selections changed elsewhere. Refresh and retry.'],
    P3011: ['FINANCIAL_BILLING_VERSION_CONFLICT', 'conflict', 409, 'Billing data changed elsewhere. Refresh and retry.'],
    P3012: ['FINANCIAL_PAYMENT_REVISION_CONFLICT', 'conflict', 409, 'The payment was already corrected elsewhere. Refresh and retry.'],
    P3013: ['FINANCIAL_INVALID_PAYMENT_AMOUNT', 'validation', 400, 'Payment amount must be greater than zero.'],
    P3014: ['FINANCIAL_INVALID_SELECTIONS', 'validation', 400, 'Procedure selections are invalid.'],
    '40001': ['FINANCIAL_VERSION_CONFLICT', 'conflict', 409, 'Financial data changed elsewhere. Refresh and retry.'],
    '23505': ['FINANCIAL_DUPLICATE', 'conflict', 409, 'A duplicate financial record already exists.'],
    '22023': ['FINANCIAL_INVALID_INPUT', 'validation', 400, 'Invalid financial input.'],
  };
  const [code, kind, status, message] = mapping[error?.code] || [
    'FINANCIAL_RPC_FAILED', 'transport', undefined,
    'The financial request could not be completed.',
  ];
  return new FinancialApiError(message, { code, kind, status, cause: error });
};

const legacyHeaders = () => ({
  Authorization: `Bearer ${localStorage.getItem('clinic_token')}`,
  'Content-Type': 'application/json',
});

const legacyRequest = async (path, options = {}) => {
  const response = await fetch(`${API_URL}${path}`, { ...options, headers: legacyHeaders() });
  if (!response.ok) {
    let detail = '';
    try { detail = (await response.json())?.detail || ''; } catch { /* no JSON body */ }
    const error = new FinancialApiError(detail || `Request failed with ${response.status}`, {
      code: response.status === 409 ? 'FINANCIAL_VERSION_CONFLICT' : 'FINANCIAL_LEGACY_FAILED',
      kind: response.status === 409 ? 'conflict' : 'transport', status: response.status,
    });
    throw error;
  }
  return response.json();
};

const resultRow = (data) => (Array.isArray(data) ? data[0] : data);

export function createFinanceService({
  provider = readRuntimeConfig().authProvider,
  supabaseClient,
  legacyRequestImpl = legacyRequest,
} = {}) {
  if (provider === 'legacy') {
    return {
      listProcedures: (activeOnly = false) => legacyRequestImpl(`/clinic-procedures${activeOnly ? '?active_only=true' : ''}`),
      createProcedure: (payload) => legacyRequestImpl('/clinic-procedures', { method: 'POST', body: JSON.stringify(payload) }),
      updateProcedure: (id, payload) => legacyRequestImpl(`/clinic-procedures/${id}`, { method: 'PATCH', body: JSON.stringify(payload) }),
      getConsultationProcedures: (patientId) => legacyRequestImpl(`/consultations/${patientId}/procedures`),
      saveConsultationProcedures: (patientId, payload) => legacyRequestImpl(`/consultations/${patientId}/procedures`, { method: 'PUT', body: JSON.stringify(payload) }),
      listBilling: () => legacyRequestImpl('/finance/billing'),
      getPatientFinancialHistory: (patientId) => legacyRequestImpl(`/finance/patients/${patientId}/history`),
      getPatientOutstanding: (patientId) => legacyRequestImpl(`/finance/patients/${patientId}/outstanding`),
      getPatientFinancialSummaries: () => legacyRequestImpl('/finance/patient-summaries'),
      addPayment: (consultationId, payload) => legacyRequestImpl(`/finance/consultations/${consultationId}/payments`, { method: 'POST', body: JSON.stringify(payload) }),
      correctPayment: (paymentId, payload) => legacyRequestImpl(`/finance/payments/${paymentId}/corrections`, { method: 'POST', body: JSON.stringify(payload) }),
    };
  }
  if (provider !== 'supabase') throw new Error(`Unsupported Auth provider: ${provider}`);
  const client = () => supabaseClient || getSupabaseClient();
  const rpc = async (name, args, { rows = false } = {}) => {
    const { data, error } = await client().rpc(name, args);
    if (error) throw rpcError(error);
    return rows ? (data || []) : resultRow(data);
  };
  return {
    listProcedures: (activeOnly = false) => rpc('list_clinic_procedures', { p_active_only: activeOnly }, { rows: true }),
    createProcedure: (payload) => rpc('create_clinic_procedure', { p_name: payload.name, p_price: payload.price }),
    updateProcedure: (id, payload) => rpc('update_clinic_procedure', { p_procedure_id: id, p_updates: payload }),
    getConsultationProcedures: (patientId) => rpc('get_current_consultation_procedures', { p_patient_id: patientId }),
    saveConsultationProcedures: (patientId, payload) => rpc('save_current_consultation_procedures', {
      p_patient_id: patientId, p_version: payload.version, p_selections: payload.selections,
    }),
    listBilling: () => rpc('list_financial_billing', undefined, { rows: true }),
    getPatientFinancialHistory: (patientId) => rpc('get_patient_financial_history', { p_patient_id: patientId }),
    getPatientOutstanding: (patientId) => rpc('get_patient_financial_outstanding', { p_patient_id: patientId }),
    getPatientFinancialSummaries: () => rpc('get_patient_financial_summaries'),
    addPayment: (consultationId, payload) => rpc('add_financial_payment', {
      p_consultation_id: consultationId, p_billing_version: payload.billingVersion,
      p_amount: payload.amount, p_paid_at: payload.paidAt,
    }),
    correctPayment: (paymentId, payload) => rpc('correct_financial_payment', {
      p_payment_id: paymentId, p_billing_version: payload.billingVersion,
      p_expected_revision: payload.expectedRevision, p_amount: payload.amount,
      p_paid_at: payload.paidAt, p_reason: payload.reason,
    }),
  };
}

const financeService = createFinanceService();
export const listProcedures = financeService.listProcedures;
export const createProcedure = financeService.createProcedure;
export const updateProcedure = financeService.updateProcedure;
export const getConsultationProcedures = financeService.getConsultationProcedures;
export const saveConsultationProcedures = financeService.saveConsultationProcedures;
export const listBilling = financeService.listBilling;
export const getPatientFinancialHistory = financeService.getPatientFinancialHistory;
export const getPatientOutstanding = financeService.getPatientOutstanding;
export const getPatientFinancialSummaries = financeService.getPatientFinancialSummaries;
export const addPayment = financeService.addPayment;
export const correctPayment = financeService.correctPayment;
