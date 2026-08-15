-- Verification for Migration 010: Supabase-native Appointments vertical slice.

DO $$
DECLARE
    v_definition text;
    v_public_execute integer;
    v_anon_execute integer;
    v_authenticated_execute integer;
    v_authenticated_table_privileges integer;
BEGIN
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.appointments'::regclass) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: appointments RLS is not enabled';
    END IF;

    SELECT count(*) INTO v_authenticated_table_privileges
      FROM information_schema.role_table_grants
     WHERE table_schema = 'public'
       AND table_name = 'appointments'
       AND grantee IN ('anon', 'authenticated');
    IF v_authenticated_table_privileges <> 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: browser roles retain direct appointments privileges';
    END IF;

    SELECT p.prosrc INTO v_definition
      FROM pg_proc AS p
      JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'get_appointments' AND p.pronargs = 0;
    IF v_definition IS NULL
       OR v_definition NOT LIKE '%caller.supabase_user_id = auth.uid()%'
       OR v_definition NOT LIKE '%caller.is_active = true%'
       OR v_definition NOT LIKE '%caller.approved_at IS NOT NULL%'
       OR v_definition LIKE '%personal_email%'
       OR v_definition LIKE '%hashed_password%'
       OR v_definition LIKE '%password%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: appointment read projection is unsafe';
    END IF;

    IF replace(pg_get_function_result('public.get_appointments()'::regprocedure), '"', '') <>
       'TABLE(id uuid, patient_id uuid, patient text, doctor_id uuid, doctor text, date date, time text, type text, status text, condition text, notes text)' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: appointment RPC response contract changed';
    END IF;

    SELECT p.prosrc INTO v_definition
      FROM pg_proc AS p
      JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'create_appointment' AND p.pronargs = 8;
    IF v_definition IS NULL
       OR v_definition NOT LIKE '%doctor.id = p_doctor_id%'
       OR v_definition NOT LIKE '%doctor.role = ''doctor''%'
       OR v_definition NOT LIKE '%doctor.is_active = true%'
       OR v_definition NOT LIKE '%doctor.approved_at IS NOT NULL%'
       OR v_definition NOT LIKE '%doctor.supabase_user_id IS NOT NULL%'
       OR v_definition NOT LIKE '%p_patient_id%'
       OR v_definition NOT LIKE '%p_doctor_id%'
       OR v_definition NOT LIKE '%INSERT INTO public.appointments%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: appointment creation validation is incomplete';
    END IF;

    SELECT p.prosrc INTO v_definition
      FROM pg_proc AS p
      JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE n.nspname = 'security'
       AND p.proname = 'normalize_appointment_status'
       AND p.pronargs = 1;
    IF v_definition IS NULL
       OR v_definition NOT LIKE '%(''pending'', ''confirmed'', ''completed'', ''cancelled'', ''no_show'')%'
       OR v_definition LIKE '%''arrived''%'
       OR v_definition LIKE '%''scheduled''%'
       OR v_definition LIKE '%''in_progress''%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: appointment status contract does not match production enum';
    END IF;

    SELECT p.prosrc INTO v_definition
      FROM pg_proc AS p
      JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'finish_appointment_by_patient'
       AND p.proargtypes = '2950 2950'::oidvector;
    IF v_definition IS NULL
       OR v_definition NOT LIKE '%appointment.status::text IN (''pending'', ''confirmed'')%'
       OR v_definition NOT LIKE '%appointment.doctor_id IS NOT NULL%'
       OR v_definition NOT LIKE '%v_caller_role = ''admin''%'
       OR v_definition NOT LIKE '%appointment.doctor_id = v_caller_id%'
       OR v_definition LIKE '%lower(appointment.status)%'
       OR v_definition LIKE '%''finished''%'
       OR v_definition NOT LIKE '%SET status = ''completed''%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: finish lifecycle status predicate is not enum-safe';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_proc AS p
          JOIN pg_namespace AS n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname IN (
               'get_appointments', 'create_appointment', 'update_appointment',
               'update_appointment_status', 'mark_appointment_arrived', 'finish_appointment_by_patient',
               'delete_appointment'
           )
           AND (NOT p.prosecdef OR NOT ('search_path=pg_catalog, pg_temp' = ANY(p.proconfig)))
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: an appointment RPC lacks SECURITY DEFINER hardening';
    END IF;

    SELECT count(*) INTO v_public_execute
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'public'
       AND routine_name IN (
           'get_appointments', 'create_appointment', 'update_appointment',
           'update_appointment_status', 'mark_appointment_arrived', 'finish_appointment_by_patient',
           'delete_appointment'
       )
       AND grantee = 'PUBLIC';
    SELECT count(*) INTO v_anon_execute
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'public'
       AND routine_name IN (
           'get_appointments', 'create_appointment', 'update_appointment',
           'update_appointment_status', 'mark_appointment_arrived', 'finish_appointment_by_patient',
           'delete_appointment'
       )
       AND grantee = 'anon';
    SELECT count(*) INTO v_authenticated_execute
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'public'
       AND routine_name IN (
           'get_appointments', 'create_appointment', 'update_appointment',
           'update_appointment_status', 'mark_appointment_arrived', 'finish_appointment_by_patient',
           'delete_appointment'
       )
       AND grantee = 'authenticated'
       AND privilege_type = 'EXECUTE';

    IF v_public_execute <> 0 OR v_anon_execute <> 0 OR v_authenticated_execute <> 7 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: appointment RPC privileges are invalid';
    END IF;

    RAISE NOTICE 'VERIFICATION SUCCESSFUL: Supabase-native appointment contract is contained and hardened.';
END $$;
