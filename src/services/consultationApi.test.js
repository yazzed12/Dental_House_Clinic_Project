import assert from 'node:assert/strict';
import test from 'node:test';

import { createConsultationService } from './consultationApi.js';

const PATIENT_ID = '7e4b49de-b931-47f3-9454-d90c89c85a79';
const USER_ID = 'aaaabbbb-1111-4111-8111-ccccdddd2222';

const rpcClient = (handler) => ({ rpc: handler });

test('Supabase current-consultation load uses the hardened RPC and shared client', async () => {
  const calls = [];
  const service = createConsultationService({
    provider: 'supabase',
    supabaseClient: rpcClient(async (name, args) => {
      calls.push([name, args]);
      return { data: { patientId: PATIENT_ID, toothData: {}, version: 0, dentalStateVersion: 0 }, error: null };
    }),
    legacyFetch: () => { throw new Error('FastAPI must not be called'); },
  });
  const result = await service.fetchConsultation(PATIENT_ID, USER_ID);
  assert.equal(result.patientId, PATIENT_ID);
  assert.deepEqual(calls, [[
    'get_or_initialize_consultation', { p_patient_id: PATIENT_ID },
  ]]);
});

test('same-scope consultation initialization is single-flight', async () => {
  let initializeCalls = 0;
  let releaseInitialization;
  const pending = new Promise(resolve => { releaseInitialization = resolve; });
  const service = createConsultationService({
    provider: 'supabase',
    supabaseClient: rpcClient(async name => {
      if (name === 'get_or_initialize_consultation') {
        initializeCalls += 1;
        await pending;
        return { data: { patientId: PATIENT_ID, consultationId: null, toothData: {}, version: 0 }, error: null };
      }
      return { data: [], error: null };
    }),
  });
  const first = service.fetchConsultation(PATIENT_ID, USER_ID);
  const second = service.fetchConsultation(PATIENT_ID, USER_ID);
  assert.equal(first, second);
  releaseInitialization();
  await Promise.all([first, second]);
  assert.equal(initializeCalls, 1);
});

test('current consultation hydrates Migration 019 findings from read-only history', async () => {
  const calls = [];
  const service = createConsultationService({
    provider: 'supabase',
    supabaseClient: rpcClient(async (name, args) => {
      calls.push([name, args]);
      if (name === 'get_or_initialize_consultation') {
        return { data: { consultationId: 'consultation-1', toothData: {}, version: 2 }, error: null };
      }
      return { data: [{ consultationId: 'consultation-1', clinicalFindings: [] }], error: null };
    }),
  });
  const result = await service.fetchConsultation(PATIENT_ID, USER_ID);
  assert.deepEqual(result.clinicalFindings, []);
  assert.equal(calls[1][0], 'get_patient_consultation_history');
});

test('Supabase save preserves versions and omitted-versus-null session note semantics', async () => {
  const calls = [];
  const service = createConsultationService({
    provider: 'supabase',
    supabaseClient: rpcClient(async (name, args) => {
      calls.push([name, args]);
      return { data: { version: args.p_version + 1, dentalStateVersion: 4 }, error: null };
    }),
  });
  service.primeConsultationSaveQueue(PATIENT_ID, 2, 3, USER_ID);
  await service.saveConsultationToApi(PATIENT_ID, { 11: { status: 'treated' } }, 2, undefined, 3, USER_ID);
  await service.saveConsultationToApi(PATIENT_ID, { 11: { status: 'treated' } }, 2, null, 4, USER_ID);
  assert.deepEqual(calls[0], ['save_current_consultation', {
    p_patient_id: PATIENT_ID,
    p_tooth_data: { 11: { status: 'treated' } },
    p_version: 2,
    p_dental_state_version: 3,
    p_session_note: null,
    p_session_note_supplied: false,
    p_symptoms_snapshot: [],
    p_symptoms_supplied: false,
    p_clinical_findings_snapshot: null,
    p_clinical_findings_supplied: false,
  }]);
  assert.equal(calls[1][1].p_version, 3);
  assert.equal(calls[1][1].p_session_note, null);
  assert.equal(calls[1][1].p_session_note_supplied, true);
});

test('Supabase consultation save sends historical symptom snapshots atomically', async () => {
  const calls = [];
  const service = createConsultationService({
    provider: 'supabase',
    supabaseClient: rpcClient(async (name, args) => {
      calls.push([name, args]);
      return { data: { version: 3, dentalStateVersion: 4, symptoms: ['Pain'] }, error: null };
    }),
  });
  service.primeConsultationSaveQueue(PATIENT_ID, 2, 4, USER_ID);
  await service.saveConsultationToApi(
    PATIENT_ID, { 11: { status: 'caries' } }, 2, undefined, 4, USER_ID, ['Pain'],
  );
  assert.deepEqual(calls[0][1].p_symptoms_snapshot, ['Pain']);
  assert.equal(calls[0][1].p_symptoms_supplied, true);
  assert.equal(calls[0][1].p_clinical_findings_snapshot, null);
  assert.equal(calls[0][1].p_clinical_findings_supplied, false);
});

test('structured autosave selects the 10-parameter RPC and marks findings supplied', async () => {
  const calls = [];
  const service = createConsultationService({
    provider: 'supabase',
    supabaseClient: rpcClient(async (name, args) => {
      calls.push([name, args]);
      return { data: { version: 3, dentalStateVersion: 4 }, error: null };
    }),
  });
  const findings = [{ toothId: '11', toothStatus: 'problem', symptoms: ['Pain'], toothNote: 'Caries' }];
  service.primeConsultationSaveQueue(PATIENT_ID, 2, 4, USER_ID);
  await service.saveConsultationToApi(
    PATIENT_ID,
    { 11: { status: 'problem', notes: 'Caries' } },
    2, undefined, 4, USER_ID, ['Pain'], findings,
  );
  assert.deepEqual(calls[0][1].p_clinical_findings_snapshot, findings);
  assert.equal(calls[0][1].p_clinical_findings_supplied, true);
});

test('RPC errors map to stable patient, appointment, authorization and transport errors', async () => {
  const cases = [
    ['P2001', 'PATIENT_NOT_FOUND', 'patient-not-found'],
    ['P2002', 'NO_CURRENT_APPOINTMENT', 'no-current-appointment'],
    ['42501', 'CONSULTATION_FORBIDDEN', 'authorization'],
    ['XX000', 'CONSULTATION_LOAD_FAILED', 'load'],
  ];
  for (const [rpcCode, code, kind] of cases) {
    const service = createConsultationService({
      provider: 'supabase',
      supabaseClient: rpcClient(async () => ({ data: null, error: { code: rpcCode } })),
    });
    await assert.rejects(
      service.fetchConsultation(PATIENT_ID, USER_ID),
      (error) => error.code === code && error.kind === kind,
    );
  }
});

test('stale save refreshes authoritative state, preserves input and blocks the queue', async () => {
  const unsaved = { 16: { status: 'missing' } };
  let calls = 0;
  const service = createConsultationService({
    provider: 'supabase',
    supabaseClient: rpcClient(async (name) => {
      calls += 1;
      if (name === 'save_current_consultation') return { data: null, error: { code: '40001' } };
      return { data: { version: 7, dentalStateVersion: 9, toothData: {} }, error: null };
    }),
  });
  service.primeConsultationSaveQueue(PATIENT_ID, 6, 8, USER_ID);
  const conflict = await service.saveConsultationToApi(PATIENT_ID, unsaved, 6, undefined, 8, USER_ID)
    .then(() => null, (error) => error);
  assert.equal(conflict.status, 409);
  assert.equal(conflict.authoritative.version, 7);
  assert.deepEqual(unsaved, { 16: { status: 'missing' } });
  await assert.rejects(
    service.saveConsultationToApi(PATIENT_ID, unsaved, 6, undefined, 8, USER_ID),
    (error) => error.status === 409 && error.message.includes('paused'),
  );
  assert.equal(calls, 2);
});

test('session scopes do not share load promises or optimistic save versions', async () => {
  let loads = 0;
  const service = createConsultationService({
    provider: 'supabase',
    supabaseClient: rpcClient(async (name, args) => {
      if (name === 'get_or_initialize_consultation') {
        loads += 1;
        return { data: { version: loads, dentalStateVersion: loads }, error: null };
      }
      return { data: { version: args.p_version + 1, dentalStateVersion: args.p_dental_state_version }, error: null };
    }),
  });
  await Promise.all([
    service.fetchConsultation(PATIENT_ID, 'doctor-a'),
    service.fetchConsultation(PATIENT_ID, 'doctor-b'),
  ]);
  assert.equal(loads, 2);
  service.invalidateSessionState();
});

test('patient consultation history uses Supabase and keeps empty distinct from error', async () => {
  const calls = [];
  const service = createConsultationService({
    provider: 'supabase',
    supabaseClient: rpcClient(async (name, args) => {
      calls.push([name, args]);
      return { data: [], error: null };
    }),
    legacyFetch: () => { throw new Error('FastAPI must not be called'); },
  });
  assert.deepEqual(await service.fetchConsultationHistory(PATIENT_ID), []);
  assert.deepEqual(calls, [['get_patient_consultation_history', { p_patient_id: PATIENT_ID }]]);
  const failed = createConsultationService({
    provider: 'supabase',
    supabaseClient: rpcClient(async () => ({ data: null, error: { code: 'XX000' } })),
  });
  await assert.rejects(failed.fetchConsultationHistory(PATIENT_ID),
    error => error.code === 'CONSULTATION_HISTORY_FAILED' && error.kind === 'history');
});

test('only single-tooth FastAPI endpoint remains disabled in Supabase mode', async () => {
  const service = createConsultationService({ provider: 'supabase', supabaseClient: rpcClient(async () => ({})) });
  await assert.rejects(service.updateToothOnApi(PATIENT_ID, '11', {}, 1), /not been migrated/);
});
