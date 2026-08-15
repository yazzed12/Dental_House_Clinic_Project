import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { apiRequest, HttpError, legacyAuthHeaders } from './httpClient.js';

globalThis.localStorage = { getItem: () => 'legacy-token' };

function jsonResponse(status, data) {
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: { get: () => 'application/json' },
    json: async () => data,
  };
}

test('shared transport preserves the legacy bearer token', () => {
  assert.deepEqual(legacyAuthHeaders(), { Authorization: 'Bearer legacy-token' });
});

for (const status of [401, 403, 409, 422, 500]) {
  test(`shared transport keeps ${status} visible`, async () => {
    await assert.rejects(
      apiRequest('/contract-check', {
        fetchImpl: async (_url, options) => {
          assert.equal(options.headers.Authorization, 'Bearer legacy-token');
          return jsonResponse(status, { detail: `visible-${status}` });
        },
      }),
      (error) => error instanceof HttpError
        && error.status === status
        && error.message === `visible-${status}`,
    );
  });
}

test('shared transport supports JSON and no-content responses', async () => {
  const json = await apiRequest('/json', {
    fetchImpl: async () => jsonResponse(200, { ok: true }),
  });
  assert.deepEqual(json, { ok: true });

  const empty = await apiRequest('/empty', {
    fetchImpl: async () => ({ ok: true, status: 204, headers: { get: () => '' } }),
  });
  assert.equal(empty, null);
});

test('contexts orchestrate domain services without direct fetch or endpoint URLs', async () => {
  for (const relative of ['../context/DataContext.jsx', '../context/ClinicContext.jsx']) {
    const source = await readFile(new URL(relative, import.meta.url), 'utf8');
    assert.doesNotMatch(source, /\bfetch\s*\(|API_URL|\/api\//);
  }
});

test('application layouts do not render the removed floating AI assistant', async () => {
  for (const relative of ['../components/Layout.jsx', '../layouts/MainLayout.jsx']) {
    const source = await readFile(new URL(relative, import.meta.url), 'utf8');
    assert.doesNotMatch(source, /AIAssistantChat|AI Assistant|animate-float/);
  }
});

test('active React callers do not construct migrated endpoint requests', async () => {
  const relativeFiles = [
    '../context/AuthContext.jsx',
    '../pages/Settings.jsx',
    '../pages/Auth/ForgotPassword.jsx',
    '../components/AppointmentModals.jsx',
    '../components/PatientModals.jsx',
    '../components/AIChatPanel.jsx',
    '../pages/Doctor/DoctorDashboard.jsx',
    '../pages/Doctor/ConsultationFlow.jsx',
    '../pages/Doctor/ConsultationsHistory.jsx',
  ];
  for (const relative of relativeFiles) {
    const source = await readFile(new URL(relative, import.meta.url), 'utf8');
    assert.doesNotMatch(source, /\bfetch\s*\(|API_URL|API_BASE_URL/);
  }
});

test('patient report failures remain distinct from an empty report list', async () => {
  const service = await readFile(new URL('./reportApi.js', import.meta.url), 'utf8');
  const modal = await readFile(new URL('../components/PatientModals.jsx', import.meta.url), 'utf8');
  assert.match(service, /if \(error\) throw reportRpcError\(error\)/);
  assert.match(modal, /reportsError[\s\S]*Retry[\s\S]*reportsList\.length === 0/);
});

test('domain services preserve required endpoint and table contracts', async () => {
  const contracts = {
    './patientApi.js': ['patients'],
    './appointmentApi.js': ['/appointments', '/status', '/finish-by-patient/'],
    './staffApi.js': ['/doctors', '/receptionists', '/staff'],
    './clinicSettingsApi.js': ['get_clinic_settings', 'update_clinic_settings'],
    './profileApi.js': ['get_current_app_profile', 'update_current_app_profile'],
    './clinicalReferenceApi.js': ['/appointment-conditions'],
  };
  for (const [relative, paths] of Object.entries(contracts)) {
    const source = await readFile(new URL(relative, import.meta.url), 'utf8');
    for (const path of paths) assert.match(source, new RegExp(path.replaceAll('/', '\\/')));
  }

  const clinicalReference = await readFile(
    new URL('./clinicalReferenceApi.js', import.meta.url),
    'utf8',
  );
  assert.match(clinicalReference, /list_active_symptoms/);
  assert.match(clinicalReference, /create_or_reactivate_symptom/);
  assert.doesNotMatch(clinicalReference, /\/clinical\/symptoms|clinic_token/);
});
