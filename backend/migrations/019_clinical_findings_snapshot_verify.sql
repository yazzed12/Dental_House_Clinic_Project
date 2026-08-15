-- Read-only verification for Migration 019.
DO $$
DECLARE
    v_active regprocedure;
    v_superseded regprocedure;
    v_legacy regprocedure;
    v_active_definition text;
    v_patient_history text;
    v_doctor_history text;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'consultations'
           AND column_name = 'clinical_findings_snapshot'
           AND data_type = 'jsonb' AND is_nullable = 'YES'
           AND column_default IS NULL
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: nullable jsonb clinical findings column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'public.consultations'::regclass
           AND conname = 'consultations_clinical_findings_snapshot_ck'
           AND contype = 'c'
    ) OR to_regprocedure('security.clinical_findings_snapshot_valid(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: clinical findings validation missing';
    END IF;

    v_active := to_regprocedure('public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)');
    v_superseded := to_regprocedure('public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean)');
    v_legacy := to_regprocedure('public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean)');
    IF v_active IS NULL OR v_superseded IS NULL OR v_legacy IS NULL THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: required save signatures missing';
    END IF;

    IF NOT has_function_privilege('authenticated', v_active, 'EXECUTE')
       OR has_function_privilege('authenticated', v_superseded, 'EXECUTE')
       OR has_function_privilege('authenticated', v_legacy, 'EXECUTE')
       OR has_function_privilege('anon', v_active, 'EXECUTE')
       OR has_function_privilege('anon', v_superseded, 'EXECUTE')
       OR has_function_privilege('anon', v_legacy, 'EXECUTE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: save RPC role privileges invalid';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc AS proc
        CROSS JOIN LATERAL aclexplode(coalesce(proc.proacl, acldefault('f', proc.proowner))) AS acl_entry
         WHERE proc.oid IN (v_active::oid, v_superseded::oid, v_legacy::oid)
           AND acl_entry.grantee = 0 AND acl_entry.privilege_type = 'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: PUBLIC can execute protected save RPC';
    END IF;

    IF NOT security.clinical_findings_snapshot_valid(NULL)
       OR NOT security.clinical_findings_snapshot_valid('[]'::jsonb) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: NULL versus explicit-empty semantics invalid';
    END IF;

    SELECT lower(pg_get_functiondef(v_active)) INTO v_active_definition;
    IF position('security.clinical_findings_snapshot_valid' IN v_active_definition) = 0
       OR position('consultation_clinical_findings_tooth_data_mismatch' IN v_active_definition) = 0
       OR position('set clinical_findings_snapshot = p_clinical_findings_snapshot' IN v_active_definition) = 0
       OR position('distinct on (lower(btrim(symptom.value #>> ''{}'')))' IN v_active_definition) = 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: structured save validation or symptom derivation missing';
    END IF;

    SELECT lower(pg_get_functiondef('public.get_patient_consultation_history(uuid)'::regprocedure))
      INTO v_patient_history;
    SELECT lower(pg_get_functiondef('public.list_doctor_consultation_history()'::regprocedure))
      INTO v_doctor_history;
    IF position('''clinicalfindings'', consultation.clinical_findings_snapshot' IN v_patient_history) = 0
       OR position('''clinicalfindings'', consultation.clinical_findings_snapshot' IN v_doctor_history) = 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: history structured findings projection missing';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc AS proc
         WHERE proc.oid IN (
             'public.get_patient_consultation_history(uuid)'::regprocedure::oid,
             'public.list_doctor_consultation_history()'::regprocedure::oid
         ) AND (NOT proc.prosecdef OR NOT ('search_path=pg_catalog, pg_temp' = ANY(proc.proconfig)))
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: history RPC hardening invalid';
    END IF;

    IF has_function_privilege('anon', 'public.get_patient_consultation_history(uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.list_doctor_consultation_history()', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.get_patient_consultation_history(uuid)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.list_doctor_consultation_history()', 'EXECUTE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: history RPC privileges invalid';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc AS proc
        CROSS JOIN LATERAL aclexplode(coalesce(proc.proacl, acldefault('f', proc.proowner))) AS acl_entry
         WHERE proc.oid IN (
             'public.get_patient_consultation_history(uuid)'::regprocedure::oid,
             'public.list_doctor_consultation_history()'::regprocedure::oid
         ) AND acl_entry.grantee = 0 AND acl_entry.privilege_type = 'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: PUBLIC can execute protected history RPC';
    END IF;

    -- Migration 019 intentionally performs no UPDATE/backfill. Existing NULLs remain NULL;
    -- an explicit [] remains distinguishable by the nullable column and direct projection.
    RAISE NOTICE 'VERIFICATION SUCCESSFUL: structured clinical findings snapshot is contained.';
END $$;
