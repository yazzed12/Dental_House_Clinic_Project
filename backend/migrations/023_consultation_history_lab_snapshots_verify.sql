-- Migration 023 verifier: read-only projection, privilege, and isolation assertions.
DO $verify$
DECLARE
    v_signature regprocedure := to_regprocedure('public.list_doctor_consultation_history()');
    v_definition text;
    v_security_definer boolean;
    v_config text[];
    v_report_function regprocedure;
BEGIN
    IF v_signature IS NULL THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: history function missing';
    END IF;

    SELECT regexp_replace(lower(pg_get_functiondef(proc.oid)),'[[:space:]]+',' ','g'),
           proc.prosecdef,proc.proconfig
      INTO v_definition,v_security_definer,v_config
      FROM pg_proc AS proc WHERE proc.oid=v_signature::oid;

    IF NOT v_security_definer
       OR NOT ('search_path=pg_catalog, pg_temp'=ANY(coalesce(v_config,ARRAY[]::text[]))) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: SECURITY DEFINER/fixed search_path missing';
    END IF;
    IF position('security.list_doctor_consultation_history_base()' IN v_definition)=0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: contained history base call missing';
    END IF;
    IF position('''labnote''' IN v_definition)=0
       OR position('consultation.lab_note' IN v_definition)=0
       OR position('''labitems''' IN v_definition)=0
       OR v_definition !~ 'coalesce\(lab_snapshot\.items,[[:space:]]*''\[\]''::jsonb\)' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: labNote/labItems projection or empty-array fallback missing';
    END IF;
    IF position('public.consultation_lab_items' IN v_definition)=0
       OR v_definition !~ 'lab_item\.consultation_id[[:space:]]*=[[:space:]]*consultation\.id'
       OR position('lab_item.lab_name_snapshot' IN v_definition)=0
       OR position('lab_item.product_name_snapshot' IN v_definition)=0
       OR position('lab_item.unit_price_snapshot' IN v_definition)=0
       OR position('lab_item.quantity' IN v_definition)=0
       OR position('lab_item.total_amount' IN v_definition)=0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: immutable Lab snapshot source is incomplete';
    END IF;
    IF position('public.labs ' IN v_definition)>0
       OR position('public.lab_products ' IN v_definition)>0
       OR position('current_price' IN v_definition)>0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: history uses mutable Lab catalog values';
    END IF;
    IF position('''reportsnapshot''' IN v_definition)=0
       OR position('''snapshotversion''' IN v_definition)=0
       OR position('''reviewedat''' IN v_definition)=0
       OR position('''finalizedat''' IN v_definition)=0
       OR position('report.report_snapshot' IN v_definition)=0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Migration 021 report snapshot fields were not preserved';
    END IF;
    IF position('order by item.ordinality' IN v_definition)=0
       OR position('order by lab_item.created_at' IN v_definition)=0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: deterministic history/Lab ordering missing';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc AS proc
        CROSS JOIN LATERAL aclexplode(
            coalesce(proc.proacl,acldefault('f',proc.proowner))
        ) AS acl_entry
        WHERE proc.oid=v_signature::oid AND acl_entry.grantee=0
          AND acl_entry.privilege_type='EXECUTE'
    ) THEN RAISE EXCEPTION 'VERIFICATION FAILED: PUBLIC can execute history function'; END IF;
    IF has_function_privilege('anon',v_signature,'EXECUTE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: anon can execute history function';
    END IF;
    IF NOT has_function_privilege('authenticated',v_signature,'EXECUTE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: authenticated cannot execute history function';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='clinical_reports'
           AND lower(column_name) LIKE '%lab%'
    ) THEN RAISE EXCEPTION 'VERIFICATION FAILED: Lab columns entered clinical_reports'; END IF;

    FOR v_report_function IN
        SELECT proc.oid::regprocedure
          FROM pg_proc AS proc
          JOIN pg_namespace AS namespace ON namespace.oid=proc.pronamespace
         WHERE namespace.nspname IN ('public','security')
           AND (proc.proname LIKE '%clinical_report%' OR proc.proname LIKE '%report%')
    LOOP
        SELECT lower(pg_get_functiondef(v_report_function)) INTO v_definition;
        IF position('consultation_lab_items' IN v_definition)>0
           OR position('lab_note' IN v_definition)>0 THEN
            RAISE EXCEPTION 'VERIFICATION FAILED: Lab data entered Medical Report function %',v_report_function;
        END IF;
    END LOOP;

    IF to_regclass('public.consultation_lab_items') IS NULL
       OR NOT EXISTS (
           SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='consultations'
              AND column_name='lab_note' AND data_type='text'
       ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Migration 022 schema unexpectedly differs';
    END IF;
END
$verify$;

SELECT 'VERIFICATION SUCCESSFUL: Consultation History Lab snapshots are contained and medically isolated' AS result;
