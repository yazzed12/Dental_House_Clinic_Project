import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const [dashboard,users,service,app,sidebar,dataContext,settings,reportService]=await Promise.all([
  readFile(new URL('./AdminDashboard.jsx',import.meta.url),'utf8'),readFile(new URL('./UserManagement.jsx',import.meta.url),'utf8'),
  readFile(new URL('../../services/adminUsersApi.js',import.meta.url),'utf8'),readFile(new URL('../../App.jsx',import.meta.url),'utf8'),
  readFile(new URL('../../components/Sidebar.jsx',import.meta.url),'utf8'),readFile(new URL('../../context/DataContext.jsx',import.meta.url),'utf8'),
  readFile(new URL('../Settings.jsx',import.meta.url),'utf8'),readFile(new URL('../../services/reportApi.js',import.meta.url),'utf8'),
]);

test('Admin Dashboard removed unsupported health compliance announcements and AI widgets',()=>{
  for(const removed of ['System Health Analysis','System Health','System Compliance','Announcements','AI Diagnostic Accuracy'])assert.doesNotMatch(dashboard,new RegExp(removed));
  assert.doesNotMatch(dashboard,/useData|staffApi|listRecords|getDashboard|httpClient|apiRequest|clinic_token|localStorage|\/api\//);
  assert.match(dashboard,/listAdminUsers\(\)/);assert.match(dashboard,/role="alert"/);assert.match(dashboard,/onClick=\{load\}/);
});
test('active Admin routes have one Supabase source map and no Lab or AI route',()=>{
  const adminBlock=sidebar.split('admin:')[1].split('receptionist:')[0];
  for(const path of ['/admin','/admin/users','/admin/settings'])assert.match(app,new RegExp(`path="${path.replaceAll('/','\\/')}"`));
  assert.doesNotMatch(adminBlock,/Lab Product|Lab Transactions|AI|Ollama|Humanize/);assert.doesNotMatch(app,/path="\/admin\/lab|path="\/admin\/ai/);
  assert.match(dataContext,/if \(user\.role === 'admin'\) return undefined/);
});
test('Admin Dashboard and User Management use only hardened Supabase account APIs',()=>{
  const active=dashboard+users+service;
  assert.match(service,/rpc\('list_admin_users'/);assert.match(service,/rpc\('get_admin_user'/);assert.match(service,/rpc\('update_admin_user'/);assert.match(service,/functions\.invoke\('admin-create-user'/);
  assert.doesNotMatch(active,/FastAPI|httpClient|apiRequest|clinic_token|\/api\/records|\/api\/staff|mockData|localStorage/);
});
test('all returned application roles are dynamically visible while creation remains staff-only',()=>{
  assert.match(users,/new Set\(users\.map\(user=>user\.role\)/);assert.match(users,/roles\.map\(value=>/);
  const createSelect=users.split('creating?<label className="form-label">Role')[1].split('</select>')[0];
  assert.match(createSelect,/value="doctor"/);assert.match(createSelect,/value="receptionist"/);assert.doesNotMatch(createSelect,/value="admin"|value="patient"/);
});
test('Admin Settings remains Supabase-only and Doctor report transport remains present but isolated',()=>{
  assert.match(settings,/getCurrentProfile|updateCurrentProfile|updatePassword|updateClinicSettings/);assert.doesNotMatch(settings,/httpClient|apiRequest|clinic_token|\/api\/settings/);
  assert.match(reportService,/generate-report|humanize-report/);assert.doesNotMatch(dashboard+users+service,/generate-report|humanize-report|Ollama|MedicalReportMarkdown/);
});
test('all Admin primary actions have handlers and failures stay visible',()=>{
  assert.match(dashboard,/onClick=\{\(\)=>navigate\('\/admin\/users'\)\}/);assert.match(dashboard,/onClick=\{\(\)=>navigate\('\/admin\/settings'\)\}/);
  assert.match(users,/onClick=\{\(\)=>setSelected\(null\)\}/);assert.match(users,/onClick=\{\(\)=>setSelected\(user\)\}/);assert.match(users,/role="alert"/);
});
