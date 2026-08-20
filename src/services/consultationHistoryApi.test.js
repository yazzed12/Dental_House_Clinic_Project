import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

import { createConsultationHistoryService } from './consultationHistoryApi.js';

test('Doctor consultation history uses the shared Supabase RPC', async () => {
  const calls = [];
  const service = createConsultationHistoryService({
    provider: 'supabase',
    supabaseClient: { rpc: async (name, args) => {
      calls.push([name, args]);
      return { data: [{ id: 'report-1', reportId: 'report-1', patient_id: 'patient-1', patient_name: 'Patient', reportSnapshot: { schemaVersion: 1, finalNarrative: 'Stored' } }], error: null };
    } },
    legacyRequest: () => { throw new Error('FastAPI must not be called'); },
  });
  const result = await service.listDoctorConsultationHistory();
  assert.equal(result[0].id, 'report-1');
  assert.deepEqual(result[0].reportSnapshot, { schemaVersion: 1, finalNarrative: 'Stored' });
  assert.deepEqual(result[0].labItems, []);
  assert.equal(result[0].labNote, null);
  assert.deepEqual(calls, [['list_doctor_consultation_history', undefined]]);
});

test('report-only legacy rows do not trigger a patient-report authorization fan-out', async () => {
  const calls = [];
  const row = { id: 'legacy-report', reportId: 'legacy-report', patient_id: 'legacy-patient', reportSnapshot: null };
  const service = createConsultationHistoryService({
    provider: 'supabase',
    supabaseClient: { rpc: async name => { calls.push(name); return { data: [row], error: null }; } },
  });
  assert.deepEqual(await service.listDoctorConsultationHistory(), [{
    ...row, labItems: [], labNote: null, prescription: null,
  }]);
  assert.deepEqual(calls, ['list_doctor_consultation_history']);
});

test('history normalizes Migration 023 Lab fields without catalog fan-out', async () => {
  const calls = [];
  const snapshots = [{
    labId: 'lab-1', labProductId: 'product-1', labName: 'Historical Lab',
    productName: 'Zircon Crown', unitPrice: 500, quantity: 2, totalAmount: 1000,
  }];
  const service = createConsultationHistoryService({
    provider: 'supabase',
    supabaseClient: { rpc: async name => {
      calls.push(name);
      return { data: [{ id: 'history-1', labItems: snapshots, labNote: 'Shade A2' }], error: null };
    } },
  });
  const [result] = await service.listDoctorConsultationHistory();
  assert.deepEqual(result.labItems, snapshots);
  assert.equal(result.labNote, 'Shade A2');
  assert.deepEqual(calls, ['list_doctor_consultation_history']);
});

test('valid empty history stays distinct from authorization and transport errors', async () => {
  const empty = createConsultationHistoryService({
    provider: 'supabase', supabaseClient: { rpc: async () => ({ data: [], error: null }) },
  });
  assert.deepEqual(await empty.listDoctorConsultationHistory(), []);
  for (const [rpcCode, code, kind] of [
    ['42501', 'CONSULTATION_HISTORY_FORBIDDEN', 'authorization'],
    ['XX000', 'CONSULTATION_HISTORY_FAILED', 'transport'],
  ]) {
    const failed = createConsultationHistoryService({
      provider: 'supabase', supabaseClient: { rpc: async () => ({ data: null, error: { code: rpcCode } }) },
    });
    await assert.rejects(failed.listDoctorConsultationHistory(),
      error => error.code === code && error.kind === kind);
  }
});

test('legacy rollback remains explicit and Supabase history has no clinic token transport', async () => {
  const legacy = createConsultationHistoryService({
    provider: 'legacy', legacyRequest: async path => path,
  });
  assert.equal(await legacy.listDoctorConsultationHistory(), '/doctor/consultations/history');
  const source = await readFile(new URL('./consultationHistoryApi.js', import.meta.url), 'utf8');
  const supabaseBranch = source.split("if (provider !== 'supabase')")[1];
  assert.doesNotMatch(supabaseBranch, /clinic_token|apiRequest\(|fetch\(/);
});

test('patient modal renders consultation history failures instead of an empty state', async () => {
  const source = await readFile(new URL('../components/PatientModals.jsx', import.meta.url), 'utf8');
  assert.match(source, /consultationsError/);
  assert.match(source, /Consultation history could not be loaded/);
});

test('consultation-first rows cannot invoke report mutations with a synthetic id', async () => {
  const source = await readFile(new URL('../pages/Doctor/ConsultationsHistory.jsx', import.meta.url), 'utf8');
  assert.match(source, /startsWith\('consultation:'\)/);
  assert.match(source, /const hasReport = Boolean\(reportId\)/);
  assert.match(source, /hasReport && \(/);
  assert.match(source, /updateReport\(reportId/);
  assert.match(source, /General Session/);
});

test('Patient Card historical view never opens current consultation initialization but may edit an eligible report', async () => {
  const patients = await readFile(new URL('../pages/Doctor/PatientsPage.jsx', import.meta.url), 'utf8');
  const history = await readFile(new URL('../pages/Doctor/ConsultationsHistory.jsx', import.meta.url), 'utf8');
  assert.match(patients, /consultations-history\?patientId=/);
  assert.doesNotMatch(patients, /onViewConsultation=.*doctor\/consultation\//);
  assert.match(history, /historicalReadOnly = Boolean/);
  assert.match(history, /readOnly=\{historicalReadOnly\}/);
  assert.match(history, /const canEditReport = hasReport && !isStructuredFinalized && !immutabilityLocked/);
  assert.match(history, /Edit historical clinical report/);
  assert.doesNotMatch(history, /get_or_initialize_consultation|save_current_consultation/);
});

test('history renders structured findings and keeps legacy symptoms unassigned', async () => {
  const history = await readFile(new URL('../pages/Doctor/ConsultationsHistory.jsx', import.meta.url), 'utf8');
  const modal = await readFile(new URL('../components/PatientModals.jsx', import.meta.url), 'utf8');
  assert.match(history, /Array\.isArray\(report\.clinicalFindings\)/);
  assert.match(history, /isStructuredFinalized/);
  assert.match(history, /FinalReportSnapshot/);
  assert.match(history, /Tooth Note:/);
  assert.match(history, /Legacy Consultation Symptoms/);
  assert.match(modal, /Array\.isArray\(selectedConsultation\.clinicalFindings\)/);
  assert.match(modal, /clinicalFindings == null[\s\S]*Legacy Consultation Symptoms/);
});
