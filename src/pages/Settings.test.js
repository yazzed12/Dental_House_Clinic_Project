import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const [page,clinic,profile,clinicApi,sidebar,translations] = await Promise.all([
  readFile(new URL('./Settings.jsx',import.meta.url),'utf8'),
  readFile(new URL('../context/ClinicContext.jsx',import.meta.url),'utf8'),
  readFile(new URL('../services/profileApi.js',import.meta.url),'utf8'),
  readFile(new URL('../services/clinicSettingsApi.js',import.meta.url),'utf8'),
  readFile(new URL('../components/Sidebar.jsx',import.meta.url),'utf8'),
  readFile(new URL('../data/translations.js',import.meta.url),'utf8'),
]);

test('simplified Settings has exactly the requested cards and tabs',()=>{
  for(const expected of ['Profile Settings','Clinic Settings','Personal Information','Security','Clinic Information']) assert.match(page,new RegExp(expected));
  for(const removed of ['Appearance','Workflow & Services','Clinic Notifications','accentColor','notification_settings','appointment_duration','working_hours']) assert.doesNotMatch(page,new RegExp(removed));
  assert.doesNotMatch(page,/>Services</);
});
test('authoritative profile values control inputs and login email is read-only',()=>{
  assert.match(page,/value=\{profile\.fullName\}/); assert.match(page,/value=\{profile\.phone\}/); assert.match(page,/value=\{profile\.specialization\}/); assert.match(page,/value=\{profile\.email\} readOnly/);
  assert.match(page,/updateCurrentProfile/); assert.match(page,/await refreshProfile\(\)/); assert.doesNotMatch(page,/userId|role:/);
});
test('password validation and Supabase Auth workflow are present',()=>{
  assert.match(page,/password\.next\.length < 8/); assert.match(page,/password\.next !== password\.confirm/); assert.match(page,/await updatePassword\(password\.next\)/);
  assert.match(profile,/auth\.updateUser\(\{ password \}\)/); assert.doesNotMatch(profile,/httpClient|apiRequest|hashed_password|clinic_token/);
});
test('clinic hydration cannot expose a blank save and only visible fields are submitted',()=>{
  assert.match(page,/clinicLoading \? <LoadingCard/); assert.match(page,/clinicLoadError \|\| !clinic \? <LoadError/);
  assert.match(page,/if \(clinicSaving \|\| !clinic \|\| clinicLoading \|\| clinicLoadError\) return/);
  assert.match(page,/updateClinicSettings\(\{ name: clinic\.name\.trim\(\), email: clinic\.email\.trim\(\), phone: clinic\.phone\.trim\(\), address: clinic\.address\.trim\(\) \}\)/);
  assert.doesNotMatch(clinicApi,/httpClient|apiRequest|clinic_token|\/settings\/clinic/);
});
test('ClinicContext hydrates Doctor Admin and Receptionist and handles stale requests',()=>{
  assert.match(clinic,/new Set\(\['doctor', 'admin', 'receptionist'\]\)/); assert.match(clinic,/generation\.current/); assert.match(clinic,/refreshClinicSettings/); assert.doesNotMatch(clinic,/clinic_token|localStorage|\/api\//);
});
test('Patient Records label is corrected without adding Patient Settings',()=>{
  assert.match(sidebar,/path: '\/patient\/records', icon: UserCog, labelKey: 'records'/); assert.match(translations,/records: 'Records'/);
});
test('frontend Settings contains no legacy Settings endpoints or Medical Report coupling',()=>{
  const combined=page+clinic+profile+clinicApi;
  assert.doesNotMatch(combined,/\/api\/settings|\/settings\/profile|\/settings\/clinic|clinic_token/);
  assert.doesNotMatch(combined,/clinical_reports|report_snapshot|finalNarrative|finalize_clinical_report|MedicalReportMarkdown|Humanize|Ollama/);
});
