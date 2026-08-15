from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
MIG=ROOT/'backend'/'migrations'
MAIN=(MIG/'031_admin_destructive_operations.sql').read_text().lower()
PRE=(MIG/'031_admin_destructive_operations_preflight.sql').read_text().lower()
VERIFY=(MIG/'031_admin_destructive_operations_verify.sql').read_text().lower()

FORMAT_TABLES={
 'notifications','financial_payment_allocations','financial_charge_adjustments','financial_payment_records',
 'consultation_procedures','lab_payments','consultation_lab_items','clinical_reports','patient_dental_state',
 'records','logs','consultations','appointments','patients'
}
PRESERVED={'users','clinic_settings','labs','lab_products','clinic_procedures','symptoms','appointment_conditions'}

def section(start,end): return MAIN.split(start,1)[1].split(end,1)[0]

def test_preflight_is_read_only_and_has_exact_clean_result():
 for mutation in ('alter table','create function','truncate table','delete from','update public','insert into'):
  assert mutation not in PRE
 assert 'clean: migration 031 admin destructive-operation assumptions match current schema' in PRE
 assert 'additional_fk_children' in PRE

def test_format_is_one_explicit_non_cascading_operation():
 body=section('create function public.format_clinic_data()','create function public.prepare_admin_account_deletion')
 assert body.count('truncate table')==1
 assert 'cascade' not in body
 for table in FORMAT_TABLES: assert f'public.{table}' in body
 for table in PRESERVED: assert f'public.{table}' not in body
 assert 'security.admin_user_actor()' in body
 assert 'pg_advisory_xact_lock' in body
 assert 'p_actor' not in body

def test_tombstone_state_is_minimal_and_fail_closed():
 assert "deletion_status text not null default 'active'" in MAIN
 for state in ('active','pending_auth_delete','deleted'): assert f"deletion_status='{state}'" in MAIN
 prepare=section('create function public.prepare_admin_account_deletion','create function public.finalize_admin_account_deletion')
 assert 'is_active=false' in prepare and 'approved_at=null' in prepare
 assert "deletion_status='pending_auth_delete'" in prepare
 assert 'v_target.id=v_actor.id' in prepare
 assert 'admin_account_delete_last_admin_denied' in prepare
 assert "u.deletion_status='active'" in prepare

def test_prepare_is_concurrency_safe_and_target_auth_is_server_resolved():
 prepare=section('create function public.prepare_admin_account_deletion','create function public.finalize_admin_account_deletion')
 assert 'pg_advisory_xact_lock' in prepare and prepare.count('for update')>=2
 assert "u.supabase_user_id=p_actor_supabase_user_id" in prepare
 assert "'authuserid',v_target.supabase_user_id" in prepare
 assert 'p_target_auth' not in prepare

def test_finalize_is_idempotent_private_and_preserves_history():
 finalize=section('create function public.finalize_admin_account_deletion','revoke all on function public.format_clinic_data')
 assert "if v_target.deletion_status='deleted'" in finalize
 for field in ('supabase_user_id=null','personal_email=null','approved_at=null','is_active=false','phone=null'):
  assert field in finalize
 assert '@deleted.invalid' in finalize and "username=('deleted:'" in finalize
 assert 'full_name=' not in finalize and 'role=' not in finalize and 'specialization=' not in finalize
 for table in ('consultations','clinical_reports','consultation_lab_items','lab_payments','financial_payment_records','financial_charge_adjustments'):
  assert f'delete from public.{table}' not in finalize

def test_notification_cleanup_is_target_only_and_never_reassigned():
 finalize=section('create function public.finalize_admin_account_deletion','revoke all on function public.format_clinic_data')
 assert 'delete from public.notifications' in finalize
 assert 'n.recipient_user_id=v_target.id' in finalize and 'n.user_id::text=v_target.id::text' in finalize
 assert 'update public.notifications' not in finalize and 'insert into public.notifications' not in finalize

def test_acl_is_admin_browser_format_and_service_only_delete():
 assert 'grant execute on function public.format_clinic_data() to authenticated' in MAIN
 assert 'revoke execute on function public.format_clinic_data() from anon' in MAIN
 assert 'revoke all on function public.prepare_admin_account_deletion(uuid,uuid) from public,anon,authenticated' in MAIN
 assert 'grant execute on function public.prepare_admin_account_deletion(uuid,uuid) to service_role' in MAIN
 assert 'grant execute on function public.finalize_admin_account_deletion(uuid) to service_role' in MAIN

def test_existing_add_user_role_contract_is_unchanged():
 migration_026=(MIG/'026_admin_user_management_and_doctor_only_labs.sql').read_text().lower()
 edge=(ROOT/'supabase'/'functions'/'admin-create-user'/'index.ts').read_text().lower()
 assert "not in('doctor','receptionist')" in migration_026
 assert "['doctor', 'receptionist'].includes(role)" in edge
 assert 'create_admin_managed_staff' not in MAIN

def test_verifier_has_exact_success_contract():
 assert 'verification successful: admin destructive operations are safely contained' in VERIFY
 assert 'has_function_privilege' in VERIFY
