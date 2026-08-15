import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { createNotificationsService } from './notificationsApi.js';
import {
  isUnreadNotification,
  markReadOptimistically,
  rollbackNotificationRead,
} from './notificationState.js';

test('notification RPC failure rejects instead of returning fabricated rows', async () => {
  const service = createNotificationsService({ supabaseClient: {
    rpc: async () => ({ data: null, error: { code: '503' } }),
  } });
  await assert.rejects(service.listMyNotifications(), /temporarily unavailable/);
});

test('notification mark-read RPC failure rejects instead of reporting fake success', async () => {
  const service = createNotificationsService({ supabaseClient: {
    rpc: async () => ({ data: null, error: { code: '500' } }),
  } });
  await assert.rejects(service.markMyNotificationRead('server-id'), /temporarily unavailable/);
});

test('optimistic notification read state can be rolled back exactly', () => {
  const original = [
    { id: 'server-1', title: 'Persisted', read_at: null },
    { id: 'server-2', title: 'Other', read_at: null },
  ];
  const optimistic = markReadOptimistically(original, 'server-1');
  assert.equal(isUnreadNotification(optimistic.next[0]), false);
  assert.deepEqual(
    rollbackNotificationRead(optimistic.next, optimistic.previous),
    original,
  );
});

test('notification runtime has no fabricated rows or fake stream implementation', async () => {
  const source = await readFile(new URL('./notificationsApi.js', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /fallbackNotifications|createNotificationsStream|notif-1|clinic_token|fetch\s*\(|\/api\/notifications/);
});

test('routed patient portal renders only a truthful unavailable state', async () => {
  const source = await readFile(
    new URL('../pages/Patient/PatientDashboard.jsx', import.meta.url),
    'utf8',
  );
  assert.match(source, /Patient portal is not available yet/);
  assert.doesNotMatch(
    source,
    /Eleanor Voss|Dental Clinical Summary|Dental X-Ray Report|gum health has improved|X-Ray Analysis is ready/,
  );
  assert.doesNotMatch(source, /const reports\s*=|useData\(/);
});

test('active router does not import dormant mock persistence sources', async () => {
  const source = await readFile(new URL('../App.jsx', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /mockData|data\/patients|consultationStorage/);
});
