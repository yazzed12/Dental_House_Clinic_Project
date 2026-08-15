import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const [page,service,edge,migration]=await Promise.all([
  readFile(new URL('./UserManagement.jsx',import.meta.url),'utf8'),
  readFile(new URL('../../services/adminUsersApi.js',import.meta.url),'utf8'),
  readFile(new URL('../../../supabase/functions/admin-delete-user/index.ts',import.meta.url),'utf8'),
  readFile(new URL('../../../backend/migrations/031_admin_destructive_operations.sql',import.meta.url),'utf8'),
]);

test('browser sends only the target application userId',()=>{
  assert.match(service,/functions\.invoke\('admin-delete-user',\{ body:\{ userId \} \}\)/);
  const request=service.split("functions.invoke('admin-delete-user'")[1].split('});')[0];
  assert.doesNotMatch(request,/actor|role|authuuid|supabase_user_id|service.role/i);
  assert.doesNotMatch(page+service,/auth\.admin\.deleteUser|SUPABASE_SERVICE_ROLE_KEY|\.from\('users'\)\.delete/);
});

test('Edge verifies the JWT and independently validates the active approved non-deleted Admin',()=>{
  assert.match(edge,/auth\.getUser\(token\)/);
  assert.match(edge,/const verifiedActorAuthUuid = authResult\.user\.id/);
  assert.match(edge,/\.eq\('supabase_user_id', verifiedActorAuthUuid\)/);
  assert.match(edge,/String\(actor\.role\)\.toLowerCase\(\) !== 'admin'/);
  assert.match(edge,/!actor\.is_active/);assert.match(edge,/!actor\.approved_at/);
  assert.match(edge,/actor\.deletion_status !== 'active'/);
  assert.doesNotMatch(edge,/body\.(actor|role|authUser|supabase)/i);
});

test('Edge uses the exact prepare-delete-finalize sequence and server-resolved Auth UUID',()=>{
  const prepare=edge.indexOf("rpc('prepare_admin_account_deletion'");
  const authDelete=edge.indexOf('auth.admin.deleteUser(targetAuthUuid)');
  const finalize=edge.indexOf("rpc('finalize_admin_account_deletion'");
  assert.ok(prepare>0&&authDelete>prepare&&finalize>authDelete);
  assert.match(edge,/p_target_user_id: targetUserId/);
  assert.match(edge,/p_actor_supabase_user_id: verifiedActorAuthUuid/);
  assert.match(edge,/const targetAuthUuid = prepared\.authUserId/);
  assert.doesNotMatch(edge,/\.select\([^)]*supabase_user_id[^)]*\).*targetUserId/s);
});

test('missing Auth converges while real Auth/finalize failures remain retryable and fail closed',()=>{
  assert.match(edge,/authUserMissing\(deleteError\)/);
  assert.match(edge,/error\.status === 404/);
  assert.match(edge,/AUTH_DELETE_FAILED/);assert.match(edge,/ACCOUNT_FINALIZE_FAILED/);
  assert.ok(edge.indexOf("rpc('prepare_admin_account_deletion'")<edge.indexOf('AUTH_DELETE_FAILED'));
  assert.doesNotMatch(edge,/reactivat|is_active.*true|approved_at.*now/i);
  assert.match(migration,/deletion_status='pending_auth_delete'/);
});

test('safe self last-Admin missing-target and authorization codes are mapped',()=>{
  for(const code of ['ADMIN_AUTHORIZATION_DENIED','TARGET_ACCOUNT_NOT_FOUND','SELF_DELETE_DENIED','LAST_ADMIN_DENIED','AUTH_DELETE_FAILED','ACCOUNT_FINALIZE_FAILED','ACCOUNT_DELETE_FAILED']) {
    assert.match(edge+service,new RegExp(code));
  }
  assert.match(service,/The last active Admin account cannot be deleted\./);
  assert.match(service,/You cannot delete your own account\./);
  assert.doesNotMatch(edge,/reply\([^)]*(targetAuthUuid|serviceKey)|console\.(log|error)\([^)]*(deleteError|finalizeError|serviceKey)/s);
});

test('Danger Zone requires exact typed confirmation and blocks self deletion',()=>{
  assert.match(page,/Danger Zone/);assert.match(page,/Delete Account/);
  assert.match(page,/Historical clinic records created by this account will remain preserved\./);
  assert.match(page,/const expectedConfirmation=`DELETE \$\{form\.clinicEmail\}`/);
  assert.match(page,/deleteConfirmation!==expectedConfirmation/);
  assert.match(page,/String\(user\.id\)===String\(currentUserId\)/);
  assert.match(page,/You cannot delete your own account\./);
  assert.match(page,/disabled=\{isSelf\|\|deleting\}/);
});

test('successful deletion closes stale UI, clears reset fields, refreshes and supports every listed role',()=>{
  assert.match(page,/setResetPassword\(''\);setResetConfirmation\(''\)/);
  assert.match(page,/setSelected\(undefined\)/);
  assert.match(page,/await listAdminUsers\(\)/);
  assert.match(page,/Account deleted\. Historical clinic records were preserved\./);
  const deleteHandler=page.split('const deleteAccount=')[1].split('return <div')[0];
  assert.doesNotMatch(deleteHandler,/form\.role|role==='doctor'|role==='receptionist'|role==='admin'/);
});

test('Add User remains Doctor and Receptionist only and account deletion stays separate from Format',()=>{
  const createRoles=page.split('creating?<label className="form-label">Role')[1].split('</select>')[0];
  assert.match(createRoles,/<option value="doctor">Doctor<\/option><option value="receptionist">Receptionist<\/option>/);
  assert.doesNotMatch(createRoles,/admin|patient/);
  assert.doesNotMatch(page+service+edge,/format_clinic_data|FORMAT CLINIC/);
});

test('pending deletion is visible, retryable, and cannot edit or reset password',()=>{
  assert.match(page,/form\.deletionStatus==='pending_auth_delete'/);
  assert.match(page,/Deletion pending/);
  assert.match(page,/Normal editing and password reset are disabled/);
  assert.match(page,/Retry Delete Account/);
  assert.match(page,/!creating&&!accountLocked/);
  assert.match(page,/if\(saving\|\|accountLocked\)return/);
  assert.match(page,/if\(resetting\|\|creating\|\|accountLocked/);
  assert.match(page,/e\.code==='AUTH_DELETE_FAILED'\|\|e\.code==='ACCOUNT_FINALIZE_FAILED'/);
  assert.match(page,/deletionStatus:'pending_auth_delete',isActive:false/);
});

test('no historical or notification cleanup is duplicated outside Migration 031',()=>{
  for(const forbidden of ['patients','appointments','consultations','clinical_reports','lab_payments','financial_payment_records','notifications']) {
    assert.doesNotMatch(edge+service,new RegExp(`from\\(['"]${forbidden}`));
  }
});
