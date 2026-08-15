import { getSupabaseClient } from '../lib/supabaseClient.js';

export class AdminUsersError extends Error {
  constructor(message, code = 'ADMIN_USERS_FAILED') { super(message); this.name = 'AdminUsersError'; this.code = code; }
}
const messageFor = error => {
  const raw = error?.message || error?.context?.body?.error || '';
  if (/AUTHORIZATION|403/i.test(raw)) return new AdminUsersError('Admin authorization is required.', 'ADMIN_AUTHORIZATION_DENIED');
  if (/CLINIC_EMAIL_ALREADY_EXISTS|ADMIN_USER_CLINIC_EMAIL_DUPLICATE/i.test(raw)) return new AdminUsersError('This Clinic Login Email is already used by another account.', 'CLINIC_EMAIL_ALREADY_EXISTS');
  if (/PERSONAL_EMAIL_ALREADY_EXISTS|AUTH_EMAIL_ALREADY_EXISTS/i.test(raw)) return new AdminUsersError('This Personal/Auth Email is already linked to another account.', 'PERSONAL_EMAIL_ALREADY_EXISTS');
  if (/PASSWORD_POLICY_INVALID/i.test(raw)) return new AdminUsersError('The initial password does not meet the password policy.', 'PASSWORD_POLICY_INVALID');
  if (/TARGET_ACCOUNT_NOT_FOUND/i.test(raw)) return new AdminUsersError('The account could not be found.', 'TARGET_ACCOUNT_NOT_FOUND');
  if (/ACCOUNT_NOT_LINKED_TO_AUTH/i.test(raw)) return new AdminUsersError('This account is not linked to Supabase Auth yet.', 'ACCOUNT_NOT_LINKED_TO_AUTH');
  if (/ACCOUNT_DELETION_PENDING|ADMIN_USER_DELETION_STATE_LOCKED/i.test(raw)) return new AdminUsersError('Deletion is pending. Normal account changes are disabled.', 'ACCOUNT_DELETION_PENDING');
  if (/PASSWORD_RESET_FAILED/i.test(raw)) return new AdminUsersError('The password could not be reset. Please try again.', 'PASSWORD_RESET_FAILED');
  if (/SELF_DELETE_DENIED/i.test(raw)) return new AdminUsersError('You cannot delete your own account.', 'SELF_DELETE_DENIED');
  if (/LAST_ADMIN_DENIED/i.test(raw)) return new AdminUsersError('The last active Admin account cannot be deleted.', 'LAST_ADMIN_DENIED');
  if (/AUTH_DELETE_FAILED/i.test(raw)) return new AdminUsersError('Login deletion is pending. Please retry.', 'AUTH_DELETE_FAILED');
  if (/ACCOUNT_FINALIZE_FAILED/i.test(raw)) return new AdminUsersError('Account deletion is pending. Please retry.', 'ACCOUNT_FINALIZE_FAILED');
  if (/ACCOUNT_DELETE_FAILED|DELETE_INPUT_INVALID/i.test(raw)) return new AdminUsersError('The account could not be deleted safely. Please try again.', 'ACCOUNT_DELETE_FAILED');
  if (/INVALID_ROLE/i.test(raw)) return new AdminUsersError('Only Doctor or Receptionist accounts can be created.', 'INVALID_ROLE');
  if (/DOCTOR_SPECIALIZATION_REQUIRED/i.test(raw)) return new AdminUsersError('Specialization is required for Doctors.', 'DOCTOR_SPECIALIZATION_REQUIRED');
  if (/DUPLICATE|ALREADY_EXISTS|409/i.test(raw)) return new AdminUsersError('That clinic or personal email is already in use.', 'STAFF_IDENTITY_ALREADY_EXISTS');
  if (/INPUT_INVALID|SPECIALIZATION/i.test(raw)) return new AdminUsersError('Please review the account information.', 'STAFF_INPUT_INVALID');
  if (/AUTH_ACCOUNT_CREATION_FAILED/i.test(raw)) return new AdminUsersError('The Personal/Auth Email could not be created or is already registered.', 'AUTH_ACCOUNT_CREATION_FAILED');
  if (/APPLICATION_ACCOUNT_CREATION_FAILED/i.test(raw)) return new AdminUsersError('The application account could not be created. The Auth identity was rolled back.', 'APPLICATION_ACCOUNT_CREATION_FAILED');
  if (/STATE_UNKNOWN/i.test(raw)) return new AdminUsersError('Account creation status could not be confirmed. Refresh the user list before retrying.', 'ACCOUNT_CREATION_STATE_UNKNOWN');
  if (/COMPENSATION_FAILED/i.test(raw)) return new AdminUsersError('Account creation could not be completed safely. Contact an administrator before retrying.', 'ACCOUNT_CREATION_COMPENSATION_FAILED');
  return new AdminUsersError(raw || 'User management request failed.');
};
const unwrap = data => Array.isArray(data) ? data[0] : data;

export async function listAdminUsers() {
  const { data,error }=await getSupabaseClient().rpc('list_admin_users',{ p_search:null,p_role:null,p_is_active:null });
  if(error) throw messageFor(error); return data || [];
}
export async function getAdminUser(userId) {
  const { data,error }=await getSupabaseClient().rpc('get_admin_user',{ p_user_id:userId });
  if(error) throw messageFor(error); return unwrap(data);
}
export async function updateAdminUser(userId,input) {
  const { data,error }=await getSupabaseClient().rpc('update_admin_user',{
    p_user_id:userId,p_full_name:input.fullName,p_clinic_email:input.clinicEmail,p_phone:input.phone||null,
    p_specialization:input.role==='doctor'?(input.specialization||null):null,p_is_active:Boolean(input.isActive),
  });
  if(error) throw messageFor(error); return unwrap(data);
}
export async function createAdminStaff(input) {
  const { data,error }=await getSupabaseClient().functions.invoke('admin-create-user',{ body:{
    fullName:input.fullName,clinicEmail:input.clinicEmail,personalEmail:input.personalEmail,phone:input.phone,
    role:input.role,specialization:input.role==='doctor'?input.specialization:null,password:input.password,
  }});
  if(error||data?.error||!data?.user) {
    let detail=data?.error;
    if(!detail&&error?.context?.json) { try { detail=(await error.context.json())?.error; } catch { /* safe generic fallback */ } }
    throw messageFor({message:detail||error?.message});
  }
  return data.user;
}
export async function resetAdminUserPassword(userId,newPassword) {
  const { data,error }=await getSupabaseClient().functions.invoke('admin-reset-user-password',{ body:{ userId,newPassword } });
  if(error||data?.error||data?.success!==true) {
    let detail=data?.error;
    if(!detail&&error?.context?.json) { try { detail=(await error.context.json())?.error; } catch { /* safe generic fallback */ } }
    throw messageFor({message:detail||error?.message});
  }
  return data;
}
export async function deleteAdminManagedUser(userId) {
  const { data,error }=await getSupabaseClient().functions.invoke('admin-delete-user',{ body:{ userId } });
  if(error||data?.error||data?.success!==true) {
    let detail=data?.error;
    if(!detail&&error?.context?.json) { try { detail=(await error.context.json())?.error; } catch { /* safe generic fallback */ } }
    throw messageFor({message:detail||error?.message});
  }
  return data;
}
