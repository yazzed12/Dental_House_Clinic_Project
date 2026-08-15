import assert from 'node:assert/strict';
import test from 'node:test';

import { createDashboardService } from './dashboardApi.js';

test('dashboard uses the current Supabase bearer token without clinic_token fallback', async () => {
  const calls = [];
  const service = createDashboardService({
    provider: 'supabase',
    supabaseClient: { auth: { getSession: async () => ({
      data: { session: { access_token: 'supabase-token' } }, error: null,
    }) } },
    request: async (path, options) => { calls.push([path, options]); return { ok: true }; },
  });
  assert.deepEqual(await service.getDashboard(), { ok: true });
  assert.deepEqual(calls, [['/dashboard', { headers: {
    Authorization: 'Bearer supabase-token', 'Content-Type': 'application/json',
  } }]]);
});

test('dashboard fails closed before transport when the Supabase session is missing', async () => {
  let requested = false;
  const service = createDashboardService({
    provider: 'supabase',
    supabaseClient: { auth: { getSession: async () => ({ data: { session: null }, error: null }) } },
    request: async () => { requested = true; },
  });
  await assert.rejects(service.getDashboard(), error => error.status === 401);
  assert.equal(requested, false);
});

test('legacy dashboard mode preserves the explicit legacy token path', async () => {
  const original = globalThis.localStorage;
  globalThis.localStorage = { getItem: key => key === 'clinic_token' ? 'legacy-token' : null };
  try {
    let options;
    const service = createDashboardService({
      provider: 'legacy', request: async (_path, value) => { options = value; return {}; },
    });
    await service.getDashboard();
    assert.equal(options.headers.Authorization, 'Bearer legacy-token');
  } finally {
    globalThis.localStorage = original;
  }
});
