-- Read-only verification for migration 012. Run manually only after approval.
DO $verify$
DECLARE
    v_definition text;
BEGIN
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.consultations'::regclass) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: consultations RLS is not enabled';
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.patient_dental_state'::regclass) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: patient_dental_state RLS is not enabled';
    END IF;
    IF has_table_privilege('anon', 'public.consultations', 'SELECT,INSERT,UPDATE,DELETE')
       OR has_table_privilege('authenticated', 'public.consultations', 'SELECT,INSERT,UPDATE,DELETE')
       OR has_table_privilege('anon', 'public.patient_dental_state', 'SELECT,INSERT,UPDATE,DELETE')
       OR has_table_privilege('authenticated', 'public.patient_dental_state', 'SELECT,INSERT,UPDATE,DELETE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: browser roles retain direct clinical table privileges';
    END IF;

    SELECT pg_get_functiondef('public.get_or_initialize_consultation(uuid)'::regprocedure)
      INTO v_definition;
    IF v_definition NOT LIKE '%auth.uid()%'
       OR v_definition NOT LIKE '%is_active = true%'
       OR v_definition NOT LIKE '%approved_at IS NOT NULL%'
       OR v_definition NOT LIKE '%role IN (''doctor'', ''admin'')%'
       OR v_definition NOT LIKE '%appointment.status::text IN (''pending'', ''confirmed'')%'
       OR v_definition NOT LIKE '%appointment.doctor_id = v_caller_id%'
       OR v_definition LIKE '%get_latest_by_patient%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: read RPC authorization or appointment containment differs';
    END IF;

    SELECT pg_get_functiondef('public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean)'::regprocedure)
      INTO v_definition;
    IF v_definition NOT LIKE '%FOR UPDATE%'
       OR v_definition NOT LIKE '%CONSULTATION_VERSION_CONFLICT%'
       OR v_definition NOT LIKE '%CONSULTATION_DENTAL_STATE_VERSION_CONFLICT%'
       OR v_definition NOT LIKE '%UPDATE public.consultations%'
       OR v_definition NOT LIKE '%UPDATE public.patient_dental_state%'
       OR v_definition NOT LIKE '%INSERT INTO public.logs%'
       OR v_definition LIKE '%service_role%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: save RPC locking, versioning, audit, or containment differs';
    END IF;

    IF has_function_privilege('PUBLIC', 'public.get_or_initialize_consultation(uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.get_or_initialize_consultation(uuid)', 'EXECUTE')
       OR has_function_privilege('PUBLIC', 'public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean)', 'EXECUTE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: PUBLIC or anon can execute consultation RPCs';
    END IF;
    IF NOT has_function_privilege('authenticated', 'public.get_or_initialize_consultation(uuid)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean)', 'EXECUTE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: authenticated lacks consultation RPC execution';
    END IF;
END
$verify$;
