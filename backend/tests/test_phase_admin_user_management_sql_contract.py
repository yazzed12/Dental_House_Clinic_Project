import re
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
MIGRATION=(ROOT/'migrations/026_admin_user_management_and_doctor_only_labs.sql').read_text().lower()
PREFLIGHT=(ROOT/'migrations/026_admin_user_management_and_doctor_only_labs_preflight.sql').read_text().lower()
VERIFY=(ROOT/'migrations/026_admin_user_management_and_doctor_only_labs_verify.sql').read_text().lower()
MIGRATION_027=(ROOT/'migrations/027_admin_user_management_role_coverage.sql').read_text().lower()
PREFLIGHT_027=(ROOT/'migrations/027_admin_user_management_role_coverage_preflight.sql').read_text().lower()
VERIFY_027=(ROOT/'migrations/027_admin_user_management_role_coverage_verify.sql').read_text().lower()

class AdminUserManagementContractTests(unittest.TestCase):
  def test_preflight_is_read_only_and_consolidated(self):
    executable=re.sub(r'--[^\n]*','',PREFLIGHT)
    self.assertNotRegex(executable,r'(?m)^\s*(insert|update|delete|alter|drop|create|grant|revoke|truncate)\b')
    self.assertIn('select check_name,status,details',PREFLIGHT);self.assertIn('existing.admin_account',PREFLIGHT);self.assertIn('lab_actor.definition',PREFLIGHT)
  def test_admin_actor_is_server_derived_active_and_approved(self):
    compact=re.sub(r'\s+','',MIGRATION)
    for value in ('supabase_user_id=auth.uid()',"role::text='admin'",'is_active=true','approved_atisnotnull'):self.assertIn(value,compact)
  def test_browser_admin_rpcs_are_hardened(self):
    for signature in ('list_admin_users(text,text,boolean)','get_admin_user(uuid)','update_admin_user(uuid,text,text,text,text,boolean)'):
      self.assertIn(f'revoke all on function public.{signature} from public',MIGRATION);self.assertIn(f'public.{signature}',VERIFY)
    self.assertRegex(VERIFY,r'acl\.grantee\s*=\s*0');self.assertNotIn("has_function_privilege('public'",VERIFY)
  def test_creation_is_staff_only_linked_active_approved_and_internal(self):
    body=re.search(r'create function public\.create_admin_managed_staff[\s\S]*?\$function\$;',MIGRATION).group(0)
    self.assertIn("notin('doctor','receptionist')",re.sub(r'\s+','',body));self.assertNotIn("p_role='admin'",re.sub(r'\s+','',body))
    for marker in ('supabase_user_id','personal_email','is_active','approved_at','clock_timestamp()'):self.assertIn(marker,body)
    self.assertIn('to service_role',MIGRATION);self.assertIn('from public,anon,authenticated',MIGRATION)
  def test_update_cannot_change_role_auth_email_or_link(self):
    body=re.search(r'create function public\.update_admin_user[\s\S]*?\$function\$;',MIGRATION).group(0)
    set_clause=body.split('update public.users u set',1)[1].split('where u.id=',1)[0]
    for forbidden in ('personal_email=','supabase_user_id=','role=','approved_at=','hashed_password='):self.assertNotIn(forbidden,re.sub(r'\s+','',set_clause))
    self.assertIn('admin_account_status_immutable',body)
  def test_migration_026_remains_the_applied_staff_role_contract(self):
    for name in ('list_admin_users','get_admin_user','update_admin_user'):
      body=re.search(rf'create function public\.{name}[\s\S]*?\$function\$;',MIGRATION).group(0)
      self.assertIn("role::textin('admin','doctor','receptionist')",re.sub(r'\s+','',body))
  def test_migration_027_is_the_only_forward_role_coverage_delta(self):
    self.assertNotIn('create table',MIGRATION_027);self.assertNotIn('alter table',MIGRATION_027)
    for name in ('list_admin_users','get_admin_user','update_admin_user'):
      body=re.search(rf'create or replace function public\.{name}[\s\S]*?\$function\$;',MIGRATION_027).group(0)
      self.assertNotIn("role::textin('admin','doctor','receptionist')",re.sub(r'\s+','',body))
    self.assertIn('existing_user.role::text=lower(btrim(p_role))',re.sub(r'\s+','',MIGRATION_027))
    self.assertNotIn('create_admin_managed_staff(',MIGRATION_027.split('do $precondition$',1)[-1].split('$precondition$;',1)[-1])
  def test_migration_027_preflight_and_verifier_cover_identity_and_containment(self):
    executable=re.sub(r'--[^\n]*','',PREFLIGHT_027)
    self.assertNotRegex(executable,r'(?m)^\s*(insert|update|delete|alter|drop|create|grant|revoke|truncate)\b')
    for marker in ('normalized_clinic_email_unique','normalized_personal_email_unique','supabase_user_id_unique','auth.linkage_integrity','lab_actor.doctor_only','migration_027.readiness'):self.assertIn(marker,PREFLIGHT_027)
    for marker in ('list does not cover all existing application roles','staff creation role containment changed','identity uniqueness authority missing','lab is not doctor-only','public can execute'):self.assertIn(marker,VERIFY_027)
  def test_lab_actor_is_doctor_only(self):
    bodies=re.findall(r'create or replace function security\.lab_actor\(\)[\s\S]*?\$function\$;',MIGRATION)
    self.assertTrue(bodies);compact=re.sub(r'\s+','',bodies[-1]);self.assertIn("role::text='doctor'",compact);self.assertNotIn("'admin'",compact)
  def test_existing_admin_and_domain_data_are_not_recreated(self):
    self.assertNotIn('insert into public.users',MIGRATION.split('create function public.create_admin_managed_staff',1)[0]);self.assertNotIn('create table',MIGRATION)
    self.assertNotIn('delete from public.labs',MIGRATION);self.assertNotIn('delete from public.lab_',MIGRATION)

if __name__=='__main__':unittest.main()
