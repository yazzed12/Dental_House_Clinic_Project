-- Verification for Migration 011: Appointment RPC enum casts.

DO $$
DECLARE
    v_create_definition text;
    v_update_definition text;
    v_status_definition text;
    v_public_execute integer;
    v_anon_execute integer;
    v_authenticated_execute integer;
BEGIN
    SELECT p.prosrc INTO v_create_definition
      FROM pg_proc AS p
      JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'create_appointment'
       AND p.pronargs = 8;

    SELECT p.prosrc INTO v_update_definition
      FROM pg_proc AS p
      JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'update_appointment'
       AND p.pronargs = 2;

    SELECT p.prosrc INTO v_status_definition
      FROM pg_proc AS p
      JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'update_appointment_status'
       AND p.pronargs = 2;

    IF v_create_definition IS NULL
       OR v_create_definition NOT LIKE '%normalize_appointment_type(p_type)::public.appointment_type%'
       OR v_create_definition NOT LIKE '%normalize_appointment_status(p_status)::public.appointment_status%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: create_appointment enum casts are missing';
    END IF;

    IF v_update_definition IS NULL
       OR v_update_definition NOT LIKE '%normalize_appointment_type(p_updates ->> ''type'')::public.appointment_type%'
       OR v_update_definition NOT LIKE '%normalize_appointment_status(p_updates ->> ''status'')::public.appointment_status%'
       OR v_update_definition NOT LIKE '%ELSE appointment.type%'
       OR v_update_definition NOT LIKE '%ELSE appointment.status%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: update_appointment enum branches are not consistently typed';
    END IF;

    IF v_status_definition IS NULL
       OR v_status_definition NOT LIKE '%v_new_status::public.appointment_status%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: update_appointment_status enum cast is missing';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_proc AS p
          JOIN pg_namespace AS n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname IN ('create_appointment', 'update_appointment', 'update_appointment_status')
           AND (NOT p.prosecdef OR NOT ('search_path=pg_catalog, pg_temp' = ANY(p.proconfig)))
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: a replaced Appointment RPC lost security hardening';
    END IF;

    SELECT count(*) INTO v_public_execute
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'public'
       AND routine_name IN ('create_appointment', 'update_appointment', 'update_appointment_status')
       AND grantee = 'PUBLIC';
    SELECT count(*) INTO v_anon_execute
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'public'
       AND routine_name IN ('create_appointment', 'update_appointment', 'update_appointment_status')
       AND grantee = 'anon';
    SELECT count(*) INTO v_authenticated_execute
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'public'
       AND routine_name IN ('create_appointment', 'update_appointment', 'update_appointment_status')
       AND grantee = 'authenticated'
       AND privilege_type = 'EXECUTE';

    IF v_public_execute <> 0 OR v_anon_execute <> 0 OR v_authenticated_execute <> 3 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: replaced Appointment RPC privileges are invalid';
    END IF;

    RAISE NOTICE 'VERIFICATION SUCCESSFUL: Appointment RPC enum assignments are explicitly typed.';
END $$;
