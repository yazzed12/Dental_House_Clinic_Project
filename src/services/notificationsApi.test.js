import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { createNotificationsService } from './notificationsApi.js';
import { isCurrentNotificationRequest } from './notificationState.js';

test('notification service maps the exact four RPC contracts without recipient parameters', async () => {
  const calls = [];
  const client = { rpc: async (name, args) => {
    calls.push([name, args]);
    if (name === 'list_my_notifications') return { data: [{ id: 'uuid-a', title: 'A', body: 'Body', type: 'appointment_arrived', createdAt: '2026-08-15T00:00:00Z', readAt: null }], error: null };
    if (name === 'get_my_unread_notification_count') return { data: 1, error: null };
    return { data: {}, error: null };
  } };
  const service = createNotificationsService({ supabaseClient: client });
  const rows = await service.listMyNotifications();
  assert.equal(rows[0].read_at, null);
  assert.equal(await service.getMyUnreadNotificationCount(), 1);
  await service.markMyNotificationRead('uuid-a');
  await service.markAllMyNotificationsRead();
  assert.deepEqual(calls.map(([name]) => name), ['list_my_notifications', 'get_my_unread_notification_count', 'mark_my_notification_read', 'mark_all_my_notifications_read']);
  assert.deepEqual(calls[2][1], { p_notification_id: 'uuid-a' });
  assert.equal(calls.filter(([name]) => name === 'mark_all_my_notifications_read').length, 1);
  assert.doesNotMatch(JSON.stringify(calls), /recipient|doctor|patient|clinic|role/i);
});

test('active bell is session gated and generation protected with no legacy polling', async () => {
  const hook = await readFile(new URL('../hooks/useNotifications.js', import.meta.url), 'utf8');
  const topbar = await readFile(new URL('../components/Topbar.jsx', import.meta.url), 'utf8');
  assert.match(hook, /!authLoading.*authProvider === 'supabase'.*user\?\.id/);
  assert.match(hook, /isCurrentNotificationRequest/);
  assert.match(hook, /setNotifications\(\[\]\).*setUnreadCount\(0\)/s);
  assert.match(hook, /window\.addEventListener\('focus'/);
  assert.doesNotMatch(hook + topbar, /setInterval|clinic_token|\/api\/notifications|recipient_user_id|doctor_id/);
  assert.match(topbar, /item\.read_at == null/);
  assert.match(topbar, /appointment_arrived/);
});

test('Doctor A response is rejected after logout and Doctor B switch', () => {
  assert.equal(isCurrentNotificationRequest({
    requestGeneration: 1, currentGeneration: 3,
    requestUserId: 'doctor-a', currentUserId: 'doctor-b',
  }), false);
  assert.equal(isCurrentNotificationRequest({
    requestGeneration: 3, currentGeneration: 3,
    requestUserId: 'doctor-b', currentUserId: 'doctor-b',
  }), true);
});
