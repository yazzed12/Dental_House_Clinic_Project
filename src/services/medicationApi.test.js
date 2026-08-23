import assert from 'node:assert/strict';
import test from 'node:test';

import { createMedicationService } from './medicationApi.js';
import { buildAIReportGenerationPayload } from './reportApi.js';

const fakeClient = calls => ({ rpc: async (name, args) => {
  calls.push({ name, args });
  return {
    data: name === 'search_dental_medications'
      ? [{ id: 'm-1', brandName: 'Fixture', verificationStatus: 'verified', retiredMetadata: 'ignored' }]
      : { id: 'result' },
    error: null,
  };
} });

test('Supabase medication service preserves narrow RPC boundaries', async () => {
  const calls = [];
  const service = createMedicationService({ provider: 'supabase', supabaseClient: fakeClient(calls) });
  const results = await service.searchMedications('synthetic', 12);
  await service.getEffectiveMedicationPreset('m-1');
  await service.savePrescriptionDraft('c-1', 3, [{ medicationId: 'm-1' }]);
  await service.approvePrescription('p-1', 4);
  assert.deepEqual(results, [{ id: 'm-1', brandName: 'Fixture', verificationStatus: 'verified' }]);
  assert.deepEqual(calls, [
    { name: 'search_dental_medications', args: { p_query: 'synthetic', p_limit: 12 } },
    { name: 'get_effective_medication_preset', args: { p_medication_id: 'm-1' } },
    { name: 'save_prescription_draft', args: { p_consultation_id: 'c-1', p_expected_version: 3, p_items: [{ medicationId: 'm-1' }] } },
    { name: 'approve_prescription', args: { p_prescription_id: 'p-1', p_expected_version: 4 } },
  ]);
});

test('custom medication creation cannot claim imported/global authority', async () => {
  const calls = [];
  const service = createMedicationService({ provider: 'supabase', supabaseClient: fakeClient(calls) });
  await service.createCustomMedication({
    brand_name: 'Fixture', generic_name: '', strength: '1 unit', dosage_form: 'Fixture Form',
    route: 'Fixture Route', category: '', manufacturer: '', catalog_scope: 'global',
    verification_status: 'verified',
  });
  assert.deepEqual(calls[0], { name: 'create_custom_medication', args: {
    p_brand_name: 'Fixture', p_generic_name: null, p_strength: '1 unit',
    p_dosage_form: 'Fixture Form', p_route: 'Fixture Route', p_category: null,
    p_manufacturer: null,
  } });
});

test('AI generation payload includes an exact approved prescription and excludes drafts', () => {
  const approved = {
    id: 'p-1', status: 'approved', retiredMetadata: 'ignored',
    items: [{ brandName: 'Fixture', dose: 'Doctor value', retiredMetadata: 'ignored' }],
  };
  const payload = buildAIReportGenerationPayload({
    patient: { id: 'patient-1', name: 'Patient' }, consultationId: 'consultation-1',
    clinicalFindings: [], performedProcedures: [], doctor: {}, approvedPrescription: approved,
  });
  assert.equal(payload.consultationId, 'consultation-1');
  assert.deepEqual(payload.approvedPrescription, {
    id: 'p-1', status: 'approved', items: [{ brandName: 'Fixture', dose: 'Doctor value' }],
  });
  assert.equal(buildAIReportGenerationPayload({
    patient: {}, clinicalFindings: [], performedProcedures: [], doctor: {},
    approvedPrescription: { status: 'draft', items: [] },
  }).approvedPrescription, null);
});
