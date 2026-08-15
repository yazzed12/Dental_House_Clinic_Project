-- Verification script for Migration 006: Minimal Auth & RLS Identity Helper Foundation (Trusted Schema)

DO $$
DECLARE
    v_public_func_count integer;
    v_security_func_count integer;
    v_sec_def_count integer;
    v_search_path_count integer;
    v_public_grant_count integer;
    v_internal_auth_grant_count integer;
    v_entrypoint_auth_grant_count integer;
    v_create_privilege_count integer;
BEGIN
    -- 1. Verify 0 helper functions exist in public schema
    SELECT count(*)
      INTO v_public_func_count
      FROM information_schema.routines
     WHERE routine_schema = 'public'
       AND routine_name IN (
           'current_app_user_id',
           'current_app_role',
           'is_active_approved_user',
           'is_doctor',
           'is_admin'
       );

    IF v_public_func_count > 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Helper functions must NOT exist in public schema';
    END IF;

    -- 2. Verify all 5 minimal helper functions exist in 'security' schema
    SELECT count(*)
      INTO v_security_func_count
      FROM information_schema.routines
     WHERE routine_schema = 'security'
       AND routine_name IN (
           'current_app_user_id',
           'current_app_role',
           'is_active_approved_user',
           'is_doctor',
           'is_admin'
       );

    IF v_security_func_count <> 5 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Expected 5 helper functions in security schema, found %', v_security_func_count;
    END IF;

    -- 3. Verify all 5 functions are configured as SECURITY DEFINER
    SELECT count(*)
      INTO v_sec_def_count
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
     WHERE n.nspname = 'security'
       AND p.proname IN ('current_app_user_id', 'current_app_role', 'is_active_approved_user', 'is_doctor', 'is_admin')
       AND p.prosecdef = true;

    IF v_sec_def_count <> 5 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Expected all 5 security functions to be SECURITY DEFINER, found %', v_sec_def_count;
    END IF;

    -- 4. Verify all 5 functions have pinned search_path = pg_catalog, pg_temp
    SELECT count(*)
      INTO v_search_path_count
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
     WHERE n.nspname = 'security'
       AND p.proname IN ('current_app_user_id', 'current_app_role', 'is_active_approved_user', 'is_doctor', 'is_admin')
       AND array_to_string(p.proconfig, ',') LIKE '%search_path=pg_catalog, pg_temp%';

    IF v_search_path_count <> 5 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Expected all 5 functions to have pinned search_path = pg_catalog, pg_temp, found %', v_search_path_count;
    END IF;

    -- 5. Verify PUBLIC has 0 EXECUTE privileges on the security functions
    SELECT count(*)
      INTO v_public_grant_count
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'security'
       AND routine_name IN ('current_app_user_id', 'current_app_role', 'is_active_approved_user', 'is_doctor', 'is_admin')
       AND grantee = 'PUBLIC';

    IF v_public_grant_count > 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: PUBLIC still holds privileges on security helper functions';
    END IF;

    -- 6. Verify internal helpers have NO direct authenticated EXECUTE grants
    SELECT count(*)
      INTO v_internal_auth_grant_count
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'security'
       AND routine_name IN ('current_app_user_id', 'current_app_role', 'is_doctor', 'is_admin')
       AND grantee = 'authenticated';

    IF v_internal_auth_grant_count > 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Internal helpers should not be directly granted to authenticated';
    END IF;

    -- 7. Verify ONLY security.is_active_approved_user has EXECUTE granted to authenticated
    SELECT count(*)
      INTO v_entrypoint_auth_grant_count
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'security'
       AND routine_name = 'is_active_approved_user'
       AND grantee = 'authenticated'
       AND privilege_type = 'EXECUTE';

    IF v_entrypoint_auth_grant_count <> 1 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: security.is_active_approved_user must be granted EXECUTE to authenticated';
    END IF;

    -- 8. Verify authenticated role cannot CREATE objects in security schema
    SELECT count(*)
      INTO v_create_privilege_count
      FROM information_schema.schema_privileges
     WHERE schema_name = 'security'
       AND grantee IN ('PUBLIC', 'anon', 'authenticated')
       AND privilege_type = 'CREATE';

    IF v_create_privilege_count > 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Untrusted roles must not have CREATE privileges on security schema';
    END IF;

    RAISE NOTICE 'VERIFICATION SUCCESSFUL: 006 Auth RLS helpers trusted schema model verified cleanly.';
END $$;
