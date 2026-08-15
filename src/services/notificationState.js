export const isUnreadNotification = (notification) => notification.read_at == null;

export function isCurrentNotificationRequest({ requestGeneration, currentGeneration, requestUserId, currentUserId }) {
  return requestGeneration === currentGeneration && requestUserId === currentUserId;
}

export function markReadOptimistically(items, id, readAt = new Date().toISOString()) {
  const previous = items.find((item) => String(item.id) === String(id));
  return { previous, next: items.map((item) => String(item.id) === String(id)
    ? { ...item, read_at: item.read_at ?? readAt } : item) };
}

export function rollbackNotificationRead(items, previous) {
  if (!previous) return items;
  return items.map((item) => String(item.id) === String(previous.id) ? previous : item);
}

export function markAllReadOptimistically(items, readAt = new Date().toISOString()) {
  return items.map((item) => ({ ...item, read_at: item.read_at ?? readAt }));
}
