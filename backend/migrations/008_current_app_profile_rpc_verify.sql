-- Verification for Migration 008: browser-safe current application profile RPC.

DO $$
DECLARE
    v_exists boolean;
    v_security_definer boolean;
    v_safe_search_path boolean;
    v_public_execute integer;
    v_anon_execute integer;
    v_authenticated_execute integer;
    v_definition text;
BEGIN
    SELECT EXISTS (
        SELECT 1
          FROM information_schema.routines
         WHERE routine_schema = 'public'
           AND routine_name = 'get_current_app_profile'
    ) INTO v_exists;

    IF NOT v_exists THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: public.get_current_app_profile() is missing';
    END IF;

    SELECT
        p.prosecdef,
        array_to_string(p.proconfig, ',') LIKE '%search_path=pg_catalog, pg_temp%',
        p.prosrc
      INTO v_security_definer, v_safe_search_path, v_definition
      FROM pg_proc AS p
      JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'get_current_app_profile'
       AND p.pronargs = 0;

    IF NOT v_security_definer OR NOT v_safe_search_path THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: profile RPC is not securely hardened';
    END IF;

    IF v_definition NOT LIKE '%u.supabase_user_id = auth.uid()%'
       OR v_definition NOT LIKE '%u.is_active = true%'
       OR v_definition NOT LIKE '%u.approved_at IS NOT NULL%'
       OR v_definition LIKE '%personal_email%'
       OR v_definition LIKE '%hashed_password%'
       OR v_definition LIKE '%password%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: profile RPC identity, approval, or safe-field contract is invalid';
    END IF;

    SELECT count(*) INTO v_public_execute
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'public'
       AND routine_name = 'get_current_app_profile'
       AND grantee = 'PUBLIC';

    SELECT count(*) INTO v_anon_execute
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'public'
       AND routine_name = 'get_current_app_profile'
       AND grantee = 'anon';

    SELECT count(*) INTO v_authenticated_execute
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'public'
       AND routine_name = 'get_current_app_profile'
       AND grantee = 'authenticated'
       AND privilege_type = 'EXECUTE';

    IF v_public_execute <> 0 OR v_anon_execute <> 0 OR v_authenticated_execute <> 1 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: profile RPC execute privileges are invalid';
    END IF;

    RAISE NOTICE 'VERIFICATION SUCCESSFUL: current application profile RPC is safe.';
END $$;
