-- READ-ONLY verifier for Migration 027.
DO $verify$
DECLARE v_definition text; v_acl boolean;
BEGIN
  FOREACH v_definition IN ARRAY ARRAY[
    'public.list_admin_users(text,text,boolean)',
    'public.get_admin_user(uuid)',
    'public.update_admin_user(uuid,text,text,text,text,boolean)'
  ] LOOP
    IF to_regprocedure(v_definition) IS NULL THEN RAISE EXCEPTION 'VERIFICATION FAILED: % missing',v_definition; END IF;
    IF NOT has_function_privilege('authenticated',v_definition,'EXECUTE')
       OR has_function_privilege('anon',v_definition,'EXECUTE') THEN
      RAISE EXCEPTION 'VERIFICATION FAILED: Admin RPC role ACL incorrect for %',v_definition;
    END IF;
    SELECT EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
      WHERE p.oid=v_definition::regprocedure AND acl.grantee=0 AND acl.privilege_type='EXECUTE') INTO v_acl;
    IF v_acl THEN RAISE EXCEPTION 'VERIFICATION FAILED: PUBLIC can execute %',v_definition; END IF;
  END LOOP;

  v_definition:=regexp_replace(lower(pg_get_functiondef('public.list_admin_users(text,text,boolean)'::regprocedure)),'[[:space:]]+','','g');
  IF v_definition LIKE '%role::textin(''admin'',''doctor'',''receptionist'')%'
     OR v_definition NOT LIKE '%existing_user.role::text=lower(btrim(p_role))%' THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: list does not cover all existing application roles';
  END IF;
  v_definition:=regexp_replace(lower(pg_get_functiondef('public.get_admin_user(uuid)'::regprocedure)),'[[:space:]]+','','g');
  IF v_definition LIKE '%role::textin(''admin'',''doctor'',''receptionist'')%' THEN RAISE EXCEPTION 'VERIFICATION FAILED: detail role restriction remains'; END IF;
  v_definition:=regexp_replace(lower(pg_get_functiondef('public.update_admin_user(uuid,text,text,text,text,boolean)'::regprocedure)),'[[:space:]]+','','g');
  IF v_definition LIKE '%role::textin(''admin'',''doctor'',''receptionist'')%'
     OR v_definition LIKE '%personal_email=%' OR v_definition LIKE '%supabase_user_id=%' OR v_definition LIKE '%role=%'
     OR v_definition NOT LIKE '%admin_account_status_immutable%' THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: update coverage or protected fields unsafe';
  END IF;

  v_definition:=regexp_replace(lower(pg_get_functiondef('public.create_admin_managed_staff(uuid,text,text,text,text,text,text)'::regprocedure)),'[[:space:]]+','','g');
  IF v_definition NOT LIKE '%notin(''doctor'',''receptionist'')%' OR v_definition LIKE '%p_role=''admin''%' THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: staff creation role containment changed';
  END IF;
  IF has_function_privilege('authenticated','public.create_admin_managed_staff(uuid,text,text,text,text,text,text)','EXECUTE')
     OR has_function_privilege('anon','public.create_admin_managed_staff(uuid,text,text,text,text,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: browser can execute internal creation RPC';
  END IF;

  IF NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='users' AND indexname='uq_users_normalized_clinic_email' AND indexdef ILIKE 'CREATE UNIQUE INDEX%')
     OR NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='users' AND indexname='uq_users_normalized_personal_email' AND indexdef ILIKE 'CREATE UNIQUE INDEX%')
     OR NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='users' AND indexname='uq_users_supabase_user_id' AND indexdef ILIKE 'CREATE UNIQUE INDEX%') THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: identity uniqueness authority missing';
  END IF;
  v_definition:=regexp_replace(lower(pg_get_functiondef('security.admin_user_actor()'::regprocedure)),'[[:space:]]+','','g');
  IF v_definition NOT LIKE '%supabase_user_id=auth.uid()%role::text=''admin''%is_active=true%approved_atisnotnull%' THEN RAISE EXCEPTION 'VERIFICATION FAILED: Admin actor changed'; END IF;
  v_definition:=regexp_replace(lower(pg_get_functiondef('security.lab_actor()'::regprocedure)),'[[:space:]]+','','g');
  IF v_definition NOT LIKE '%role::text=''doctor''%' OR v_definition LIKE '%role::text=''admin''%' THEN RAISE EXCEPTION 'VERIFICATION FAILED: Lab is not Doctor-only'; END IF;
  IF EXISTS(SELECT 1 FROM public.users u LEFT JOIN auth.users a ON a.id=u.supabase_user_id WHERE u.supabase_user_id IS NOT NULL AND a.id IS NULL) THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: existing Auth linkage is broken';
  END IF;
  RAISE NOTICE 'VERIFICATION SUCCESSFUL: Migration 027 role coverage is contained';
END
$verify$;
