import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { createFinanceService } from './financeApi.js';

const PATIENT_ID = '7e4b49de-b931-47f3-9454-d90c89c85a79';
const CONSULTATION_ID = 'b2887fcf-8f65-4976-8909-00e323d1db24';
const PAYMENT_ID = 'c3887fcf-8f65-4976-8909-00e323d1db24';
const rpcClient = (handler) => ({ rpc: handler });

test('catalog and current selections use Supabase RPCs with stable shapes', async () => {
  const calls = [];
  const service = createFinanceService({ provider: 'supabase', supabaseClient: rpcClient(async (name, args) => {
    calls.push([name, args]);
    if (name === 'list_clinic_procedures') return { data: [{ id: 'p1', name: 'Filling', price: '100.00', isActive: true }], error: null };
    return { data: { consultationId: CONSULTATION_ID, version: 2, items: [], total: '0.00' }, error: null };
  }) });
  assert.equal((await service.listProcedures(true))[0].price, '100.00');
  assert.equal((await service.getConsultationProcedures(PATIENT_ID)).version, 2);
  assert.deepEqual(calls, [
    ['list_clinic_procedures', { p_active_only: true }],
    ['get_current_consultation_procedures', { p_patient_id: PATIENT_ID }],
  ]);
});

test('catalog create/update and selection save send only controlled payloads', async () => {
  const calls = [];
  const service = createFinanceService({ provider: 'supabase', supabaseClient: rpcClient(async (name, args) => {
    calls.push([name, args]); return { data: {}, error: null };
  }) });
  await service.createProcedure({ name: 'Filling', price: '100.00', created_by: 'ignored' });
  await service.updateProcedure('p1', { is_active: false });
  await service.saveConsultationProcedures(PATIENT_ID, { version: 4, selections: [{ procedureId: 'p1', quantity: 2 }] });
  assert.deepEqual(calls[0], ['create_clinic_procedure', { p_name: 'Filling', p_price: '100.00' }]);
  assert.deepEqual(calls[1], ['update_clinic_procedure', { p_procedure_id: 'p1', p_updates: { is_active: false } }]);
  assert.deepEqual(calls[2], ['save_current_consultation_procedures', {
    p_patient_id: PATIENT_ID, p_version: 4, p_selections: [{ procedureId: 'p1', quantity: 2 }],
  }]);
});

test('billing, patient projections, payment creation and correction use RPCs', async () => {
  const calls = [];
  const service = createFinanceService({ provider: 'supabase', supabaseClient: rpcClient(async (name, args) => {
    calls.push([name, args]); return { data: name === 'list_financial_billing' ? [] : {}, error: null };
  }) });
  await service.listBilling();
  await service.getPatientFinancialHistory(PATIENT_ID);
  await service.getPatientOutstanding(PATIENT_ID);
  await service.getPatientFinancialSummaries();
  await service.addPayment(CONSULTATION_ID, { billingVersion: 3, amount: '25.00', paidAt: '2026-08-13T10:00:00Z' });
  await service.correctPayment(PAYMENT_ID, { billingVersion: 4, expectedRevision: 1, amount: '20.00', paidAt: '2026-08-13T10:00:00Z', reason: 'Correction' });
  assert.deepEqual(calls.map(call => call[0]), [
    'list_financial_billing', 'get_patient_financial_history',
    'get_patient_financial_outstanding', 'get_patient_financial_summaries',
    'add_financial_payment', 'correct_financial_payment',
  ]);
  assert.equal(calls[4][1].p_billing_version, 3);
  assert.equal(calls[5][1].p_expected_revision, 1);
});

test('financial authorization, conflict, validation and transport errors stay distinct', async () => {
  const cases = [
    ['42501', 'FINANCIAL_FORBIDDEN', 'authorization', 403],
    ['40001', 'FINANCIAL_VERSION_CONFLICT', 'conflict', 409],
    ['22023', 'FINANCIAL_INVALID_INPUT', 'validation', 400],
    ['XX000', 'FINANCIAL_RPC_FAILED', 'transport', undefined],
  ];
  for (const [rpcCode, code, kind, status] of cases) {
    const service = createFinanceService({ provider: 'supabase', supabaseClient: rpcClient(async () => ({ data: null, error: { code: rpcCode } })) });
    await assert.rejects(service.listBilling(), error => error.code === code && error.kind === kind && error.status === status);
  }
});

test('financial domain conflicts and validation failures retain stable client codes', async () => {
  const cases = [
    ['P3008', 'FINANCIAL_INVALID_QUANTITY', 'validation'],
    ['P3009', 'FINANCIAL_DUPLICATE_SELECTION', 'validation'],
    ['P3010', 'FINANCIAL_PROCEDURES_VERSION_CONFLICT', 'conflict'],
    ['P3011', 'FINANCIAL_BILLING_VERSION_CONFLICT', 'conflict'],
    ['P3012', 'FINANCIAL_PAYMENT_REVISION_CONFLICT', 'conflict'],
    ['P3013', 'FINANCIAL_INVALID_PAYMENT_AMOUNT', 'validation'],
  ];
  for (const [rpcCode, clientCode, kind] of cases) {
    const service = createFinanceService({
      provider: 'supabase',
      supabaseClient: { rpc: async () => ({ data: null, error: { code: rpcCode } }) },
    });
    await assert.rejects(service.listBilling(), (error) =>
      error.code === clientCode && error.kind === kind);
  }
});

test('legacy finance remains an explicit rollback transport', async () => {
  const calls = [];
  const service = createFinanceService({ provider: 'legacy', legacyRequestImpl: async (path, options) => {
    calls.push([path, options]); return [];
  } });
  await service.listProcedures(true);
  await service.listBilling();
  assert.equal(calls[0][0], '/clinic-procedures?active_only=true');
  assert.equal(calls[1][0], '/finance/billing');
});

test('Supabase financial service branch has no FastAPI, clinic token, or service role', async () => {
  const source = await readFile(new URL('./financeApi.js', import.meta.url), 'utf8');
  const supabaseBranch = source.slice(source.indexOf("if (provider !== 'supabase')"));
  assert.doesNotMatch(supabaseBranch, /clinic_token|API_URL|fetch\s*\(|service_role/);
  for (const rpc of ['list_clinic_procedures', 'save_current_consultation_procedures', 'list_financial_billing', 'add_financial_payment', 'correct_financial_payment']) {
    assert.match(supabaseBranch, new RegExp(rpc));
  }
});

test('financial UI callers surface failures instead of replacing them with empty data', async () => {
  const consultation = await readFile(new URL('../pages/Doctor/ConsultationFlow.jsx', import.meta.url), 'utf8');
  const upcoming = await readFile(new URL('../components/UpcomingConsultations.jsx', import.meta.url), 'utf8');
  const patients = await readFile(new URL('../pages/Doctor/PatientsPage.jsx', import.meta.url), 'utf8');
  assert.match(consultation, /setProcedureSummaryError\(error\.message\)/);
  assert.doesNotMatch(consultation, /getConsultationProcedures[\s\S]{0,180}\.catch\(\(\) => undefined\)/);
  assert.match(upcoming, /setFinancialError\(error\.message\)/);
  assert.doesNotMatch(upcoming, /getPatientFinancialSummaries\(\)[\s\S]{0,100}catch\(\(\)=>setFinancialSummaries\(\{\}\)\)/);
  assert.match(patients, /showToast\(error\.message, 'danger'\)/);
});
