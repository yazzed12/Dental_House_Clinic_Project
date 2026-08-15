-- Migration 032 verifier. Read-only catalog and normalized function-definition checks.
DO $verify$
DECLARE
  v_format text;
  v_actor text;
  v_normalized text;
  v_truncate text;
  v_search_path text;
  v_table text;
BEGIN
  IF to_regprocedure('public.format_clinic_data()') IS NULL THEN
    RAISE EXCEPTION 'format_clinic_data() is missing';
  END IF;
  IF to_regprocedure('security.admin_user_actor()') IS NULL THEN
    RAISE EXCEPTION 'security.admin_user_actor() is missing';
  END IF;

  SELECT lower(pg_get_functiondef('public.format_clinic_data()'::regprocedure)) INTO v_format;
  SELECT lower(pg_get_functiondef('security.admin_user_actor()'::regprocedure)) INTO v_actor;
  SELECT regexp_replace(array_to_string(proconfig, ','), '[[:space:]]+', '', 'g')
    INTO v_search_path
    FROM pg_proc
   WHERE oid = 'public.format_clinic_data()'::regprocedure;
  v_normalized := regexp_replace(v_format, '[[:space:]]+', '', 'g');
  v_truncate := coalesce((regexp_match(v_normalized, 'truncatetable([^;]+);'))[1], '');

  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.format_clinic_data()'::regprocedure)
     OR v_search_path <> 'search_path=pg_catalog,pg_temp'
     OR v_normalized NOT LIKE '%security.admin_user_actor()%' THEN
    RAISE EXCEPTION 'Format security definition changed';
  END IF;
  IF regexp_replace(v_actor, '[[:space:]]+', '', 'g') NOT LIKE '%role::text=''admin''%'
     OR regexp_replace(v_actor, '[[:space:]]+', '', 'g') NOT LIKE '%is_active=true%'
     OR regexp_replace(v_actor, '[[:space:]]+', '', 'g') NOT LIKE '%approved_atisnotnull%' THEN
    RAISE EXCEPTION 'Admin authorization is not active/approved/fail-closed';
  END IF;
  IF v_normalized NOT LIKE '%pg_advisory_xact_lock%smart-clinic:destructive-operations%'
     OR v_truncate = '' OR v_normalized LIKE '%truncate%cascade%' THEN
    RAISE EXCEPTION 'Format lock or explicit non-cascade TRUNCATE is missing';
  END IF;

  FOREACH v_table IN ARRAY ARRAY[
    'notifications','financial_payment_allocations','financial_charge_adjustments',
    'financial_payment_records','consultation_procedures','lab_payments',
    'consultation_lab_items','clinical_reports','patient_dental_state','records',
    'logs','consultations','appointments','patients','lab_products','labs'
  ] LOOP
    IF NOT (v_truncate LIKE '%public.' || v_table || '%') THEN
      RAISE EXCEPTION 'Format table is missing: public.%', v_table;
    END IF;
  END LOOP;

  FOREACH v_table IN ARRAY ARRAY[
    'users','clinic_settings','clinic_procedures','symptoms','appointment_conditions'
  ] LOOP
    IF v_truncate LIKE ('%public.' || v_table || '%') THEN
      RAISE EXCEPTION 'Preserved table entered Format scope: public.%', v_table;
    END IF;
  END LOOP;

  IF v_normalized LIKE '%auth.users%'
     OR v_normalized LIKE '%deletefrompublic.users%'
     OR v_normalized LIKE '%updatepublic.users%'
     OR v_normalized LIKE '%deletefromauth.%'
     OR v_normalized LIKE '%updateauth.%'
     OR v_normalized LIKE '%deletion_status%'
     OR v_normalized LIKE '%pending_auth_delete%'
     OR v_normalized LIKE '%drop%' THEN
    RAISE EXCEPTION 'Format mutates identity, tombstone state, or schema';
  END IF;

  IF to_regclass('public.labs') IS NULL
     OR to_regclass('public.lab_products') IS NULL
     OR to_regclass('public.lab_payments') IS NULL
     OR to_regclass('public.consultation_lab_items') IS NULL
     OR to_regprocedure('security.lab_actor()') IS NULL
     OR to_regprocedure('public.list_labs(boolean)') IS NULL
     OR to_regprocedure('public.create_lab(text)') IS NULL
     OR to_regprocedure('public.list_lab_transactions(uuid,timestamp with time zone,timestamp with time zone)') IS NULL THEN
    RAISE EXCEPTION 'Lab schema or RPC foundation is missing';
  END IF;

  IF to_regprocedure('public.prepare_admin_account_deletion(uuid,uuid)') IS NULL
     OR to_regprocedure('public.finalize_admin_account_deletion(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Account deletion functions are missing';
  END IF;

  IF EXISTS (
       SELECT 1
       FROM pg_proc AS procedure
       CROSS JOIN LATERAL aclexplode(coalesce(procedure.proacl, acldefault('f', procedure.proowner))) AS acl
       WHERE procedure.oid = 'public.format_clinic_data()'::regprocedure
         AND acl.grantee = 0
         AND acl.privilege_type = 'EXECUTE'
     )
     OR has_function_privilege('anon', 'public.format_clinic_data()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.format_clinic_data()', 'EXECUTE') THEN
    RAISE EXCEPTION 'Format RPC ACL mismatch';
  END IF;
END
$verify$;

SELECT 'VERIFICATION SUCCESSFUL: Clinic Format clears Lab data while preserving the system' AS result;
