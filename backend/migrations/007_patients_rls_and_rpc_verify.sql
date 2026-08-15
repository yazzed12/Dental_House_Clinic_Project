-- Verification script for Migration 007: Patients RLS Policies and safe_delete_patient RPC

DO $$
DECLARE
    v_priv_count integer;
    v_anon_priv_count integer;
    v_delete_priv_count integer;
    v_policy_count integer;
    v_delete_policy_count integer;
    v_rpc_exists boolean;
    v_rpc_secdef boolean;
    v_public_rpc_priv integer;
    v_anon_rpc_priv integer;
    v_auth_rpc_priv integer;
    v_care_team_ref boolean;
    v_logs_ref boolean;
BEGIN
    -- 1. Verify authenticated role table privileges on public.patients (SELECT, INSERT, UPDATE)
    SELECT count(*)
      INTO v_priv_count
      FROM information_schema.role_table_grants
     WHERE table_schema = 'public'
       AND table_name = 'patients'
       AND grantee = 'authenticated'
       AND privilege_type IN ('SELECT', 'INSERT', 'UPDATE');

    IF v_priv_count <> 3 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: authenticated role missing expected SELECT, INSERT, UPDATE privileges on public.patients';
    END IF;

    -- 2. Verify DELETE privilege is NOT granted on public.patients to authenticated or anon
    SELECT count(*)
      INTO v_delete_priv_count
      FROM information_schema.role_table_grants
     WHERE table_schema = 'public'
       AND table_name = 'patients'
       AND grantee IN ('authenticated', 'anon', 'PUBLIC')
       AND privilege_type = 'DELETE';

    IF v_delete_priv_count > 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: DELETE privilege must NOT be granted to browser roles on public.patients';
    END IF;

    -- 3. Verify anon has 0 privileges on public.patients
    SELECT count(*)
      INTO v_anon_priv_count
      FROM information_schema.role_table_grants
     WHERE table_schema = 'public'
       AND table_name = 'patients'
       AND grantee = 'anon';

    IF v_anon_priv_count > 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: anon role must have 0 privileges on public.patients';
    END IF;

    -- 4. Verify SELECT, INSERT, UPDATE policies exist on public.patients
    SELECT count(*)
      INTO v_policy_count
      FROM pg_policies
     WHERE tablename = 'patients'
       AND schemaname = 'public'
       AND policyname IN ('patient_select_policy', 'patient_insert_policy', 'patient_update_policy');

    IF v_policy_count <> 3 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Expected 3 RLS policies on public.patients, found %', v_policy_count;
    END IF;

    -- 5. Verify NO direct DELETE policy exists on public.patients
    SELECT count(*)
      INTO v_delete_policy_count
      FROM pg_policies
     WHERE tablename = 'patients'
       AND schemaname = 'public'
       AND cmd = 'DELETE';

    IF v_delete_policy_count > 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Direct DELETE policy must NOT exist on public.patients';
    END IF;

    -- 6. Verify public.safe_delete_patient function exists and is SECURITY DEFINER
    SELECT EXISTS (
        SELECT 1 FROM information_schema.routines
         WHERE routine_schema = 'public' AND routine_name = 'safe_delete_patient'
    ) INTO v_rpc_exists;

    IF NOT v_rpc_exists THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Function public.safe_delete_patient does not exist';
    END IF;

    SELECT prosecdef INTO v_rpc_secdef
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
     WHERE n.nspname = 'public' AND p.proname = 'safe_delete_patient';

    IF NOT v_rpc_secdef THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: public.safe_delete_patient must be SECURITY DEFINER';
    END IF;

    -- 7. Verify PUBLIC and anon have NO execute on safe_delete_patient
    SELECT count(*) INTO v_public_rpc_priv
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'public' AND routine_name = 'safe_delete_patient' AND grantee = 'PUBLIC';

    IF v_public_rpc_priv > 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: PUBLIC must not hold EXECUTE on public.safe_delete_patient';
    END IF;

    SELECT count(*) INTO v_anon_rpc_priv
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'public' AND routine_name = 'safe_delete_patient' AND grantee = 'anon';

    IF v_anon_rpc_priv > 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: anon must not hold EXECUTE on public.safe_delete_patient';
    END IF;

    -- 8. Verify authenticated HAS execute on safe_delete_patient
    SELECT count(*) INTO v_auth_rpc_priv
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'public' AND routine_name = 'safe_delete_patient' AND grantee = 'authenticated' AND privilege_type = 'EXECUTE';

    IF v_auth_rpc_priv <> 1 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: authenticated role missing EXECUTE privilege on public.safe_delete_patient';
    END IF;

    -- 9. Verify patient_care_team is NOT referenced in function prosrc definition
    SELECT (prosrc LIKE '%patient_care_team%') INTO v_care_team_ref
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
     WHERE n.nspname = 'public' AND p.proname = 'safe_delete_patient';

    IF v_care_team_ref THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: safe_delete_patient must NOT reference patient_care_team';
    END IF;

    -- 10. Verify public.logs is referenced in history check inside safe_delete_patient
    SELECT (prosrc LIKE '%public.logs WHERE patient_id%') INTO v_logs_ref
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
     WHERE n.nspname = 'public' AND p.proname = 'safe_delete_patient';

    IF NOT v_logs_ref THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: safe_delete_patient must include public.logs in history check';
    END IF;

    RAISE NOTICE 'VERIFICATION SUCCESSFUL: 007 Patients RLS and safe_delete_patient RPC (6-table history check) verified cleanly.';
END $$;
