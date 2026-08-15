-- READ-ONLY verifier for Migration 026:
-- Admin User Management + Doctor-only Lab authorization.

DO $verify$
DECLARE
  v_definition text;
  v_acl boolean;
BEGIN
  IF to_regprocedure('public.list_admin_users(text,text,boolean)') IS NULL
     OR to_regprocedure('public.get_admin_user(uuid)') IS NULL
     OR to_regprocedure('public.update_admin_user(uuid,text,text,text,text,boolean)') IS NULL
     OR to_regprocedure('public.create_admin_managed_staff(uuid,text,text,text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: Admin user functions missing';
  END IF;


  v_definition := regexp_replace(
    lower(pg_get_functiondef('security.admin_user_actor()'::regprocedure)),
    '[[:space:]]+',
    '',
    'g'
  );

  IF v_definition NOT LIKE '%supabase_user_id=auth.uid()%'
     OR v_definition NOT LIKE '%role::text=''admin''%'
     OR v_definition NOT LIKE '%is_active=true%'
     OR v_definition NOT LIKE '%approved_atisnotnull%' THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: Admin actor is not contained';
  END IF;


  v_definition := regexp_replace(
    lower(
      pg_get_functiondef(
        'public.create_admin_managed_staff(uuid,text,text,text,text,text,text)'::regprocedure
      )
    ),
    '[[:space:]]+',
    '',
    'g'
  );

  IF v_definition NOT LIKE '%notin(''doctor'',''receptionist'')%'
     OR v_definition LIKE '%''admin''%'
     OR v_definition NOT LIKE '%approved_at%clock_timestamp()%'
     OR v_definition NOT LIKE '%supabase_user_id%' THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: Staff creation contract unsafe';
  END IF;


  v_definition := regexp_replace(
    lower(
      pg_get_functiondef(
        'public.update_admin_user(uuid,text,text,text,text,boolean)'::regprocedure
      )
    ),
    '[[:space:]]+',
    '',
    'g'
  );

  IF v_definition LIKE '%personal_email=%'
     OR v_definition LIKE '%supabase_user_id=%'
     OR v_definition LIKE '%role=%'
     OR v_definition NOT LIKE '%admin_account_status_immutable%' THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: Admin update scope unsafe';
  END IF;

  v_definition := regexp_replace(
    lower(pg_get_functiondef('security.lab_actor()'::regprocedure)),
    '[[:space:]]+',
    '',
    'g'
  );

  IF v_definition NOT LIKE '%role::text=''doctor''%'
     OR v_definition LIKE '%''admin''%' THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: Lab actor is not Doctor-only';
  END IF;


  FOREACH v_definition IN ARRAY ARRAY[
    'public.list_admin_users(text,text,boolean)',
    'public.get_admin_user(uuid)',
    'public.update_admin_user(uuid,text,text,text,text,boolean)'
  ]
  LOOP
    IF NOT has_function_privilege('authenticated', v_definition, 'EXECUTE')
       OR has_function_privilege('anon', v_definition, 'EXECUTE') THEN
      RAISE EXCEPTION 'VERIFICATION FAILED: Admin RPC role ACL incorrect';
    END IF;

    SELECT EXISTS(
      SELECT 1
      FROM pg_proc p
      CROSS JOIN LATERAL
        aclexplode(
          coalesce(
            p.proacl,
            acldefault('f', p.proowner)
          )
        ) acl
      WHERE p.oid = v_definition::regprocedure
        AND acl.grantee = 0
        AND acl.privilege_type = 'EXECUTE'
    )
    INTO v_acl;

    IF v_acl THEN
      RAISE EXCEPTION 'VERIFICATION FAILED: PUBLIC can execute Admin RPC';
    END IF;
  END LOOP;


  IF has_function_privilege(
       'authenticated',
       'public.create_admin_managed_staff(uuid,text,text,text,text,text,text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'anon',
       'public.create_admin_managed_staff(uuid,text,text,text,text,text,text)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'service_role',
       'public.create_admin_managed_staff(uuid,text,text,text,text,text,text)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: internal staff creation ACL incorrect';
  END IF;


  SELECT EXISTS(
    SELECT 1
    FROM pg_proc p
    CROSS JOIN LATERAL
      aclexplode(
        coalesce(
          p.proacl,
          acldefault('f', p.proowner)
        )
      ) acl
    WHERE p.oid =
      'public.create_admin_managed_staff(uuid,text,text,text,text,text,text)'::regprocedure
      AND acl.grantee = 0
      AND acl.privilege_type = 'EXECUTE'
  )
  INTO v_acl;

  IF v_acl THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: PUBLIC can execute internal staff creation';
  END IF;


  RAISE NOTICE
    'VERIFICATION SUCCESSFUL: Admin user management is contained and Lab authorization is Doctor-only';
END
$verify$;
