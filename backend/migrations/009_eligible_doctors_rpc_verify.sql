-- Verification for Migration 009: browser-safe eligible Doctor selector RPC.

DO $$
DECLARE
    v_security_definer boolean;
    v_safe_search_path boolean;
    v_public_execute integer;
    v_anon_execute integer;
    v_authenticated_execute integer;
    v_definition text;
    v_result_type text;
BEGIN
    SELECT
        p.prosecdef,
        array_to_string(p.proconfig, ',') LIKE '%search_path=pg_catalog, pg_temp%',
        p.prosrc,
        pg_get_function_result(p.oid)
      INTO v_security_definer, v_safe_search_path, v_definition, v_result_type
      FROM pg_proc AS p
      JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'get_eligible_doctors'
       AND p.pronargs = 0;

    IF v_definition IS NULL THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: public.get_eligible_doctors() is missing';
    END IF;

    IF NOT v_security_definer OR NOT v_safe_search_path THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Doctor selector RPC is not securely hardened';
    END IF;

    IF v_result_type <> 'TABLE(id uuid, full_name text, specialization text)' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Doctor selector return contract is invalid';
    END IF;

    IF v_definition NOT LIKE '%caller.supabase_user_id = auth.uid()%'
       OR v_definition NOT LIKE '%caller.is_active = true%'
       OR v_definition NOT LIKE '%caller.approved_at IS NOT NULL%'
       OR v_definition NOT LIKE '%ERRCODE = ''42501''%'
       OR v_definition NOT LIKE '%doctor.role = ''doctor''%'
       OR v_definition NOT LIKE '%doctor.is_active = true%'
       OR v_definition NOT LIKE '%doctor.approved_at IS NOT NULL%'
       OR v_definition NOT LIKE '%doctor.supabase_user_id IS NOT NULL%'
       OR v_definition LIKE '%personal_email%'
       OR v_definition LIKE '%hashed_password%'
       OR v_definition LIKE '%password%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Doctor selector authorization or safe-field contract is invalid';
    END IF;

    SELECT count(*) INTO v_public_execute
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'public'
       AND routine_name = 'get_eligible_doctors'
       AND grantee = 'PUBLIC';

    SELECT count(*) INTO v_anon_execute
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'public'
       AND routine_name = 'get_eligible_doctors'
       AND grantee = 'anon';

    SELECT count(*) INTO v_authenticated_execute
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'public'
       AND routine_name = 'get_eligible_doctors'
       AND grantee = 'authenticated'
       AND privilege_type = 'EXECUTE';

    IF v_public_execute <> 0 OR v_anon_execute <> 0 OR v_authenticated_execute <> 1 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Doctor selector RPC execute privileges are invalid';
    END IF;

    RAISE NOTICE 'VERIFICATION SUCCESSFUL: eligible Doctor selector RPC is safe.';
END $$;
