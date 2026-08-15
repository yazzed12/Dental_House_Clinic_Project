-- Migration 031 verifier. Read-only catalog and definition checks.
DO $verify$
DECLARE v_format text; v_prepare text; v_finalize text; v_actor text;
BEGIN
  IF to_regprocedure('public.format_clinic_data()') IS NULL
     OR to_regprocedure('public.prepare_admin_account_deletion(uuid,uuid)') IS NULL
     OR to_regprocedure('public.finalize_admin_account_deletion(uuid)') IS NULL THEN
    RAISE EXCEPTION 'destructive operation function missing';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users'
    AND column_name='deletion_status' AND is_nullable='NO')
     OR NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users'
    AND column_name='deleted_at' AND udt_name='timestamptz') THEN RAISE EXCEPTION 'tombstone columns missing'; END IF;

  SELECT lower(pg_get_functiondef('public.format_clinic_data()'::regprocedure)) INTO v_format;
  SELECT lower(pg_get_functiondef('public.prepare_admin_account_deletion(uuid,uuid)'::regprocedure)) INTO v_prepare;
  SELECT lower(pg_get_functiondef('public.finalize_admin_account_deletion(uuid)'::regprocedure)) INTO v_finalize;
  SELECT lower(pg_get_functiondef('security.admin_user_actor()'::regprocedure)) INTO v_actor;

  IF v_format NOT LIKE '%security.admin_user_actor()%' OR v_actor NOT LIKE '%role::text = ''admin''%'
     OR v_actor NOT LIKE '%is_active = true%' OR v_actor NOT LIKE '%approved_at is not null%' THEN
    RAISE EXCEPTION 'format Admin authorization is not fail closed';
  END IF;
  IF v_format NOT LIKE '%truncate table%' OR v_format LIKE '%cascade%'
     OR v_format LIKE '%public.users%' OR v_format LIKE '%auth.users%'
     OR v_format LIKE '%public.clinic_settings%' OR v_format LIKE '%public.labs,%'
     OR v_format LIKE '%public.lab_products%' OR v_format LIKE '%public.clinic_procedures%'
     OR v_format LIKE '%public.symptoms%' OR v_format LIKE '%public.appointment_conditions%' THEN
    RAISE EXCEPTION 'format scope is unsafe';
  END IF;
  IF v_format NOT LIKE ALL(ARRAY['%public.notifications%','%public.financial_payment_allocations%',
    '%public.financial_charge_adjustments%','%public.financial_payment_records%',
    '%public.consultation_procedures%','%public.lab_payments%','%public.consultation_lab_items%',
    '%public.clinical_reports%','%public.patient_dental_state%','%public.records%',
    '%public.logs%','%public.consultations%','%public.appointments%','%public.patients%']) THEN
    RAISE EXCEPTION 'format approved table missing';
  END IF;
  IF v_format NOT LIKE '%pg_advisory_xact_lock%' OR v_prepare NOT LIKE '%pg_advisory_xact_lock%'
     OR v_finalize NOT LIKE '%pg_advisory_xact_lock%' THEN RAISE EXCEPTION 'destructive lock missing'; END IF;

  IF v_prepare NOT LIKE '%v_target.id=v_actor.id%' OR v_prepare NOT LIKE '%last_admin_denied%'
     OR v_prepare NOT LIKE '%for update%' OR v_prepare NOT LIKE '%deletion_status=''active''%'
     OR v_prepare NOT LIKE '%is_active=false%' OR v_prepare NOT LIKE '%approved_at=null%'
     OR v_prepare NOT LIKE '%pending_auth_delete%' THEN RAISE EXCEPTION 'prepare protections incomplete'; END IF;
  IF v_finalize LIKE '%delete from public.consultations%' OR v_finalize LIKE '%delete from public.clinical_reports%'
     OR v_finalize LIKE '%delete from public.lab_payments%' OR v_finalize LIKE '%delete from public.financial_%'
     OR v_finalize LIKE '%delete from public.users%' THEN RAISE EXCEPTION 'finalize destroys history/account row'; END IF;
  IF v_finalize NOT LIKE '%delete from public.notifications%'
     OR v_finalize NOT LIKE '%recipient_user_id=v_target.id%'
     OR v_finalize NOT LIKE '%supabase_user_id=null%' OR v_finalize NOT LIKE '%personal_email=null%'
     OR v_finalize NOT LIKE '%deleted.invalid%' OR v_finalize NOT LIKE '%deletion_status=''deleted''%'
     OR v_finalize NOT LIKE '%if v_target.deletion_status=''deleted''%' THEN RAISE EXCEPTION 'final tombstone incomplete'; END IF;

  IF has_function_privilege('anon','public.format_clinic_data()','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.format_clinic_data()','EXECUTE')
     OR has_function_privilege('authenticated','public.prepare_admin_account_deletion(uuid,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.finalize_admin_account_deletion(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.prepare_admin_account_deletion(uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.prepare_admin_account_deletion(uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.finalize_admin_account_deletion(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'destructive operation ACL mismatch';
  END IF;
END
$verify$;

SELECT 'VERIFICATION SUCCESSFUL: Admin destructive operations are safely contained' AS result;
