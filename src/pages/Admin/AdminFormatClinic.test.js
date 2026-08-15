import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const [page,service,app,sidebar,labMigration,formatMigration]=await Promise.all([
  readFile(new URL('../Settings.jsx',import.meta.url),'utf8'),
  readFile(new URL('../../services/adminClinicApi.js',import.meta.url),'utf8'),
  readFile(new URL('../../App.jsx',import.meta.url),'utf8'),
  readFile(new URL('../../components/Sidebar.jsx',import.meta.url),'utf8'),
  readFile(new URL('../../../backend/migrations/026_admin_user_management_and_doctor_only_labs.sql',import.meta.url),'utf8'),
  readFile(new URL('../../../backend/migrations/032_format_clinic_include_lab_catalog.sql',import.meta.url),'utf8'),
]);

test('Format card is inside Clinic Settings and is Admin-only',()=>{
  assert.match(page,/activeTab === 'clinic' && canManageClinic/);
  assert.match(page,/<FormatClinicDangerZone userRole=\{user\?\.role\}/);
  assert.match(page,/if\(userRole!=='admin'\)return null/);
  assert.doesNotMatch(page,/user\?\.role === 'doctor' && <section[\s\S]*Format Clinic Data/);
});

test('warning names all deleted data and preserved identity/system categories',()=>{
  for(const value of ['Patients','Dental state','Appointments','Consultations','Medical reports / clinical history','Patient financial history','Consultation Lab history','Lab payments','Labs','Lab Product List','Notifications','Operational logs']) assert.match(page,new RegExp(value));
  for(const value of ['Admin accounts','Doctor accounts','Receptionist accounts','Login emails','Passwords / Supabase Auth identities','Roles / approvals','Clinic Settings','Procedure catalog','Symptoms catalog','Appointment-condition catalog','Database/system functionality']) assert.match(page,new RegExp(value));
});

test('exact confirmation gates one parameterless RPC and duplicate submit',()=>{
  assert.match(page,/formatConfirmation!=='FORMAT CLINIC'/);
  assert.match(page,/if\(formatInFlight\.current\|\|formatting\|\|formatConfirmation!=='FORMAT CLINIC'\)return/);
  assert.match(service,/\.rpc\('format_clinic_data'\)/);
  assert.doesNotMatch(service,/\.rpc\('format_clinic_data',/);
  assert.doesNotMatch(service,/from\(|delete\(|httpClient|apiRequest|FastAPI|userId|adminId|role:/i);
});

test('success reloads authoritative state without clearing session or mutating users',()=>{
  assert.match(page,/reload=\(\)=>window\.location\.reload\(\),schedule=\(callback\)=>window\.setTimeout\(callback,700\)/);
  assert.doesNotMatch(page+service,/logout\(|signOut\(|clearSession|localStorage|sessionStorage|admin-delete-user|resetAdminUserPassword|updateAdminUser/);
  assert.doesNotMatch(service,/auth\.admin|prepare_admin_account_deletion|finalize_admin_account_deletion/);
  assert.doesNotMatch(formatMigration,/public\.users|auth\.users|clinic_settings/);
});

test('Lab system stays Doctor-only while Format clears only its data',()=>{
  assert.match(labMigration,/app_user\.role::text='doctor'/);
  assert.match(formatMigration,/public\.lab_products[\s\S]*public\.labs/);
  assert.doesNotMatch(app,/path="\/admin\/lab-(products|transactions)"/);
  assert.doesNotMatch(sidebar.split('admin:')[1].split('receptionist:')[0],/Lab Product|Lab Transactions/);
});
