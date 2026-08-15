import { getSupabaseClient } from '../lib/supabaseClient.js';

export class LabTransactionsApiError extends Error {
  constructor(message, { code = 'LAB_TRANSACTIONS_RPC_FAILED', kind = 'transport', cause } = {}) {
    super(message, { cause });
    this.name = 'LabTransactionsApiError';
    this.code = code;
    this.kind = kind;
  }
}

const readableError = error => {
  const mapping = {
    '42501': ['LAB_TRANSACTIONS_FORBIDDEN', 'authorization', 'You are not authorized to access Lab Transactions.'],
    P4020: ['LAB_TRANSACTION_LAB_NOT_FOUND', 'not-found', 'The selected Lab could not be found.'],
    P4021: ['LAB_TRANSACTION_LAB_NOT_ACTIVE', 'validation', 'Archived Labs cannot accept new payments.'],
    P4022: ['LAB_PAYMENT_NOT_FOUND', 'not-found', 'The selected Lab payment could not be found.'],
    '22023': ['LAB_TRANSACTION_INVALID', 'validation', 'Check the payment details or selected date range.'],
    '40001': ['LAB_PAYMENT_REVISION_CONFLICT', 'conflict', 'This payment changed elsewhere. Refresh and try again.'],
  };
  const [code, kind, message] = mapping[error?.code] || [
    'LAB_TRANSACTIONS_RPC_FAILED', 'transport', 'The Lab Transactions request could not be completed.',
  ];
  return new LabTransactionsApiError(message, { code, kind, cause: error });
};

export function createLabTransactionsService({ supabaseClient } = {}) {
  const client = () => supabaseClient || getSupabaseClient();
  const rpc = async (name, args) => {
    const { data, error } = await client().rpc(name, args);
    if (error) throw readableError(error);
    return data;
  };
  const rangeArgs = (labId, dateFrom, dateTo) => ({
    p_lab_id: labId,
    p_date_from: dateFrom,
    p_date_to: dateTo,
  });
  return {
    listLabTransactions: async (labId, dateFrom, dateTo) =>
      (await rpc('list_lab_transactions', rangeArgs(labId, dateFrom, dateTo))) || [],
    getLabTransactionSummary: (labId, dateFrom, dateTo) =>
      rpc('get_lab_transaction_summary', rangeArgs(labId, dateFrom, dateTo)),
    listLabPayments: async (labId, dateFrom, dateTo) =>
      (await rpc('list_lab_payments', rangeArgs(labId, dateFrom, dateTo))) || [],
    createLabPayment: ({ labId, amount, paidAt, note }) => rpc('create_lab_payment', {
      p_lab_id: labId, p_amount: amount, p_paid_at: paidAt, p_note: note || null,
    }),
    correctLabPayment: ({ paymentId, expectedRevision, amount, paidAt, note, reason }) =>
      rpc('correct_lab_payment', {
        p_payment_id: paymentId, p_expected_revision: expectedRevision,
        p_amount: amount, p_paid_at: paidAt, p_note: note || null, p_reason: reason,
      }),
  };
}

const service = createLabTransactionsService();
export const listLabTransactions = service.listLabTransactions;
export const getLabTransactionSummary = service.getLabTransactionSummary;
export const listLabPayments = service.listLabPayments;
export const createLabPayment = service.createLabPayment;
export const correctLabPayment = service.correctLabPayment;
