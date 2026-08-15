-- Verification script for Migration 005: Targeted Patients Security Containment

DO $$
DECLARE
    v_rls_enabled boolean;
    v_force_rls boolean;
    v_policy_count integer;
    v_anon_privileges integer;
    v_auth_privileges integer;
    v_public_privileges integer;
    v_patient_count integer;
BEGIN
    -- 1. Check Row Level Security flags on public.patients
    SELECT relrowsecurity, relforcerowsecurity
      INTO v_rls_enabled, v_force_rls
      FROM pg_class
     WHERE oid = 'public.patients'::regclass;

    IF NOT v_rls_enabled THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Row Level Security is not enabled on public.patients';
    END IF;

    IF v_force_rls THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: FORCE ROW LEVEL SECURITY should remain false on public.patients';
    END IF;

    -- 2. Check that none of the 5 removed policies exist
    SELECT count(*)
      INTO v_policy_count
      FROM pg_policies
     WHERE tablename = 'patients'
       AND schemaname = 'public'
       AND policyname IN (
           'Allow all',
           'Allow clinic staff to insert patients',
           'Allow clinic staff to read patients',
           'Allow clinic staff to update patients',
           'Allow initial data migration'
       );

    IF v_policy_count > 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Insecure/unverified policies still exist on public.patients';
    END IF;

    -- 3. Check table privileges on public.patients for anon, authenticated, and PUBLIC
    SELECT count(*)
      INTO v_anon_privileges
      FROM information_schema.role_table_grants
     WHERE table_schema = 'public' AND table_name = 'patients' AND grantee = 'anon';

    SELECT count(*)
      INTO v_auth_privileges
      FROM information_schema.role_table_grants
     WHERE table_schema = 'public' AND table_name = 'patients' AND grantee = 'authenticated';

    SELECT count(*)
      INTO v_public_privileges
      FROM information_schema.role_table_grants
     WHERE table_schema = 'public' AND table_name = 'patients' AND grantee = 'PUBLIC';

    IF v_anon_privileges > 0 OR v_auth_privileges > 0 OR v_public_privileges > 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Table privileges remain granted to anon, authenticated, or PUBLIC on public.patients';
    END IF;

    -- 4. Verify patient table data is intact
    SELECT count(*) INTO v_patient_count FROM public.patients;
    RAISE NOTICE 'VERIFICATION SUCCESSFUL: Patients containment active. Patient row count: %', v_patient_count;
END $$;
