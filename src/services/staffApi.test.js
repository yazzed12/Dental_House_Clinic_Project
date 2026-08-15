import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { createDoctorListService } from './staffApi.js';

test('Supabase Doctor lookup uses only the eligible Doctors RPC and maps its safe result', async () => {
  const calls = [];
  const listDoctors = createDoctorListService({
    provider: 'supabase',
    supabaseClient: {
      async rpc(name) {
        calls.push(name);
        return {
          data: [{
            id: 'doctor-1',
            full_name: 'Dr Safe',
            specialization: 'Cardiology',
            unexpected_field: 'not forwarded',
          }],
          error: null,
        };
      },
    },
    legacyRequest: async () => {
      throw new Error('FastAPI must not be called in Supabase mode');
    },
  });

  assert.deepEqual(await listDoctors(), [{
    id: 'doctor-1',
    name: 'Dr Safe',
    specialization: 'Cardiology',
  }]);
  assert.deepEqual(calls, ['get_eligible_doctors']);
});

test('Supabase Doctor lookup distinguishes an RPC failure from a valid empty list', async () => {
  const emptyList = createDoctorListService({
    provider: 'supabase',
    supabaseClient: { rpc: async () => ({ data: [], error: null }) },
  });
  assert.deepEqual(await emptyList(), []);

  const failedList = createDoctorListService({
    provider: 'supabase',
    supabaseClient: { rpc: async () => ({ data: null, error: { message: 'denied' } }) },
  });
  await assert.rejects(failedList(), /denied/);
});

test('legacy Doctor lookup preserves the FastAPI rollback path', async () => {
  const calls = [];
  const response = [{ id: 'legacy-doctor', name: 'Legacy Doctor' }];
  const listDoctors = createDoctorListService({
    provider: 'legacy',
    legacyRequest: async (path) => {
      calls.push(path);
      return response;
    },
  });

  assert.equal(await listDoctors(), response);
  assert.deepEqual(calls, ['/doctors']);
});

test('Supabase Doctor lookup has no direct users read or clinic token dependency', async () => {
  const source = await readFile(new URL('./staffApi.js', import.meta.url), 'utf8');
  assert.match(source, /rpc\('get_eligible_doctors'\)/);
  assert.doesNotMatch(source, /\.from\(['"]users['"]\)/);
  assert.doesNotMatch(source, /clinic_token/);
});
