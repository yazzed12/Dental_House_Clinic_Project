import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const [page,service,edge]=await Promise.all([
  readFile(new URL('./UserManagement.jsx',import.meta.url),'utf8'),
  readFile(new URL('../../services/adminUsersApi.js',import.meta.url),'utf8'),
  readFile(new URL('../../../supabase/functions/admin-reset-user-password/index.ts',import.meta.url),'utf8'),
]);

test('browser submits only the application user id and new password',()=>{
  assert.match(service,/functions\.invoke\('admin-reset-user-password',[\s\S]*body:\{ userId,newPassword \}/);
  const request=service.split("functions.invoke('admin-reset-user-password'")[1].split('});')[0];
  assert.doesNotMatch(request,/supabase_user_id|authUserId|actorId|service_role/i);
  assert.doesNotMatch(page+service,/SUPABASE_SERVICE_ROLE_KEY|auth\.admin\.updateUserById/);
});

test('server derives and validates the Admin actor from the caller JWT',()=>{
  assert.match(edge,/auth\.getUser\(token\)/);
  assert.match(edge,/\.eq\('supabase_user_id', authResult\.user\.id\)/);
  assert.match(edge,/role\)\.toLowerCase\(\) !== 'admin'/);
  assert.match(edge,/!actor\.is_active/);
  assert.match(edge,/!actor\.approved_at/);
  assert.match(edge,/String\(actor\.role\)\.toLowerCase\(\) !== 'admin'/);
  assert.match(edge,/actor\.deletion_status !== 'active'/);
});

test('server resolves the protected Auth UUID from public users before resetting',()=>{
  assert.match(edge,/\.select\('id, supabase_user_id, deletion_status'\)\.eq\('id', userId\)\.maybeSingle\(\)/);
  assert.match(edge,/auth\.admin\.updateUserById\(target\.supabase_user_id, \{ password: newPassword \}\)/);
  assert.match(edge,/if \(!target\) return fail\('TARGET_ACCOUNT_NOT_FOUND'/);
  assert.match(edge,/if \(!target\.supabase_user_id\) return fail\('ACCOUNT_NOT_LINKED_TO_AUTH'/);
  assert.doesNotMatch(edge,/hashed_password|select\([^)]*password|body\.(supabase_user_id|authUserId|actorId)/i);
  assert.doesNotMatch(edge,/\.from\('users'\)[\s\S]*\.(update|upsert|insert|delete)\(/);
});

test('pending or deleted targets cannot reset passwords server-side',()=>{
  assert.match(edge,/target\.deletion_status !== 'active'/);
  assert.match(edge,/ACCOUNT_DELETION_PENDING/);
  assert.match(service,/ACCOUNT_DELETION_PENDING/);
});

test('server returns only the approved safe error contract',()=>{
  const returned=[...edge.matchAll(/fail\('([A-Z_]+)'/g)].map(match=>match[1]);
  const allowed=new Set(['ADMIN_AUTHORIZATION_DENIED','TARGET_ACCOUNT_NOT_FOUND','ACCOUNT_NOT_LINKED_TO_AUTH','ACCOUNT_DELETION_PENDING','PASSWORD_POLICY_INVALID','PASSWORD_RESET_FAILED']);
  assert.ok(returned.length>0);for(const code of returned)assert.ok(allowed.has(code),`unsafe error code: ${code}`);
  for(const code of allowed)assert.ok(returned.includes(code),`missing error code: ${code}`);
});

test('Admin modal gates reset by linkage, validates, prevents duplicates and clears only on success',()=>{
  assert.match(page,/!form\.isLinked/);
  assert.match(page,/This account is not linked to Supabase Auth yet\./);
  assert.match(page,/resetPassword\.length<8\|\|resetPassword\.length>256/);
  assert.match(page,/resetPassword!==resetConfirmation/);
  assert.match(page,/if\(resetting\|\|creating\|\|accountLocked\|\|!form\.isLinked\)return/);
  assert.match(page,/await resetAdminUserPassword\(user\.id,resetPassword\);setResetPassword\(''\);setResetConfirmation\(''\)/);
  const failure=page.split('catch(e){setResetError(e.message);')[1].split('}finally{setResetting(false);')[0];
  assert.doesNotMatch(failure,/setResetPassword\(''\)|setResetConfirmation\(''\)/);
  assert.match(page,/value="••••••••"[\s\S]*readOnly/);
});
