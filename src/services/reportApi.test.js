import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

import { buildAIReportGenerationPayload, buildClinicalReportPayload, createReportPersistenceService, getAiAuthHeaders } from './reportApi.js';

const report = {
  patient_id: 'patient-1', consultation_id: 'consultation-1',
  appointment_id: 'appointment-1', tooth_id: '11', tooth_status: 'caries',
  symptoms: ['Pain'], doctor_notes: 'Note', ai_draft_report: 'Draft',
  final_medical_report: 'Final', status: 'approved',
};

test('AI transport uses the current Supabase access token', async () => {
  const headers = await getAiAuthHeaders({
    provider: 'supabase',
    supabaseClient: {
      auth: { getSession: async () => ({ data: { session: { access_token: 'current-token' } }, error: null }) },
    },
  });
  assert.deepEqual(headers, {
    Authorization: 'Bearer current-token',
    'Content-Type': 'application/json',
  });
});

test('AI transport fails closed without a Supabase session', async () => {
  await assert.rejects(
    getAiAuthHeaders({
      provider: 'supabase',
      supabaseClient: { auth: { getSession: async () => ({ data: { session: null }, error: null }) } },
    }),
    error => error.status === 401,
  );
});

test('AI generation payload includes all isolated tooth findings and authoritative consultation data', () => {
  const findings = [
    { toothId: '11', toothStatus: 'problem', symptoms: ['Pain'], toothNote: 'Deep lesion' },
    { toothId: '24', toothStatus: 'treated', symptoms: ['Sensitivity'], toothNote: '' },
  ];
  const payload = buildAIReportGenerationPayload({
    patient: { id: 'patient-1', name: 'Ada', dateOfBirth: '1990-02-03', age: 36, gender: 'Female', phone: 'private' },
    consultationDate: '2026-08-14',
    clinicalFindings: findings,
    consultationNote: 'Actual session note',
    performedProcedures: [{ id: 'selection-1', procedureId: 'procedure-1', name: 'Cleaning', quantity: 2 }],
    doctor: { name: 'Dr Noor', specialty: 'Dentistry', clinic: { name: 'Clinic' } },
    aiInstructions: ' Keep this concise. ',
  });
  assert.deepEqual(payload.clinicalFindings, findings);
  assert.deepEqual(payload.clinicalFindings[0].symptoms, ['Pain']);
  assert.deepEqual(payload.clinicalFindings[1].symptoms, ['Sensitivity']);
  assert.equal(payload.consultationNote, 'Actual session note');
  assert.equal(payload.aiInstructions, 'Keep this concise.');
  assert.deepEqual(payload.performedProcedures, [
    { id: 'selection-1', procedureId: 'procedure-1', name: 'Cleaning', quantity: 2 },
  ]);
  assert.equal(payload.performedProcedures[0].toothId, undefined);
  assert.deepEqual(payload.patient, { id: 'patient-1', name: 'Ada', age: 36, gender: 'Female' });
  assert.equal(payload.examinationDate, '2026-08-14');
  assert.deepEqual(payload.doctor, { name: 'Dr Noor', specialty: 'Dentistry', clinic: { name: 'Clinic' } });
});

test('AI generation supports one finding and no optional instructions or procedures', () => {
  const payload = buildAIReportGenerationPayload({
    patient: { id: 'patient-1', name: 'Ada' },
    clinicalFindings: [{ toothId: '11', toothStatus: 'healthy', symptoms: [], toothNote: '' }],
  });
  assert.equal(payload.clinicalFindings.length, 1);
  assert.equal(payload.aiInstructions, null);
  assert.deepEqual(payload.performedProcedures, []);
});

test('consultation generation uses all findings regardless of current selected tooth', async () => {
  const source = await readFile(new URL('../pages/Doctor/ConsultationFlow.jsx', import.meta.url), 'utf8');
  const generation = source.slice(source.indexOf('const handleGenerateReport'), source.indexOf('const handleFinalizeReport'));
  assert.match(generation, /clinicalFindings: structuredFindings/);
  assert.match(generation, /consultationNote: savedSession\?\.sessionNote \?\? sessionNote/);
  assert.match(generation, /performedProcedures: procedureSummary\.items/);
  assert.match(generation, /await saveCurrentSession\(\)/);
  assert.doesNotMatch(generation, /selectedTooth|selectedSymptoms|medicalHistory|jawTeethStatus/);
});

test('Supabase report save sends controlled consultation-linked RPC payload', async () => {
  const calls = [];
  const service = createReportPersistenceService({
    provider: 'supabase',
    supabaseClient: { rpc: async (name, args) => {
      calls.push([name, args]);
      return { data: { id: 'report-1' }, error: null };
    } },
  });
  assert.equal((await service.saveReport(report)).id, 'report-1');
  assert.equal(calls[0][0], 'save_clinical_report');
  assert.equal(calls[0][1].p_consultation_id, 'consultation-1');
  assert.equal(calls[0][1].p_patient_id, 'patient-1');
  assert.deepEqual(calls[0][1].p_symptoms, ['Pain']);
  assert.equal(calls[0][1].p_doctor_id, undefined);
  assert.equal(calls[0][1].p_humanized_report, '');
});

test('report payload and save RPC preserve a generated humanized derivative separately', async () => {
  const payload = buildClinicalReportPayload({
    patientId: 'patient-1', consultationId: 'consultation-1', appointmentId: 'appointment-1',
    toothId: null, toothStatus: null, symptoms: [], doctorNotes: 'Note',
    aiDraftReport: 'Authoritative report', finalMedicalReport: 'Authoritative report',
    humanizedReport: 'Patient-friendly derivative', status: 'draft',
  });
  assert.equal(payload.final_medical_report, 'Authoritative report');
  assert.equal(payload.humanized_report, 'Patient-friendly derivative');

  const calls = [];
  const service = createReportPersistenceService({ provider: 'supabase', supabaseClient: {
    rpc: async (name, args) => { calls.push([name, args]); return { data: { id: 'report-1' }, error: null }; },
  } });
  await service.saveReport(payload);
  assert.equal(calls[0][1].p_final_medical_report, 'Authoritative report');
  assert.equal(calls[0][1].p_humanized_report, 'Patient-friendly derivative');
  assert.equal(calls[0][1].p_status, 'draft');
});

test('Supabase report update and patient read use hardened RPCs', async () => {
  const calls = [];
  const service = createReportPersistenceService({
    provider: 'supabase',
    supabaseClient: { rpc: async (name, args) => {
      calls.push([name, args]);
      return { data: name === 'get_patient_clinical_reports' ? [] : { id: 'report-1' }, error: null };
    } },
  });
  await service.updateReport('report-1', { humanized_report: 'Friendly' });
  assert.deepEqual(await service.getPatientReports('patient-1'), []);
  assert.deepEqual(calls, [
    ['update_clinical_report', { p_report_id: 'report-1', p_updates: { humanized_report: 'Friendly' } }],
    ['get_patient_clinical_reports', { p_patient_id: 'patient-1' }],
  ]);
});

test('structured finalization sends only Migration 020 review arguments', async () => {
  const calls = [];
  const service = createReportPersistenceService({ provider: 'supabase', supabaseClient: {
    rpc: async (name, args) => { calls.push([name, args]); return { data: { id: 'report-1' }, error: null }; },
  } });
  const assessments = [{ toothId: '11', clinicalDescription: null, diagnosis: null, icd10: null, treatmentPlan: null }];
  await service.finalizeReport('report-1', assessments, '', 'Clinical Dental Report');
  assert.deepEqual(calls[0], ['finalize_clinical_report', {
    p_report_id: 'report-1', p_assessments: assessments,
    p_clinical_summary: '', p_final_narrative: 'Clinical Dental Report',
  }]);
});

test('report RPC errors remain distinct from valid empty reads', async () => {
  const empty = createReportPersistenceService({
    provider: 'supabase', supabaseClient: { rpc: async () => ({ data: [], error: null }) },
  });
  assert.deepEqual(await empty.getPatientReports('patient-1'), []);
  const denied = createReportPersistenceService({
    provider: 'supabase', supabaseClient: { rpc: async () => ({ data: null, error: { code: '42501' } }) },
  });
  await assert.rejects(denied.saveReport(report),
    error => error.code === 'REPORT_FORBIDDEN' && error.status === 403);
});

test('Supabase persistence is isolated from legacy AI and clinic-token transport', async () => {
  const source = await readFile(new URL('./reportApi.js', import.meta.url), 'utf8');
  const persistence = source.slice(source.indexOf('export function createReportPersistenceService'));
  const supabase = persistence.slice(
    persistence.indexOf("if (provider !== 'supabase')"),
    persistence.indexOf('const reportPersistenceService'),
  );
  assert.doesNotMatch(supabase, /clinic_token|fetchLegacy\(|\/reports/);
  assert.match(source, /generateAIReport[\s\S]*\/ai\/generate-report/);
  assert.match(source, /humanizeReport[\s\S]*\/ai\/humanize-report/);
});
