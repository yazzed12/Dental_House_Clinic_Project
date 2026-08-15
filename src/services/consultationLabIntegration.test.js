import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const read = path => readFile(new URL(path, import.meta.url), 'utf8');

test('Consultation exposes Lab Product beside Procedures and flushes Lab changes before finish', async () => {
  const source = await read('../pages/Doctor/ConsultationFlow.jsx');
  assert.match(source, /Procedures \(/);
  assert.match(source, /Lab Product \(/);
  assert.match(source, /await consultationLabs\.flushBeforeFinish\(\)/);
});

test('Lab Product click path mounts and closes the real selector without waiting for a consultation id', async () => {
  const source = await read('../pages/Doctor/ConsultationFlow.jsx');
  const button = source.match(/<button\s+type="button"[\s\S]*?<FlaskConical[\s\S]*?<\/button>/)[0];
  assert.match(button, /onClick=\{\(\) => setShowLabProducts\(true\)\}/);
  assert.match(button, /disabled=\{!isConsultationActive\}/);
  assert.doesNotMatch(button, /consultationId/);
  assert.match(source, /\{showLabProducts && \(\s*<LabProductSelector/);
  assert.match(source, /onClose=\{\(\) => setShowLabProducts\(false\)\}/);
});

test('Lab selector is a visible dialog and catalog RPC failure remains rendered inside it', async () => {
  const source = await read('../components/LabProductSelector.jsx');
  assert.match(source, /role="dialog" aria-modal="true"/);
  assert.match(source, /<h2 id="lab-products-heading"[^>]*>Lab Products<\/h2>/);
  assert.match(source, /\(catalogError \|\| error\) && <div role="alert"/);
  assert.match(source, /type="button" aria-label="Close Lab Products"/);
});

test('Lab picker uses active RPC lists, local case-insensitive search, multi-lab parent state, quantity and one note', async () => {
  const source = await read('../components/LabProductSelector.jsx');
  assert.match(source, /listLabs\(false\)/);
  assert.match(source, /listLabProducts\(selectedLabId, false\)/);
  assert.match(source, /toLowerCase\(\)\.includes/);
  assert.match(source, /min="1" max="999"/);
  assert.match(source, /Lab Note/);
  assert.match(source, /No active labs available\./);
  assert.match(source, /No active products for this lab\./);
});

test('Lab persistence sends intent only and medical report construction has no Lab input', async () => {
  const api = await read('./labApi.js');
  const flow = await read('../pages/Doctor/ConsultationFlow.jsx');
  assert.match(api, /items\.map\(\(\{ labProductId, quantity \}\)/);
  assert.doesNotMatch(api, /p_(?:unit_price|total_amount|doctor_id|patient_id|lab_name|product_name)/);
  const reportCall = flow.match(/buildAIReportGenerationPayload\(\{[\s\S]*?\n\s*\}\);/)[0];
  assert.doesNotMatch(reportCall, /lab/i);
  assert.doesNotMatch(flow, /finalNarrative[\s\S]{0,100}consultationLabs|consultationLabs[\s\S]{0,100}finalNarrative/);
});

test('Consultation Lab state deduplicates by product, preserves edits on save failure, and uses saved snapshots', async () => {
  const hook = await read('../hooks/useConsultationLabs.js');
  assert.match(hook, /find\(item => item\.labProductId === product\.id\)/);
  assert.match(hook, /catch\(reason => \{ setError\(reason\.message\); throw reason; \}\)/);
  assert.match(hook, /isSavedSnapshot: true/);
  assert.match(hook, /Math\.max\(1, Math\.min\(999/);
});

test('Lab save ensures the shared consultation before calling the Lab RPC and preserves pre-init drafts', async () => {
  const hook = await read('../hooks/useConsultationLabs.js');
  const dental = await read('../hooks/useDentalSystem.js');
  const flow = await read('../pages/Doctor/ConsultationFlow.jsx');
  assert.match(hook, /saveLabDraft\(\{/);
  assert.match(hook, /ensureConsultationInitialized,/);
  assert.match(hook, /if \(previousConsultationId\) \{[\s\S]*commitState\(\[\], '', false\)/);
  assert.match(dental, /const ensureConsultationInitialized = useCallback/);
  assert.match(dental, /await fetchConsultation\(patientId, sessionScope\)/);
  assert.match(flow, /useConsultationLabs\(consultationId, ensureConsultationInitialized\)/);
});

test('existing consultation id bypasses initialization and Finish flush uses the same initializer', async () => {
  const hook = await read('../hooks/useConsultationLabs.js');
  const api = await read('./labApi.js');
  const flow = await read('../pages/Doctor/ConsultationFlow.jsx');
  assert.match(hook, /saveLabDraft\(\{/);
  assert.match(api, /consultationId\s*\? \{ consultationId \}\s*:\s*await ensureConsultationInitialized/);
  assert.match(flow, /await ensureConsultationInitialized\(\);[\s\S]*await flushBeforeFinish\(finalNote\);[\s\S]*await consultationLabs\.flushBeforeFinish\(\);/);
  assert.doesNotMatch(flow, /lab(?:Items|Note|Products)[\s\S]{0,120}buildAIReportGenerationPayload/i);
});

test('shared initializer handles the real null consultationId read shape through save_current_consultation', async () => {
  const dental = await read('../hooks/useDentalSystem.js');
  assert.match(dental, /const loaded = await fetchConsultation\(patientId, sessionScope\)/);
  assert.match(dental, /loaded\?\.consultationId\s*\? loaded\s*:\s*await persistConsultation/);
  assert.match(dental, /result\?\.consultationId/);
  assert.match(dental, /consultationInitializationRef\.current/);
});

test('Supabase clinic settings and legacy records remain isolated background consumers', async () => {
  const clinic = await read('../context/ClinicContext.jsx');
  const data = await read('../context/DataContext.jsx');
  const records = await read('./recordsApi.js');
  const settings = await read('./clinicSettingsApi.js');
  const dental = await read('../hooks/useDentalSystem.js');
  assert.match(settings, /rpc\('get_clinic_settings'\)/);
  assert.doesNotMatch(settings, /apiRequest|clinic_token|\/settings\/clinic/);
  assert.match(records, /apiRequest\('\/records'\)/);
  assert.match(clinic, /refreshClinicSettings/);
  assert.match(data, /Promise\.allSettled/);
  assert.match(data, /listRecords\(\)/);
  assert.doesNotMatch(dental, /settings\/clinic|listRecords|\/records/);
});
