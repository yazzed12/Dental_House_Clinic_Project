export function canFetchPatients({ authLoading, user, authProvider }) {
  return !authLoading && Boolean(user?.id) && authProvider === 'supabase';
}

export function canFetchDoctors({ authLoading, user, authProvider }) {
  return !authLoading
    && Boolean(user?.id)
    && (authProvider === 'supabase' || authProvider === 'legacy');
}

export function canFetchAppointments({ authLoading, user, authProvider }) {
  return !authLoading
    && Boolean(user?.id)
    && (authProvider === 'supabase' || authProvider === 'legacy');
}

export function isCurrentDataRequest({
  generation,
  currentGeneration,
  expectedUserId,
  currentUserId,
}) {
  return generation === currentGeneration && expectedUserId === currentUserId;
}
