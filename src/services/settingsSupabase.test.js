import assert from 'node:assert/strict';
import test from 'node:test';
import { createProfileService } from './profileApi.js';
import { createClinicSettingsService } from './clinicSettingsApi.js';

test('profile hydration/update use Supabase RPC without browser identity or role', async () => {
  const calls=[]; const client={ rpc:async(name,args)=>{calls.push([name,args]);return {data:name==='get_current_app_profile'?[{full_name:'Dr. Yehia',email:'doctor@clinic.test',phone:'010',specialization:'Endodontics'}]:{full_name:'Dr. Yehia'},error:null};},auth:{updateUser:async()=>({data:{user:{}},error:null})} };
  const service=createProfileService({supabaseClient:client}); const profile=await service.getCurrentProfile();
  assert.equal(profile.full_name,'Dr. Yehia');
  await service.updateCurrentProfile({fullName:'Dr. Yehia',phone:'010',specialization:'Endodontics'});
  assert.deepEqual(calls[1],['update_current_app_profile',{p_full_name:'Dr. Yehia',p_phone:'010',p_specialization:'Endodontics'}]);
  assert.equal('p_user_id' in calls[1][1],false); assert.equal('p_role' in calls[1][1],false);
});

test('password uses Supabase Auth updateUser only', async () => {
  const values=[]; const service=createProfileService({supabaseClient:{rpc:async()=>({data:null,error:null}),auth:{updateUser:async value=>{values.push(value);return {data:{},error:null};}}}});
  await service.updatePassword('SecurePass123'); assert.deepEqual(values,[{password:'SecurePass123'}]);
});

test('Clinic Information RPC submits only four visible fields', async () => {
  const calls=[]; const service=createClinicSettingsService({supabaseClient:{rpc:async(name,args)=>{calls.push([name,args]);return {data:{name:'Smart Dental Clinic'},error:null};}}});
  await service.getClinicSettings(); await service.updateClinicSettings({name:'Smart Dental Clinic',email:'clinic@test',phone:'010',address:'Cairo',services:'must-not-send',notification_settings:'must-not-send'});
  assert.deepEqual(calls[0],['get_clinic_settings',undefined]);
  assert.deepEqual(calls[1],['update_clinic_settings',{p_name:'Smart Dental Clinic',p_email:'clinic@test',p_phone:'010',p_address:'Cairo'}]);
});
