import { useCallback, useEffect, useRef, useState } from 'react';
import { notificationsService } from '../services/notificationsApi.js';
import { isCurrentNotificationRequest, isUnreadNotification, markAllReadOptimistically, markReadOptimistically, rollbackNotificationRead } from '../services/notificationState.js';

const STALE_AFTER_MS = 60_000;

export function useNotifications({ user, authLoading, authProvider }) {
  const [notifications, setNotifications] = useState([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const [loading, setLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');
  const [visibleUserId, setVisibleUserId] = useState(null);
  const generation = useRef(0);
  const identity = useRef(null);
  const inFlight = useRef(null);
  const lastLoadedAt = useRef(0);
  const mounted = useRef(true);
  const ready = !authLoading && authProvider === 'supabase' && Boolean(user?.id);
  const userId = ready ? String(user.id) : null;

  const clear = useCallback(() => {
    generation.current += 1; identity.current = null; inFlight.current = null; lastLoadedAt.current = 0;
    setNotifications([]); setUnreadCount(0); setLoading(false); setRefreshing(false); setError(''); setVisibleUserId(null);
  }, []);

  const load = useCallback(async ({ force = false } = {}) => {
    if (!userId || identity.current !== userId) return false;
    if (!force && Date.now() - lastLoadedAt.current < STALE_AFTER_MS) return true;
    if (inFlight.current) return inFlight.current;
    const requestGeneration = ++generation.current;
    const requestUserId = userId;
    const initial = lastLoadedAt.current === 0;
    if (initial) setLoading(true); else setRefreshing(true);
    let request;
    request = Promise.all([
      notificationsService.listMyNotifications(),
      notificationsService.getMyUnreadNotificationCount(),
    ]).then(([rows, count]) => {
      if (!mounted.current || !isCurrentNotificationRequest({ requestGeneration, currentGeneration: generation.current, requestUserId, currentUserId: identity.current })) return false;
      setNotifications(rows); setUnreadCount(count); setError(''); lastLoadedAt.current = Date.now();
      return true;
    }).catch((loadError) => {
      if (mounted.current && generation.current === requestGeneration && identity.current === requestUserId) {
        setError(loadError.message || 'Notifications are temporarily unavailable. Please try again.');
      }
      return false;
    }).finally(() => {
      if (inFlight.current === request) inFlight.current = null;
      if (mounted.current && generation.current === requestGeneration && identity.current === requestUserId) {
        setLoading(false); setRefreshing(false);
      }
    });
    inFlight.current = request;
    return request;
  }, [userId]);

  useEffect(() => {
    let active = true;
    queueMicrotask(() => {
      if (!active) return;
      clear();
      if (ready) {
        identity.current = userId;
        setVisibleUserId(userId);
        void load({ force: true });
      }
    });
    return () => { active = false; generation.current += 1; inFlight.current = null; };
  }, [clear, load, ready, userId]);

  useEffect(() => {
    mounted.current = true;
    return () => { mounted.current = false; generation.current += 1; };
  }, []);

  useEffect(() => {
    if (!ready) return undefined;
    const onFocus = () => { void load(); };
    window.addEventListener('focus', onFocus);
    return () => window.removeEventListener('focus', onFocus);
  }, [load, ready]);

  const markAsRead = useCallback(async (id) => {
    const previous = notifications.find((item) => String(item.id) === String(id));
    if (!previous || !isUnreadNotification(previous) || identity.current !== userId) return true;
    generation.current += 1; inFlight.current = null; setLoading(false); setRefreshing(false);
    setNotifications((items) => markReadOptimistically(items, id).next);
    setUnreadCount((count) => Math.max(0, count - 1));
    try {
      await notificationsService.markMyNotificationRead(id);
      if (identity.current !== userId) return false;
      setError(''); lastLoadedAt.current = 0; void load({ force: true }); return true;
    } catch (updateError) {
      if (identity.current === userId) {
        setNotifications((items) => rollbackNotificationRead(items, previous));
        setUnreadCount((count) => count + 1);
        setError(updateError.message || 'Notification could not be updated.');
      }
      return false;
    }
  }, [load, notifications, userId]);

  const markAllAsRead = useCallback(async () => {
    if (!userId || unreadCount === 0) return true;
    const previousRows = notifications;
    const previousCount = unreadCount;
    generation.current += 1; inFlight.current = null; setLoading(false); setRefreshing(false);
    setNotifications(markAllReadOptimistically(previousRows)); setUnreadCount(0);
    try {
      await notificationsService.markAllMyNotificationsRead();
      if (identity.current !== userId) return false;
      setError(''); lastLoadedAt.current = 0; void load({ force: true }); return true;
    } catch (updateError) {
      if (identity.current === userId) {
        setNotifications(previousRows); setUnreadCount(previousCount);
        setError(updateError.message || 'Notifications could not be updated.');
      }
      return false;
    }
  }, [load, notifications, unreadCount, userId]);

  const ownsVisibleState = Boolean(userId) && visibleUserId === userId;
  return { notifications: ownsVisibleState ? notifications : [], unreadCount: ownsVisibleState ? unreadCount : 0,
    loading: ownsVisibleState && loading, refreshing: ownsVisibleState && refreshing,
    error: ownsVisibleState ? error : '', markAsRead, markAllAsRead,
    refresh: () => load({ force: true }), refreshIfStale: load };
}
