import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import * as patientApi from './patientApi.js';

function createMockSupabase(responses = {}) {
  return {
    from(table) {
      assert.equal(table, 'patients');
      const builder = {
        select() { return builder; },
        neq(col, val) {
          builder.neqCol = col;
          builder.neqVal = val;
          return builder;
        },
        eq(col, val) {
          builder.eqCol = col;
          builder.eqVal = val;
          return builder;
        },
        insert(data) {
          builder.insertedData = data;
          return builder;
        },
        update(data) {
          builder.updatedData = data;
          return builder;
        },
        async single() {
          if (responses.singleError) return { data: null, error: responses.singleError };
          return { data: responses.singleData || null, error: null };
        },
        then(resolve) {
          if (responses.listError) resolve({ data: null, error: responses.listError });
          else resolve({ data: responses.listData || [], error: null });
        },
      };
      return builder;
    },
    async rpc(funcName, params) {
      assert.equal(funcName, 'safe_delete_patient');
      if (responses.rpcError) return { data: null, error: responses.rpcError };
      return { data: responses.rpcData || { status: 'success' }, error: null };
    },
  };
}

test('patientApi does not import or use httpClient transport', async () => {
  const source = await readFile(new URL('./patientApi.js', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /httpClient|apiRequest|\/api\/patients/);
  assert.match(source, /getSupabaseClient/);
});

test('listPatients excludes archived patients and maps snake_case fields', async () => {
  const mockClient = createMockSupabase({
    listData: [
      {
        id: 'patient-1',
        name: 'Jane Doe',
        age: 30,
        phone: '555-1234',
        gender: 'Female',
        status: 'Active',
        condition: 'Routine',
        last_visit: '2026-08-01',
        blood_type: 'O+',
      },
    ],
  });
  const patients = await patientApi.listPatients(mockClient);
  assert.equal(patients.length, 1);
  assert.equal(patients[0].id, 'patient-1');
  assert.equal(patients[0].lastVisit, '2026-08-01');
  assert.equal(patients[0].bloodType, 'O+');
});

test('getPatient allows retrieving an archived patient by ID', async () => {
  const mockClient = createMockSupabase({
    singleData: {
      id: 'patient-archived',
      name: 'John Old',
      status: 'Archived',
      last_visit: '2025-01-01',
      blood_type: 'A-',
    },
  });
  const patient = await patientApi.getPatient('patient-archived', mockClient);
  assert.equal(patient.id, 'patient-archived');
  assert.equal(patient.status, 'Archived');
  assert.equal(patient.lastVisit, '2025-01-01');
});

test('createPatient returns database-generated UUID and mapped fields', async () => {
  const mockClient = createMockSupabase({
    singleData: {
      id: 'generated-uuid-1234',
      name: 'New Patient',
      age: 25,
      last_visit: '2026-08-10',
      blood_type: 'B+',
    },
  });
  const created = await patientApi.createPatient(
    {
      name: 'New Patient',
      age: 25,
      lastVisit: '2026-08-10',
      bloodType: 'B+',
    },
    mockClient
  );
  assert.equal(created.id, 'generated-uuid-1234');
  assert.equal(created.name, 'New Patient');
  assert.equal(created.lastVisit, '2026-08-10');
});

test('updatePatient maps updates and returns status success contract', async () => {
  const mockClient = createMockSupabase({
    singleData: {
      id: 'patient-1',
      name: 'Updated Patient',
      age: 31,
      last_visit: '2026-08-10',
      blood_type: 'O+',
    },
  });
  const res = await patientApi.updatePatient(
    'patient-1',
    {
      age: 31,
      lastVisit: '2026-08-10',
    },
    mockClient
  );
  assert.equal(res.status, 'success');
  assert.equal(res.patient.id, 'patient-1');
  assert.equal(res.patient.age, 31);
});

test('deletePatient invokes safe_delete_patient RPC', async () => {
  const mockClient = createMockSupabase({
    rpcData: {
      status: 'success',
      action: 'archived',
      message: 'Patient archived safely to preserve clinical history.',
    },
  });
  const res = await patientApi.deletePatient('patient-1', mockClient);
  assert.equal(res.status, 'success');
  assert.equal(res.action, 'archived');
});

test('patientApi error handling translates Supabase errors correctly', async () => {
  const mockClientPermission = createMockSupabase({
    singleError: { code: '42501', message: 'permission denied for table patients' },
  });
  await assert.rejects(
    patientApi.getPatient('restricted-id', mockClientPermission),
    /Insufficient permissions/
  );

  const mockClientNotFound = createMockSupabase({
    singleError: { code: 'P0002', message: 'row not found' },
  });
  await assert.rejects(
    patientApi.getPatient('missing-id', mockClientNotFound),
    /Patient not found/
  );
});
