-- Migration 021 verifier: read-only contract and privilege assertions.
DO $verify$
DECLARE
    v_signature regprocedure := to_regprocedure('public.list_doctor_consultation_history()');
    v_definition text;
    v_security_definer boolean;
    v_config text[];
BEGIN
    IF v_signature IS NULL THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: history function missing';
    END IF;
    SELECT lower(pg_get_functiondef(v_signature)), proc.prosecdef, proc.proconfig
      INTO v_definition, v_security_definer, v_config
      FROM pg_proc AS proc WHERE proc.oid=v_signature::oid;

    IF NOT v_security_definer
       OR NOT ('search_path=pg_catalog, pg_temp'=ANY(coalesce(v_config, ARRAY[]::text[]))) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: SECURITY DEFINER/fixed search_path missing';
    END IF;
    IF position('security.list_doctor_consultation_history_base()' IN v_definition)=0
       OR position('''clinicalfindings''' IN v_definition)=0
       OR position('''reportsnapshot''' IN v_definition)=0
       OR position('''snapshotversion''' IN v_definition)=0
       OR position('''reviewedat''' IN v_definition)=0
       OR position('''finalizedat''' IN v_definition)=0
       OR position('report.report_snapshot' IN v_definition)=0
       OR position('report.snapshot_version' IN v_definition)=0
       OR position('report.reviewed_at' IN v_definition)=0
       OR position('report.finalized_at' IN v_definition)=0
       OR position('report.id = nullif(item.value ->> ''reportid'', '''')::uuid' IN v_definition)=0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: snapshot projection/contained report join missing';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM pg_proc AS proc
          CROSS JOIN LATERAL aclexplode(
              coalesce(proc.proacl, acldefault('f', proc.proowner))
          ) AS acl_entry
         WHERE proc.oid=v_signature::oid
           AND acl_entry.grantee=0
           AND acl_entry.privilege_type='EXECUTE'
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: PUBLIC can execute history function';
    END IF;
    IF has_function_privilege('anon', v_signature, 'EXECUTE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: anon can execute history function';
    END IF;
    IF NOT has_function_privilege('authenticated', v_signature, 'EXECUTE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: authenticated cannot execute history function';
    END IF;
    IF to_regprocedure('public.get_patient_clinical_reports(uuid)') IS NULL THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: patient reports function unexpectedly missing';
    END IF;
END
$verify$;

SELECT 'VERIFICATION SUCCESSFUL: history snapshot alignment is contained' AS result;
