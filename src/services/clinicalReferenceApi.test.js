import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { createSymptomService } from './clinicalReferenceApi.js';


const rpcClient = (handler) => ({ rpc: handler });

test('symptom list uses Supabase RPC and preserves successful empty results', async () => {
  const calls = [];
  const service = createSymptomService({
    supabaseClient: rpcClient(async (name, args) => {
      calls.push([name, args]);
      return { data: [], error: null };
    }),
  });
  assert.deepEqual(await service.listSymptoms(), []);
  assert.deepEqual(calls, [['list_active_symptoms', undefined]]);
});

test('symptom list preserves the minimal id/name projection', async () => {
  const rows = [
    { id: 'symptom-1', name: 'Cold Sensitivity' },
    { id: 'symptom-2', name: 'Sharp Pain' },
  ];
  const service = createSymptomService({
    supabaseClient: rpcClient(async () => ({ data: rows, error: null })),
  });
  assert.deepEqual(await service.listSymptoms(), rows);
  assert.deepEqual(Object.keys((await service.listSymptoms())[0]), ['id', 'name']);
});

test('custom symptom sends only its name to create/reactivate RPC', async () => {
  let call;
  const service = createSymptomService({
    supabaseClient: rpcClient(async (name, args) => {
      call = [name, args];
      return { data: { id: 'symptom-1', name: 'Sharp Pain' }, error: null };
    }),
  });
  const result = await service.createSymptom({
    name: ' Sharp Pain ',
    created_by: 'client-must-not-control-this',
  });
  assert.deepEqual(call, [
    'create_or_reactivate_symptom', { p_name: ' Sharp Pain ' },
  ]);
  assert.deepEqual(result, { id: 'symptom-1', name: 'Sharp Pain' });
});

test('authorization and transport failures are distinct from an empty list', async () => {
  const forbidden = createSymptomService({
    supabaseClient: rpcClient(async () => ({ data: null, error: { code: '42501' } })),
  });
  await assert.rejects(
    forbidden.listSymptoms(),
    (error) => error.code === 'SYMPTOM_FORBIDDEN' && error.kind === 'authorization',
  );

  const unavailable = createSymptomService({
    supabaseClient: rpcClient(async () => ({ data: null, error: { code: 'XX000' } })),
  });
  await assert.rejects(
    unavailable.listSymptoms(),
    (error) => error.code === 'SYMPTOM_RPC_FAILED' && error.kind === 'transport',
  );
});

test('blank-name validation maps to a stable frontend error', async () => {
  const service = createSymptomService({
    supabaseClient: rpcClient(async () => ({ data: null, error: { code: '22023' } })),
  });
  await assert.rejects(
    service.createSymptom({ name: '   ' }),
    (error) => error.code === 'SYMPTOM_NAME_REQUIRED' && error.kind === 'validation',
  );
});

test('Symptoms feature has no FastAPI or clinic-token transport and UI surfaces failures', async () => {
  const serviceSource = await readFile(new URL('./clinicalReferenceApi.js', import.meta.url), 'utf8');
  const flowSource = await readFile(new URL('../pages/Doctor/ConsultationFlow.jsx', import.meta.url), 'utf8');
  const symptomSection = serviceSource.slice(serviceSource.indexOf('export class SymptomApiError'));
  assert.doesNotMatch(symptomSection, /clinic_token|\/clinical\/symptoms|apiRequest\(/);
  assert.match(symptomSection, /getSupabaseClient/);
  assert.match(flowSource, /setSymptomsError\(err\?\.message/);
  assert.match(flowSource, /symptomsError \? \(/);
  assert.match(flowSource, /!symptomsError/);
});
