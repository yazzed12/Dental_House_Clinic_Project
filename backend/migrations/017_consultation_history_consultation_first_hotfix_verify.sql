-- Read-only verification for Migration 017. Do not run as part of this local task.

DO $$
DECLARE
    v_definition text;
BEGIN
    SELECT pg_get_functiondef('public.list_doctor_consultation_history()'::regprocedure)
      INTO v_definition;

    IF v_definition IS NULL
       OR v_definition NOT LIKE '%FROM public.consultations AS consultation%'
       OR v_definition NOT LIKE '%eligible_consultations AS%'
       OR v_definition NOT LIKE '%LEFT JOIN LATERAL%public.clinical_reports AS candidate%'
       OR v_definition NOT LIKE '%candidate.patient_id = consultation.patient_id%'
       OR v_definition NOT LIKE '%candidate.doctor_id = consultation.doctor_id%'
       OR v_definition NOT LIKE '%consultation.appointment_id IS NOT NULL%'
       OR v_definition NOT LIKE '%candidate.appointment_id = consultation.appointment_id%'
       OR v_definition NOT LIKE '%candidate.created_at DESC NULLS LAST%'
       OR v_definition NOT LIKE '%candidate.id DESC%'
       OR v_definition NOT LIKE '%LIMIT 1%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: consultation-first report matching is incomplete';
    END IF;

    IF v_definition NOT LIKE '%consultation.doctor_id = v_caller_id%'
       OR v_definition NOT LIKE '%consultation.doctor_id IS NULL%'
       OR v_definition NOT LIKE '%relationship_appointment.doctor_id = v_caller_id%'
       OR v_definition NOT LIKE '%owned_consultation.doctor_id = v_caller_id%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: consultation ownership containment is incomplete';
    END IF;

    IF v_definition NOT LIKE '%UNION ALL%'
       OR v_definition NOT LIKE '%NOT EXISTS%matched_report_ids%'
       OR v_definition NOT LIKE '%''reportOnly'', true%'
       OR v_definition NOT LIKE '%''consultationId'', NULL%'
       OR v_definition NOT LIKE '%''procedures'', ''[]''::jsonb%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: unmatched report preservation is incomplete';
    END IF;

    IF v_definition NOT LIKE '%''reportOnly'', false%'
       OR v_definition NOT LIKE '%''reportId'', item.report_id%'
       OR v_definition NOT LIKE '%''sessionNote'', item.session_note%'
       OR v_definition NOT LIKE '%selection.consultation_id = consultation.id%'
       OR v_definition NOT LIKE '%history.sort_updated DESC NULLS LAST%'
       OR v_definition NOT LIKE '%history.sort_created DESC NULLS LAST%'
       OR v_definition NOT LIKE '%history.stable_id DESC%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: consultation projection or ordering is incomplete';
    END IF;

    IF v_definition LIKE '%INSERT INTO public.%'
       OR v_definition LIKE '%UPDATE public.%'
       OR v_definition LIKE '%DELETE FROM public.%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: history RPC is not read-only';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_proc AS proc
         WHERE proc.oid = 'public.list_doctor_consultation_history()'::regprocedure
           AND (NOT proc.prosecdef
                OR NOT ('search_path=pg_catalog, pg_temp' = ANY(proc.proconfig)))
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: history RPC hardening changed';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.routine_privileges
         WHERE routine_schema = 'public'
           AND routine_name = 'list_doctor_consultation_history'
           AND grantee IN ('PUBLIC', 'anon')
           AND privilege_type = 'EXECUTE'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.routine_privileges
         WHERE routine_schema = 'public'
           AND routine_name = 'list_doctor_consultation_history'
           AND grantee = 'authenticated'
           AND privilege_type = 'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: history RPC privileges are invalid';
    END IF;

    RAISE NOTICE 'VERIFICATION SUCCESSFUL: Consultation History is consultation-first.';
END $$;
