import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const [page,service,edge,app,sidebar,login,css]=await Promise.all([
  readFile(new URL('./UserManagement.jsx',import.meta.url),'utf8'),readFile(new URL('../../services/adminUsersApi.js',import.meta.url),'utf8'),
  readFile(new URL('../../../supabase/functions/admin-create-user/index.ts',import.meta.url),'utf8'),readFile(new URL('../../App.jsx',import.meta.url),'utf8'),
  readFile(new URL('../../components/Sidebar.jsx',import.meta.url),'utf8'),readFile(new URL('../Auth/Login.jsx',import.meta.url),'utf8'),readFile(new URL('../../index.css',import.meta.url),'utf8'),
]);

test('Admin has one Supabase User Management page and no Admin Lab access',()=>{
  assert.match(app,/path="\/admin\/users"[\s\S]*allowedRoles=\{\['admin'\]\}/);assert.match(sidebar,/path: '\/admin\/users'[\s\S]*User Management/);
  assert.doesNotMatch(app,/path="\/admin\/lab-(products|transactions)"/);assert.doesNotMatch(sidebar.split('admin:')[1].split('receptionist:')[0],/Lab Product|Lab Transactions/);
  assert.match(app,/path="\/doctor\/lab-products"[\s\S]*allowedRoles=\{\['doctor'\]\}/);assert.match(app,/path="\/doctor\/lab-transactions"[\s\S]*allowedRoles=\{\['doctor'\]\}/);
});
test('user list, local filters, detail and controlled editing use hardened RPCs',()=>{
  for(const label of ['User Management','Add User','Search by name or clinic email','All roles','All statuses','Account Information'])assert.match(page,new RegExp(label));
  for(const rpc of ['list_admin_users','get_admin_user','update_admin_user'])assert.match(service,new RegExp(rpc));
  assert.doesNotMatch(service+page,/httpClient|apiRequest|clinic_token|\/api\/staff|actorId|adminId/);
  assert.match(page,/form\.role==='admin'/);const updateCall=service.split("rpc('update_admin_user'")[1].split('});')[0];assert.doesNotMatch(updateCall,/p_role/);
});
test('Add User offers Doctor and Receptionist only with password confirmation',()=>{
  const createRoleSelect=page.split('creating?<label className="form-label">Role')[1].split('</select>')[0];assert.match(createRoleSelect,/<option value="doctor">Doctor<\/option><option value="receptionist">Receptionist<\/option>/);assert.doesNotMatch(createRoleSelect,/<option value="admin">/);
  assert.match(page,/form\.password\.length<8/);assert.match(page,/form\.password!==form\.confirmPassword/);assert.match(page,/Specialization is required for Doctors/);
  assert.match(service,/functions\.invoke\('admin-create-user'/);assert.doesNotMatch(service,/auth\.admin|service_role|SUPABASE_SERVICE_ROLE_KEY/);
});
test('Edge Function verifies Admin and compensates an application insert failure',()=>{
  assert.match(edge,/auth\.getUser\(token\)/);assert.match(edge,/supabase_user_id[\s\S]*role[\s\S]*is_active[\s\S]*approved_at/);
  assert.match(edge,/auth\.admin\.createUser/);assert.match(edge,/rpc\('create_admin_managed_staff'/);assert.match(edge,/auth\.admin\.deleteUser/);assert.match(edge,/ACCOUNT_CREATION_COMPENSATION_FAILED/);
  assert.match(edge,/\['doctor', 'receptionist'\]/);assert.doesNotMatch(edge,/role.*\['admin'/);
});
test('Add User performs normalized application and Auth conflicts before creation',()=>{
  const beforeCreate=edge.split('auth.admin.createUser')[0];
  assert.match(beforeCreate,/normalizedEmail/);assert.match(beforeCreate,/ilike\('email', clinicEmail\)/);assert.match(beforeCreate,/ilike\('personal_email', personalEmail\)/);
  assert.match(beforeCreate,/auth\.admin\.listUsers/);assert.match(beforeCreate,/CLINIC_EMAIL_ALREADY_EXISTS/);assert.match(beforeCreate,/PERSONAL_EMAIL_ALREADY_EXISTS/);assert.match(beforeCreate,/AUTH_EMAIL_ALREADY_EXISTS/);
  assert.match(edge,/PASSWORD_POLICY_INVALID/);assert.doesNotMatch(edge,/hashed_password|compare.*password|password.*another user/i);
  assert.match(edge,/INVALID_ROLE/);assert.match(edge,/DOCTOR_SPECIALIZATION_REQUIRED/);
});
test('Add User maps field-specific conflicts and retains the entered form',()=>{
  assert.match(service,/CLINIC_EMAIL_ALREADY_EXISTS[\s\S]*Clinic Login Email is already used/);
  assert.match(service,/PERSONAL_EMAIL_ALREADY_EXISTS\|AUTH_EMAIL_ALREADY_EXISTS[\s\S]*Personal\/Auth Email is already linked/);
  assert.match(page,/setErrorField\(e\.code==='CLINIC_EMAIL_ALREADY_EXISTS'/);assert.match(page,/aria-invalid=\{errorField==='clinicEmail'\}/);assert.match(page,/aria-invalid=\{errorField==='personalEmail'\}/);
  assert.match(page,/validEmail\(form\.clinicEmail\)/);assert.match(page,/validEmail\(form\.personalEmail\)/);
  assert.doesNotMatch(page,/catch\(e\).*setForm\(blank\)/s);
});
test('race conflicts compensate the new Auth identity before returning a safe conflict',()=>{
  const failure=edge.split('if (applicationError || !createdUser)')[1];
  assert.match(failure,/clinicRace/);assert.match(failure,/personalRace/);assert.match(failure,/auth\.admin\.deleteUser/);
  assert.ok(failure.indexOf('auth.admin.deleteUser')<failure.lastIndexOf("fail('CLINIC_EMAIL_ALREADY_EXISTS'"));
  assert.match(failure,/ACCOUNT_CREATION_COMPENSATION_FAILED/);assert.match(failure,/ACCOUNT_CREATION_STATE_UNKNOWN/);
});
test('Login password toggle is interactive, accessible and avoids leading-icon CSS collision',()=>{
  assert.match(login,/useState\(false\)/);assert.match(login,/type=\{showPassword \? "text" : "password"\}/);assert.match(login,/type="button"/);
  assert.match(login,/aria-pressed=\{showPassword\}/);assert.match(login,/setShowPassword\(!showPassword\)/);assert.match(login,/showPassword \? 'Hide password' : 'Show password'/);
  assert.match(css,/\.input-with-icon \.password-visibility-button svg/);assert.match(css,/inset-inline-end/);
});
test('Patients and medical reports are outside Admin account management',()=>{
  assert.doesNotMatch(page+service+edge,/patientApi|patients|clinical_reports|report_snapshot|MedicalReport|Ollama|Humanize/);
});
