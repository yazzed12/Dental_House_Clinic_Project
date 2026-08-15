-- Read-only verification for Migration 018. Run only after separately approved deployment.
DO $$
DECLARE
    v_save text;
    v_report text;
    v_history text;
    v_save_eight regprocedure;
    v_save_six regprocedure;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='consultations' AND column_name='symptoms_snapshot' AND data_type='jsonb')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='clinical_reports' AND column_name='consultation_id' AND data_type='uuid') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: session/report linkage columns missing';
    END IF;

    v_save_eight := to_regprocedure('public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean)');
    v_save_six := to_regprocedure('public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean)');
    IF v_save_eight IS NULL OR v_save_six IS NULL THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: required consultation save overload missing';
    END IF;

    SELECT pg_get_functiondef(v_save_eight) INTO v_save;
    SELECT pg_get_functiondef('public.save_clinical_report(uuid,uuid,uuid,text,text,jsonb,text,text,text,text,text)'::regprocedure) INTO v_report;
    SELECT lower(pg_get_functiondef(
        'public.list_doctor_consultation_history()'::regprocedure
    )) INTO v_history;

    IF v_save NOT LIKE '%jsonb_typeof(p_symptoms_snapshot)%'
       OR v_save NOT LIKE '%UPDATE public.consultations%SET symptoms_snapshot%'
       OR v_save NOT LIKE '%public.save_current_consultation(%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: atomic symptom persistence missing';
    END IF;
    IF NOT has_function_privilege('authenticated', v_save_eight, 'EXECUTE')
       OR has_function_privilege('authenticated', v_save_six, 'EXECUTE')
       OR has_function_privilege('anon', v_save_eight, 'EXECUTE')
       OR has_function_privilege('anon', v_save_six, 'EXECUTE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: consultation save overload role privileges are invalid';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM pg_proc AS proc
          CROSS JOIN LATERAL aclexplode(coalesce(proc.proacl, acldefault('f', proc.proowner))) AS privilege
         WHERE proc.oid IN (v_save_eight::oid, v_save_six::oid)
           AND privilege.grantee = 0
           AND privilege.privilege_type = 'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: PUBLIC can execute a consultation save overload';
    END IF;
    IF v_report NOT LIKE '%security.clinical_report_actor()%'
       OR v_report NOT LIKE '%INSERT INTO public.clinical_reports%'
       OR v_report NOT LIKE '%INSERT INTO public.logs%'
       OR v_report NOT LIKE '%p_symptoms IS DISTINCT FROM v_consultation.symptoms_snapshot%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: report containment/linkage missing';
    END IF;
    IF position('when consultation.symptoms_snapshot is not null' IN v_history) = 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: history symptom snapshot precedence missing';
    END IF;
    IF position('then consultation.symptoms_snapshot' IN v_history) = 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: history symptom snapshot value missing';
    END IF;
    IF position('else security.consultation_history_json_array(consultation.report_symptoms)' IN v_history) = 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: history legacy symptom fallback missing';
    END IF;
    IF position('''reportonly'', true' IN v_history) = 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: history report-only compatibility missing';
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.role_table_grants
         WHERE table_schema = 'public'
           AND table_name = 'clinical_reports'
           AND grantee = 'authenticated'
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: direct report writes remain available';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_policies
         WHERE schemaname = 'public'
           AND tablename = 'clinical_reports'
           AND policyname IN ('Allow clinic staff full access', 'Allow initial data migration')
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: legacy clinical_reports policies remain';
    END IF;
    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint AS constraint_record
         WHERE constraint_record.conrelid = 'public.clinical_reports'::regclass
           AND constraint_record.contype = 'f'
           AND constraint_record.confrelid = 'public.consultations'::regclass
           AND constraint_record.conkey = ARRAY[
               (SELECT attribute.attnum::smallint
                  FROM pg_attribute AS attribute
                 WHERE attribute.attrelid = 'public.clinical_reports'::regclass
                   AND attribute.attname = 'consultation_id')
           ]::smallint[]
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: clinical_reports consultation foreign key missing';
    END IF;
    RAISE NOTICE 'VERIFICATION SUCCESSFUL: clinical session persistence is contained.';
END $$;
