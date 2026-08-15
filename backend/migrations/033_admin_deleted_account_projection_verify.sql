-- Migration 033 verifier. Read-only and whitespace-insensitive.
DO $verify$
DECLARE v_list text; v_detail text; v_update text; v_create text; v_format text; v_prepare text; v_finalize text;
BEGIN
  SELECT regexp_replace(lower(pg_get_functiondef('public.list_admin_users(text,text,boolean)'::regprocedure)),'[[:space:]]+','','g') INTO v_list;
  SELECT regexp_replace(lower(pg_get_functiondef('public.get_admin_user(uuid)'::regprocedure)),'[[:space:]]+','','g') INTO v_detail;
  SELECT regexp_replace(lower(pg_get_functiondef('public.update_admin_user(uuid,text,text,text,text,boolean)'::regprocedure)),'[[:space:]]+','','g') INTO v_update;
  SELECT regexp_replace(lower(pg_get_functiondef('public.create_admin_managed_staff(uuid,text,text,text,text,text,text)'::regprocedure)),'[[:space:]]+','','g') INTO v_create;
  SELECT regexp_replace(lower(pg_get_functiondef('public.format_clinic_data()'::regprocedure)),'[[:space:]]+','','g') INTO v_format;
  SELECT regexp_replace(lower(pg_get_functiondef('public.prepare_admin_account_deletion(uuid,uuid)'::regprocedure)),'[[:space:]]+','','g') INTO v_prepare;
  SELECT regexp_replace(lower(pg_get_functiondef('public.finalize_admin_account_deletion(uuid)'::regprocedure)),'[[:space:]]+','','g') INTO v_finalize;

  IF v_list NOT LIKE '%u.deletion_status<>''deleted''%' OR v_list NOT LIKE '%''deletionstatus'',u.deletion_status%'
     OR v_list NOT LIKE '%p_search%' OR v_list NOT LIKE '%p_role%' OR v_list NOT LIKE '%p_is_active%' THEN
    RAISE EXCEPTION 'Admin list deletion projection or existing filters are incomplete';
  END IF;
  IF v_detail NOT LIKE '%u.deletion_status<>''deleted''%' OR v_detail NOT LIKE '%''deletionstatus'',u.deletion_status%'
     OR v_list LIKE '%supabaseuserid%' OR v_detail LIKE '%supabaseuserid%' OR v_list LIKE '%personalemail%' OR v_detail LIKE '%personalemail%' THEN
    RAISE EXCEPTION 'Admin detail projection is unsafe';
  END IF;
  IF v_update NOT LIKE '%v_target.deletion_status<>''active''%' OR v_update NOT LIKE '%admin_user_deletion_state_locked%'
     OR v_update NOT LIKE '%forupdate%' THEN RAISE EXCEPTION 'Pending/deleted account editing is not fail closed'; END IF;
  IF v_list NOT LIKE '%security.admin_user_actor()%' OR v_detail NOT LIKE '%security.admin_user_actor()%' OR v_update NOT LIKE '%security.admin_user_actor()%' THEN
    RAISE EXCEPTION 'Admin authorization was not preserved';
  END IF;
  IF v_create NOT LIKE '%notin(''doctor'',''receptionist'')%' OR v_create LIKE '%notin(''admin''%' THEN
    RAISE EXCEPTION 'Add User role contract changed';
  END IF;
  IF v_prepare NOT LIKE '%pending_auth_delete%' OR v_finalize NOT LIKE '%deletion_status=''deleted''%'
     OR v_finalize LIKE '%deletefrompublic.users%' THEN RAISE EXCEPTION 'Account deletion semantics changed'; END IF;
  IF v_format NOT LIKE '%public.lab_products%' OR v_format NOT LIKE '%public.labs%'
     OR v_format LIKE '%public.users%' OR v_format LIKE '%auth.users%' THEN RAISE EXCEPTION 'Migration 032 Format contract changed'; END IF;
  IF to_regprocedure('security.lab_actor()') IS NULL
     OR to_regprocedure('public.list_my_notifications(integer,timestamp with time zone,uuid)') IS NULL
     OR to_regprocedure('public.list_doctor_consultation_history()') IS NULL
     OR to_regprocedure('public.get_appointments()') IS NULL THEN
    RAISE EXCEPTION 'Lab, notification, or Doctor-isolation foundation is missing';
  END IF;
  IF has_function_privilege('anon','public.list_admin_users(text,text,boolean)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.list_admin_users(text,text,boolean)','EXECUTE') THEN
    RAISE EXCEPTION 'Admin projection ACL mismatch';
  END IF;
END
$verify$;

SELECT 'VERIFICATION SUCCESSFUL: Admin deleted-account projection is safely contained' AS result;
