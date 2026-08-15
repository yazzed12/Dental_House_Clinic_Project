import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { canFetchAppointments, canFetchDoctors, canFetchPatients, isCurrentDataRequest } from './sessionLifecycle.js';

test('patients remain gated during auth hydration and while unauthenticated', () => {
  assert.equal(canFetchPatients({
    authLoading: true,
    user: { id: 'doctor-1' },
    authProvider: 'supabase',
  }), false);
  assert.equal(canFetchPatients({
    authLoading: false,
    user: null,
    authProvider: 'supabase',
  }), false);
  assert.equal(canFetchPatients({
    authLoading: false,
    user: { id: 'doctor-1' },
    authProvider: 'legacy',
  }), false);
});

test('approved application user establishment enables Supabase patient fetching', () => {
  assert.equal(canFetchPatients({
    authLoading: false,
    user: { id: 'doctor-1', role: 'doctor' },
    authProvider: 'supabase',
  }), true);
});

test('Doctor hydration waits for auth and requires an authenticated user', () => {
  assert.equal(canFetchDoctors({
    authLoading: true,
    user: { id: 'receptionist-1' },
    authProvider: 'supabase',
  }), false);
  assert.equal(canFetchDoctors({
    authLoading: false,
    user: null,
    authProvider: 'supabase',
  }), false);
  assert.equal(canFetchDoctors({
    authLoading: false,
    user: { id: 'receptionist-1' },
    authProvider: 'supabase',
  }), true);
  assert.equal(canFetchDoctors({
    authLoading: false,
    user: { id: 'legacy-user' },
    authProvider: 'legacy',
  }), true);
});

test('Appointment hydration waits for auth and requires an authenticated user', () => {
  assert.equal(canFetchAppointments({
    authLoading: true,
    user: { id: 'receptionist-1' },
    authProvider: 'supabase',
  }), false);
  assert.equal(canFetchAppointments({
    authLoading: false,
    user: null,
    authProvider: 'supabase',
  }), false);
  assert.equal(canFetchAppointments({
    authLoading: false,
    user: { id: 'receptionist-1' },
    authProvider: 'supabase',
  }), true);
  assert.equal(canFetchAppointments({
    authLoading: false,
    user: { id: 'legacy-user' },
    authProvider: 'legacy',
  }), true);
});

test('stale data requests are rejected after generation or user changes', () => {
  assert.equal(isCurrentDataRequest({
    generation: 1,
    currentGeneration: 2,
    expectedUserId: 'doctor-1',
    currentUserId: 'doctor-1',
  }), false);
  assert.equal(isCurrentDataRequest({
    generation: 2,
    currentGeneration: 2,
    expectedUserId: 'doctor-1',
    currentUserId: 'doctor-2',
  }), false);
  assert.equal(isCurrentDataRequest({
    generation: 2,
    currentGeneration: 2,
    expectedUserId: 'doctor-2',
    currentUserId: 'doctor-2',
  }), true);
});

test('DataContext clears scoped state and distinguishes patient loading, error, and empty states', async () => {
  const source = await readFile(new URL('./DataContext.jsx', import.meta.url), 'utf8');
  assert.match(source, /clearUserScopedData\(\)/);
  assert.match(source, /setPatients\(\[\]\)/);
  assert.match(source, /setPatientsLoading\(true\)/);
  assert.match(source, /setPatientsError\(patientsResult\.reason/);
  assert.match(source, /patientsResult\.status === 'fulfilled'/);
  assert.match(source, /user\?\.id/);
});

test('DataContext hydrates Doctors on login and keeps empty, error, logout, and stale states distinct', async () => {
  const source = await readFile(new URL('./DataContext.jsx', import.meta.url), 'utf8');
  assert.match(source, /const doctorsReady = canFetchDoctors/);
  assert.match(source, /fetchBackendData\(generation, user\.id, patientsReady, doctorsReady, appointmentsReady\)/);
  assert.match(source, /setDoctors\(\[\]\)/);
  assert.match(source, /setDoctorsLoading\(true\)/);
  assert.match(source, /setDoctorsError\(doctorsResult\.reason/);
  assert.match(source, /doctorsResult\.status === 'fulfilled'/);
  assert.match(source, /isCurrentDataRequest/);
  assert.match(source, /setDoctorsOwnerId\(null\)/);
});

test('DataContext hydrates appointments on login and keeps empty, error, logout, and stale states distinct', async () => {
  const source = await readFile(new URL('./DataContext.jsx', import.meta.url), 'utf8');
  assert.match(source, /const appointmentsReady = canFetchAppointments/);
  assert.match(source, /fetchBackendData\(generation, user\.id, patientsReady, doctorsReady, appointmentsReady\)/);
  assert.match(source, /setAppointments\(\[\]\)/);
  assert.match(source, /setAppointmentsLoading\(true\)/);
  assert.match(source, /setAppointmentsError\(appointmentsResult\.reason/);
  assert.match(source, /appointmentsResult\.status === 'fulfilled'/);
  assert.match(source, /setAppointmentsOwnerId\(null\)/);
  assert.match(source, /isCurrentDataRequest/);
});

test('protected routes hold navigation while auth restoration is pending', async () => {
  const source = await readFile(new URL('../App.jsx', import.meta.url), 'utf8');
  const protectedRoute = source.split('const ProtectedRoute', 2)[1].split('const RootRedirect', 1)[0];
  assert.ok(protectedRoute.indexOf('if (loading)') < protectedRoute.indexOf('if (!user)'));
  assert.match(protectedRoute, /Checking session/);
});

test('AuthContext invalidates restoration, login, and logout operations by generation', async () => {
  const source = await readFile(new URL('./AuthContext.jsx', import.meta.url), 'utf8');
  assert.match(source, /operationGeneration/);
  assert.match(source, /restoreGeneration === operationGeneration\.current/);
  assert.match(source, /loginGeneration === operationGeneration\.current/);
  assert.match(source, /logoutGeneration === operationGeneration\.current/);
});
