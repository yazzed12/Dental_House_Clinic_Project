-- Read-only verification for Migration 016. Do not run as part of this local task.

DO $$
DECLARE
    v_patient_definition text;
    v_doctor_definition text;
    v_actor_definition text;
BEGIN
    SELECT pg_get_functiondef('security.consultation_history_actor()'::regprocedure)
      INTO v_actor_definition;
    IF v_actor_definition NOT LIKE '%supabase_user_id = auth.uid()%'
       OR v_actor_definition NOT LIKE '%is_active = true%'
       OR v_actor_definition NOT LIKE '%approved_at IS NOT NULL%'
       OR v_actor_definition NOT LIKE '%role IN (''doctor'', ''admin'')%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: history actor containment is incomplete';
    END IF;

    SELECT pg_get_functiondef('public.get_patient_consultation_history(uuid)'::regprocedure)
      INTO v_patient_definition;
    IF v_patient_definition NOT LIKE '%CONSULTATION_HISTORY_PATIENT_NOT_FOUND%'
       OR v_patient_definition NOT LIKE '%appointment.doctor_id = v_caller_id%'
       OR v_patient_definition NOT LIKE '%owned_consultation.doctor_id = v_caller_id%'
       OR v_patient_definition NOT LIKE '%consultation.last_updated DESC NULLS LAST%'
       OR v_patient_definition NOT LIKE '%consultation.created_at DESC NULLS LAST%'
       OR v_patient_definition NOT LIKE '%consultation.id DESC%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: patient history projection is incomplete';
    END IF;

    SELECT pg_get_functiondef('public.list_doctor_consultation_history()'::regprocedure)
      INTO v_doctor_definition;
    IF v_doctor_definition NOT LIKE '%v_caller_role = ''admin'' OR report.doctor_id = v_caller_id%'
       OR v_doctor_definition NOT LIKE '%report.created_at DESC NULLS LAST%'
       OR v_doctor_definition NOT LIKE '%consultation.last_updated DESC NULLS LAST%'
       OR v_doctor_definition NOT LIKE '%consultation.created_at DESC NULLS LAST%'
       OR v_doctor_definition NOT LIKE '%consultation.id DESC%'
       OR v_doctor_definition NOT LIKE '%LEFT JOIN LATERAL%'
       OR v_doctor_definition NOT LIKE '%report.appointment_id IS NOT NULL%'
       OR v_doctor_definition NOT LIKE '%report.doctor_id IS NULL%'
       OR v_doctor_definition NOT LIKE '%consultation.doctor_id IS NULL%'
       OR v_doctor_definition NOT LIKE '%consultation.doctor_id = report.doctor_id%'
       OR v_doctor_definition NOT LIKE '%public.consultation_procedures%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Doctor history projection is incomplete';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_proc AS proc
          JOIN pg_namespace AS namespace ON namespace.oid = proc.pronamespace
         WHERE namespace.nspname = 'public'
           AND proc.proname IN (
               'get_patient_consultation_history', 'list_doctor_consultation_history'
           )
           AND (NOT proc.prosecdef
                OR NOT ('search_path=pg_catalog, pg_temp' = ANY(proc.proconfig)))
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: a history RPC lacks SECURITY DEFINER hardening';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.routine_privileges
         WHERE routine_schema = 'public'
           AND routine_name IN (
               'get_patient_consultation_history', 'list_doctor_consultation_history'
           )
           AND grantee IN ('PUBLIC', 'anon')
           AND privilege_type = 'EXECUTE'
    ) OR (
        SELECT count(DISTINCT routine_name)
          FROM information_schema.routine_privileges
         WHERE routine_schema = 'public'
           AND routine_name IN (
               'get_patient_consultation_history', 'list_doctor_consultation_history'
           )
           AND grantee = 'authenticated'
           AND privilege_type = 'EXECUTE'
    ) <> 2 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: history RPC privileges are invalid';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.role_table_grants
         WHERE table_schema = 'public'
           AND table_name = 'clinical_reports'
           AND grantee IN ('PUBLIC', 'anon', 'authenticated')
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: browser roles retain direct clinical_reports privileges';
    END IF;

    RAISE NOTICE 'VERIFICATION SUCCESSFUL: Consultation History is contained and Supabase-native.';
END $$;
