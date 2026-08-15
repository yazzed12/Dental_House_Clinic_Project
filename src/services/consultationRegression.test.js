import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import {
  fetchConsultation,
  primeConsultationSaveQueue,
  resetConsultationApiStateForTests,
  resumeConsultationSaveQueue,
  saveConsultationToApi,
} from './consultationApi.js';
import { buildClinicalReportPayload, saveReport } from './reportApi.js';
import {
  isCompletedAppointmentStatus,
  markFinishedAppointment,
} from './appointmentLifecycle.js';

globalThis.localStorage = { getItem: () => 'synthetic-token' };

test('session note and optimistic version are sent unchanged', async () => {
  let request;
  globalThis.fetch = async (_url, options) => {
    request = options;
    return {
      ok: true,
      status: 200,
      json: async () => ({
        version: 8,
        dentalStateVersion: 12,
        sessionNote: 'Saved note',
      }),
    };
  };

  await saveConsultationToApi(
    'patient-uuid',
    { 11: { status: 'treated' } },
    7,
    'Saved note',
    11,
  );
  assert.deepEqual(JSON.parse(request.body), {
    toothData: { 11: { status: 'treated' } },
    version: 7,
    sessionNote: 'Saved note',
    dentalStateVersion: 11,
  });
});

test('consultation conflict remains visible to the caller', async () => {
  globalThis.fetch = async () => ({
    ok: false,
    status: 409,
    json: async () => ({ detail: 'Version conflict. Please refresh.' }),
  });
  await assert.rejects(
    saveConsultationToApi('patient-uuid', {}, 3, 'note'),
    error => error.status === 409 && error.message.includes('Version conflict')
  );
});

test('report payload preserves UUID patient and active appointment identity', () => {
  const payload = buildClinicalReportPayload({
    patientId: '7e4b49de-b931-47f3-9454-d90c89c85a79',
    consultationId: 'c2887fcf-8f65-4976-8909-00e323d1db24',
    appointmentId: 'b2887fcf-8f65-4976-8909-00e323d1db24',
    toothId: '11',
    toothStatus: 'treated',
    symptoms: ['Pain'],
    doctorNotes: 'Short note',
    aiDraftReport: 'Draft',
    finalMedicalReport: 'Final',
  });
  assert.equal(payload.patient_id, '7e4b49de-b931-47f3-9454-d90c89c85a79');
  assert.equal(payload.consultation_id, 'c2887fcf-8f65-4976-8909-00e323d1db24');
  assert.equal(payload.appointment_id, 'b2887fcf-8f65-4976-8909-00e323d1db24');
});

test('report save errors remain visible to the caller', async () => {
  globalThis.fetch = async () => ({
    ok: false,
    status: 500,
    json: async () => ({ detail: 'Internal server error' }),
  });
  await assert.rejects(
    saveReport({ patient_id: 'patient-uuid' }),
    error => error.status === 500 && error.message.includes('Internal server error')
  );
});

test('clinical consultation hook has no LocalStorage persistence fallback', async () => {
  const source = await readFile(
    new URL('../hooks/useDentalSystem.js', import.meta.url),
    'utf8',
  );
  assert.doesNotMatch(
    source,
    /consultationStorage|\bloadConsultation\b|\bsaveConsultation\s*\(/,
  );
  assert.match(source, /setPersistenceMode\('error'\)/);
  assert.match(source, /Consultation backend load failed/);
});

test('consultation loading is UUID and authenticated-session gated', async () => {
  const hook = await readFile(
    new URL('../hooks/useDentalSystem.js', import.meta.url),
    'utf8',
  );
  const flow = await readFile(
    new URL('../pages/Doctor/ConsultationFlow.jsx', import.meta.url),
    'utf8',
  );
  assert.match(hook, /useAuth\(\)/);
  assert.match(hook, /isValidConsultationPatientId\(patientId\)/);
  assert.match(hook, /fetchConsultation\(patientId, sessionScope\)/);
  assert.match(hook, /invalidateConsultationSessionState\(\)/);
  assert.match(hook, /activeScopeRef\.current === operationScope/);
  assert.doesNotMatch(flow, /Patient record not found or connection error/);
  assert.match(flow, /consultationError \|\| 'The consultation could not be loaded\.'/);
});

test('finished UUID appointment lifecycle updates only the selected appointment', () => {
  const today = '2026-08-09';
  const finishedId = '30000000-0000-0000-0000-000000000001';
  const activeId = '30000000-0000-0000-0000-000000000002';
  const appointments = [
    { id: finishedId, patient_id: 'patient-a', date: today, status: 'pending' },
    { id: activeId, patient_id: 'patient-b', date: today, status: 'confirmed' },
  ];

  assert.deepEqual(
    markFinishedAppointment(appointments, {
      patientId: 'patient-a', appointmentId: finishedId, today,
    }),
    [{ ...appointments[0], status: 'completed' }, appointments[1]],
  );
  assert.equal(isCompletedAppointmentStatus('Completed'), true);
  assert.equal(isCompletedAppointmentStatus('finished'), true);
  assert.equal(isCompletedAppointmentStatus('confirmed'), false);
});

test('previous-note curtain is read-only, initially expanded, and independently toggled', async () => {
  const curtain = await readFile(
    new URL('../components/PreviousConsultationNoteCurtain.jsx', import.meta.url),
    'utf8',
  );
  const flow = await readFile(
    new URL('../pages/Doctor/ConsultationFlow.jsx', import.meta.url),
    'utf8',
  );

  assert.match(curtain, /useState\(true\)/);
  assert.match(curtain, /setExpanded\(value => !value\)/);
  assert.match(curtain, /previous-note-curtain__handle/);
  assert.match(curtain, /aria-expanded=\{expanded\}/);
  assert.match(curtain, /No notes from the previous consultation\./);
  assert.doesNotMatch(curtain, /textarea|contentEditable|saveSessionNote/);
  assert.match(flow, /PreviousConsultationNoteCurtain previousNote=\{lastConsultationNote\}/);
  assert.match(flow, /saveSessionNote\(noteDraft\)/);
});

test('finish UI waits for backend success and does not falsely finish on errors', async () => {
  const context = await readFile(
    new URL('../context/DataContext.jsx', import.meta.url),
    'utf8',
  );
  const flow = await readFile(
    new URL('../pages/Doctor/ConsultationFlow.jsx', import.meta.url),
    'utf8',
  );

  assert.match(context, /await appointmentApi\.finishAppointmentByPatient\(patientId, appointmentId\)[\s\S]*setAppointments\(prev => markFinishedAppointment/);
  assert.match(context, /setAppointments\(prev => markFinishedAppointment/);
  assert.match(flow, /await completeAppointmentByPatient\(patient\.id, appointmentId\)/);
  assert.match(flow, /await flushBeforeFinish\(finalNote\)[\s\S]*await completeAppointmentByPatient/);
  assert.match(flow, /finishInFlightRef\.current/);
  assert.match(flow, /disabled=\{isFinishing\}/);
  assert.match(flow, /catch \(err\)[\s\S]*cancelFinishBarrier\(\)/);
  assert.match(flow, /markConsultationFinished\(\)[\s\S]*setIsConsultationActive\(false\)/);
  assert.match(flow, /setIsConsultationActive\(false\)/);
  assert.match(flow, /catch \(err\)[\s\S]*could not be finished/);
});

test('finish flush barrier cancels debounce and includes note, symptoms and dental versions', async () => {
  const hook = await readFile(new URL('../hooks/useDentalSystem.js', import.meta.url), 'utf8');
  assert.match(hook, /flushBeforeFinish[\s\S]*lifecycleBarrierRef\.current = true/);
  assert.match(hook, /clearTimeout\(autosaveTimerRef\.current\)/);
  assert.match(hook, /persistConsultation\([\s\S]*toothDataRef\.current,[\s\S]*note,[\s\S]*symptomsRef\.current/);
  assert.match(hook, /saveConsultationToApi\([\s\S]*versionRef\.current[\s\S]*dentalStateVersionRef\.current/);
  assert.match(hook, /markConsultationFinished[\s\S]*initializationCompleteRef\.current = false/);
  assert.match(hook, /flushBeforeFinish[\s\S]*clinicalFindingsRef\.current/);
  assert.match(hook, /serializeClinicalFindings\(findingsByTooth\)/);
});

test('StrictMode-style load re-entry shares one GET and initialization sends no blank POST', async () => {
  resetConsultationApiStateForTests();
  let requests = 0;
  globalThis.fetch = async (_url, options = {}) => {
    requests += 1;
    assert.equal(options.method, undefined);
    await new Promise(resolve => setTimeout(resolve, 5));
    return {
      ok: true,
      status: 200,
      json: async () => ({
        consultationId: null,
        toothData: {},
        version: 0,
        dentalStateVersion: 0,
      }),
    };
  };

  const [first, second] = await Promise.all([
    fetchConsultation('strict-patient'),
    fetchConsultation('strict-patient'),
  ]);
  assert.equal(requests, 1);
  assert.deepEqual(first, second);

  const hook = await readFile(
    new URL('../hooks/useDentalSystem.js', import.meta.url),
    'utf8',
  );
  const initialization = hook.slice(
    hook.indexOf('async function initData()'),
    hook.indexOf('// Select a tooth by its FDI ID'),
  );
  assert.doesNotMatch(initialization, /saveConsultationToApi|persistConsultation\(/);
});

test('rapid saves are serialized and the second adopts the first returned version', async () => {
  resetConsultationApiStateForTests();
  primeConsultationSaveQueue('queue-patient', 4, 9);
  const versions = [];
  const dentalStateVersions = [];
  let active = 0;
  let maxActive = 0;
  globalThis.fetch = async (_url, options) => {
    active += 1;
    maxActive = Math.max(maxActive, active);
    const payload = JSON.parse(options.body);
    versions.push(payload.version);
    dentalStateVersions.push(payload.dentalStateVersion);
    await new Promise(resolve => setTimeout(resolve, 5));
    active -= 1;
    return {
      ok: true,
      status: 200,
      json: async () => ({
        version: payload.version + 1,
        dentalStateVersion: payload.dentalStateVersion + 1,
      }),
    };
  };

  const first = saveConsultationToApi('queue-patient', { 14: { status: 'caries' } }, 4);
  const second = saveConsultationToApi('queue-patient', { 14: { status: 'treated' } }, 4);
  const results = await Promise.all([first, second]);

  assert.equal(maxActive, 1);
  assert.deepEqual(versions, [4, 5]);
  assert.deepEqual(dentalStateVersions, [9, 10]);
  assert.deepEqual(results.map(result => result.version), [5, 6]);
  assert.deepEqual(results.map(result => result.dentalStateVersion), [10, 11]);
});

test('409 refresh preserves edits, blocks queued writes, and explicit retry uses authoritative version', async () => {
  resetConsultationApiStateForTests();
  primeConsultationSaveQueue('conflict-patient', 2, 6);
  const unsaved = { 16: { status: 'missing' }, 22: { status: 'treated' } };
  const postVersions = [];
  const dentalStateVersions = [];
  let postCount = 0;
  globalThis.fetch = async (_url, options = {}) => {
    if (options.method === 'POST') {
      postCount += 1;
      const payload = JSON.parse(options.body);
      postVersions.push(payload.version);
      dentalStateVersions.push(payload.dentalStateVersion);
      if (postCount === 1) {
        return {
          ok: false,
          status: 409,
          json: async () => ({ detail: 'Version conflict. Please refresh.' }),
        };
      }
      return {
        ok: true,
        status: 200,
        json: async () => ({
          version: payload.version + 1,
          dentalStateVersion: payload.dentalStateVersion + 1,
        }),
      };
    }
    return {
      ok: true,
      status: 200,
      json: async () => ({
        consultationId: 'server-consultation',
        toothData: { 16: { status: 'healthy' } },
        version: 3,
        dentalStateVersion: 7,
      }),
    };
  };

  const originalEdits = structuredClone(unsaved);
  const conflict = await saveConsultationToApi(
    'conflict-patient', unsaved, 2, undefined, 6,
  )
    .then(() => null, error => error);
  assert.equal(conflict.status, 409);
  assert.equal(conflict.authoritative.version, 3);
  assert.equal(conflict.authoritative.dentalStateVersion, 7);
  assert.deepEqual(unsaved, originalEdits);

  await assert.rejects(
    saveConsultationToApi('conflict-patient', unsaved, 2),
    error => error.status === 409 && error.message.includes('preserved'),
  );
  assert.equal(postCount, 1);

  resumeConsultationSaveQueue(
    'conflict-patient',
    conflict.authoritative.version,
    conflict.authoritative.dentalStateVersion,
  );
  const retried = await saveConsultationToApi(
    'conflict-patient', unsaved, 2, undefined, 6,
  );
  assert.equal(retried.version, 4);
  assert.equal(retried.dentalStateVersion, 8);
  assert.deepEqual(postVersions, [2, 3]);
  assert.deepEqual(dentalStateVersions, [6, 7]);
});

test('conflict handling keeps consultation available and never replaces in-memory tooth data', async () => {
  const hook = await readFile(
    new URL('../hooks/useDentalSystem.js', import.meta.url),
    'utf8',
  );
  const conflictHandler = hook.slice(
    hook.indexOf('const handleSaveFailure'),
    hook.indexOf('const persistConsultation'),
  );
  assert.doesNotMatch(conflictHandler, /setToothData|setPersistenceMode\('error'\)/);
  assert.match(conflictHandler, /unsaved dental changes are preserved/);
  assert.match(conflictHandler, /authoritative\.version/);
  assert.match(conflictHandler, /authoritative\.dentalStateVersion/);
});
