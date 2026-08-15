import { getSupabaseClient } from '../lib/supabaseClient.js';

const unavailable = 'Notifications are temporarily unavailable. Please try again.';
const unwrap = ({ data, error }) => { if (error) throw new Error(unavailable, { cause: error }); return data; };

export function createNotificationsService({ supabaseClient } = {}) {
  const client = () => supabaseClient || getSupabaseClient();
  return {
    async listMyNotifications({ limit = 50, beforeCreatedAt = null, beforeId = null } = {}) {
      const data = unwrap(await client().rpc('list_my_notifications', {
        p_limit: limit, p_before_created_at: beforeCreatedAt, p_before_id: beforeId,
      }));
      if (!Array.isArray(data)) throw new Error(unavailable);
      return data.map((row) => ({
        id: row.id, title: row.title, body: row.body ?? row.message ?? '', type: row.type,
        appointment_id: row.appointmentId ?? row.appointment_id ?? null,
        created_at: row.createdAt ?? row.created_at,
        read_at: row.readAt ?? row.read_at ?? null,
      }));
    },
    async getMyUnreadNotificationCount() {
      const count = Number(unwrap(await client().rpc('get_my_unread_notification_count')));
      if (!Number.isSafeInteger(count) || count < 0) throw new Error(unavailable);
      return count;
    },
    async markMyNotificationRead(notificationId) {
      if (!notificationId) throw new Error('A notification ID is required.');
      return unwrap(await client().rpc('mark_my_notification_read', { p_notification_id: notificationId }));
    },
    async markAllMyNotificationsRead() {
      return unwrap(await client().rpc('mark_all_my_notifications_read'));
    },
  };
}

export const notificationsService = createNotificationsService();
