import assert from 'node:assert/strict';
import test from 'node:test';
import { createLabTransactionsService, LabTransactionsApiError } from './labTransactionsApi.js';

const LAB = '11111111-1111-4111-8111-111111111111';
const FROM = '2026-08-01T00:00:00.000Z';
const TO = '2026-09-01T00:00:00.000Z';

test('Lab Transactions use only the five hardened Supabase RPCs with half-open ranges', async () => {
  const calls = [];
  const service = createLabTransactionsService({ supabaseClient: { rpc: async (name, args) => { calls.push([name, args]); return { data: name.startsWith('list_') ? [] : {}, error: null }; } } });
  await service.listLabTransactions(LAB, FROM, TO);
  await service.getLabTransactionSummary(LAB, FROM, TO);
  await service.listLabPayments(LAB, FROM, TO);
  await service.createLabPayment({ labId: LAB, amount: '100.00', paidAt: FROM, note: 'Monthly payment' });
  await service.correctLabPayment({ paymentId: '22222222-2222-4222-8222-222222222222', expectedRevision: 1, amount: '90.00', paidAt: FROM, note: null, reason: 'Bank correction' });
  assert.deepEqual(calls.map(call => call[0]), ['list_lab_transactions', 'get_lab_transaction_summary', 'list_lab_payments', 'create_lab_payment', 'correct_lab_payment']);
  assert.deepEqual(calls[0][1], { p_lab_id: LAB, p_date_from: FROM, p_date_to: TO });
  assert.deepEqual(calls[3][1], { p_lab_id: LAB, p_amount: '100.00', p_paid_at: FROM, p_note: 'Monthly payment' });
  assert.equal('p_created_by' in calls[3][1], false);
  assert.deepEqual(calls[4][1], { p_payment_id: '22222222-2222-4222-8222-222222222222', p_expected_revision: 1, p_amount: '90.00', p_paid_at: FROM, p_note: null, p_reason: 'Bank correction' });
});

test('RPC errors remain readable and section-safe', async () => {
  const service = createLabTransactionsService({ supabaseClient: { rpc: async () => ({ data: null, error: { code: '42501' } }) } });
  await assert.rejects(service.listLabPayments(LAB, FROM, TO), error => error instanceof LabTransactionsApiError && error.kind === 'authorization' && /authorized/.test(error.message));
});
