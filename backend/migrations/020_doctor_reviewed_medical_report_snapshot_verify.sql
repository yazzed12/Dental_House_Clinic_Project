-- Migration 020 verification. Run only after the migration has been approved/applied.
DO $verify$
DECLARE
    v_finalize text;
    v_update text;
    v_read text;
BEGIN
    IF EXISTS (
        SELECT 1
          FROM (VALUES
            ('report_snapshot','jsonb','YES'),
            ('snapshot_version','integer','YES'),
            ('reviewed_by','uuid','YES'),
            ('reviewed_at','timestamp with time zone','YES'),
            ('finalized_at','timestamp with time zone','YES')
          ) AS expected(column_name, data_type, is_nullable)
          LEFT JOIN information_schema.columns AS actual
            ON actual.table_schema='public' AND actual.table_name='clinical_reports'
           AND actual.column_name=expected.column_name
         WHERE actual.column_name IS NULL OR actual.data_type<>expected.data_type
            OR actual.is_nullable<>expected.is_nullable
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Migration 020 columns/types/nullability incorrect';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint AS constraint_record
         WHERE constraint_record.conrelid='public.clinical_reports'::regclass
           AND constraint_record.contype='f'
           AND constraint_record.confrelid='public.users'::regclass
           AND pg_get_constraintdef(constraint_record.oid) LIKE 'FOREIGN KEY (reviewed_by)%'
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: reviewed_by users FK missing';
    END IF;

    IF to_regprocedure('security.medical_report_snapshot_valid(jsonb)') IS NULL
       OR NOT EXISTS (
           SELECT 1 FROM pg_constraint
            WHERE conrelid='public.clinical_reports'::regclass
              AND conname='clinical_reports_snapshot_valid_ck'
       )
       OR NOT EXISTS (
           SELECT 1 FROM pg_constraint
            WHERE conrelid='public.clinical_reports'::regclass
              AND conname='clinical_reports_snapshot_state_ck'
       ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: snapshot validation/state constraints missing';
    END IF;

    IF to_regprocedure('public.finalize_clinical_report(uuid,jsonb,text,text)') IS NULL THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: finalization RPC missing';
    END IF;
    SELECT lower(pg_get_functiondef(
        'public.finalize_clinical_report(uuid,jsonb,text,text)'::regprocedure
    )) INTO v_finalize;
    IF v_finalize NOT LIKE '%security definer%'
       OR v_finalize NOT LIKE '%set search_path to ''pg_catalog'', ''pg_temp''%'
       OR v_finalize NOT LIKE '%clinical_findings_snapshot%'
       OR v_finalize NOT LIKE '%security.financial_effective_items%'
       OR v_finalize NOT LIKE '%report_snapshot = v_snapshot%'
       OR v_finalize NOT LIKE '%snapshot_version = 1%'
       OR v_finalize NOT LIKE '%reviewed_by = v_actor_id%'
       OR v_finalize NOT LIKE '%finalized_at = v_now%'
       OR v_finalize NOT LIKE '%finalized_report_immutable%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: finalization authority/immutability contract missing';
    END IF;

    IF EXISTS (
           SELECT 1
             FROM pg_proc AS proc
             CROSS JOIN LATERAL
               aclexplode(coalesce(proc.proacl, acldefault('f', proc.proowner))) AS acl_entry
            WHERE proc.oid = 'public.finalize_clinical_report(uuid,jsonb,text,text)'::regprocedure::oid
              AND acl_entry.grantee = 0
              AND acl_entry.privilege_type = 'EXECUTE'
       )
       OR has_function_privilege('anon', 'public.finalize_clinical_report(uuid,jsonb,text,text)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.finalize_clinical_report(uuid,jsonb,text,text)', 'EXECUTE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: finalization RPC privileges incorrect';
    END IF;
    IF EXISTS (
           SELECT 1
             FROM pg_proc AS proc
             CROSS JOIN LATERAL
               aclexplode(coalesce(proc.proacl, acldefault('f', proc.proowner))) AS acl_entry
            WHERE proc.oid = 'security.update_clinical_report_legacy(uuid,jsonb)'::regprocedure::oid
              AND acl_entry.grantee = 0
              AND acl_entry.privilege_type = 'EXECUTE'
       )
       OR has_function_privilege('anon', 'security.update_clinical_report_legacy(uuid,jsonb)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'security.update_clinical_report_legacy(uuid,jsonb)', 'EXECUTE')
       OR EXISTS (
           SELECT 1
             FROM pg_proc AS proc
             CROSS JOIN LATERAL
               aclexplode(coalesce(proc.proacl, acldefault('f', proc.proowner))) AS acl_entry
            WHERE proc.oid = 'security.get_patient_clinical_reports_legacy(uuid)'::regprocedure::oid
              AND acl_entry.grantee = 0
              AND acl_entry.privilege_type = 'EXECUTE'
       )
       OR has_function_privilege('anon', 'security.get_patient_clinical_reports_legacy(uuid)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'security.get_patient_clinical_reports_legacy(uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: private legacy implementations browser-executable';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
         WHERE tgrelid='public.clinical_reports'::regclass
           AND tgname='clinical_reports_finalized_immutability' AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: finalized snapshot immutability trigger missing';
    END IF;

    SELECT lower(pg_get_functiondef(
        'public.update_clinical_report(uuid,jsonb)'::regprocedure
    )) INTO v_update;
    IF v_update NOT LIKE '%v_report.report_snapshot is not null%'
       OR v_update NOT LIKE '%v_report.finalized_at is not null%'
       OR v_update NOT LIKE '%security.clinical_report_actor()%'
       OR v_update NOT LIKE '%finalized_report_immutable%'
       OR v_update NOT LIKE '%security.update_clinical_report_legacy%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: legacy update finalized-report guard missing';
    END IF;

    SELECT lower(pg_get_functiondef(
        'public.get_patient_clinical_reports(uuid)'::regprocedure
    )) INTO v_read;
    IF v_read NOT LIKE '%''reportsnapshot''%report.report_snapshot%'
       OR v_read NOT LIKE '%''snapshotversion''%report.snapshot_version%'
       OR v_read NOT LIKE '%''reviewedby''%report.reviewed_by%'
       OR v_read NOT LIKE '%''reviewedat''%report.reviewed_at%'
       OR v_read NOT LIKE '%''finalizedat''%report.finalized_at%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: report read snapshot metadata projection missing';
    END IF;

    IF EXISTS (
           SELECT 1
             FROM pg_proc AS proc
             CROSS JOIN LATERAL
               aclexplode(coalesce(proc.proacl, acldefault('f', proc.proowner))) AS acl_entry
            WHERE proc.oid = 'public.update_clinical_report(uuid,jsonb)'::regprocedure::oid
              AND acl_entry.grantee = 0
              AND acl_entry.privilege_type = 'EXECUTE'
       )
       OR has_function_privilege('anon', 'public.update_clinical_report(uuid,jsonb)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.update_clinical_report(uuid,jsonb)', 'EXECUTE')
       OR EXISTS (
           SELECT 1
             FROM pg_proc AS proc
             CROSS JOIN LATERAL
               aclexplode(coalesce(proc.proacl, acldefault('f', proc.proowner))) AS acl_entry
            WHERE proc.oid = 'public.get_patient_clinical_reports(uuid)'::regprocedure::oid
              AND acl_entry.grantee = 0
              AND acl_entry.privilege_type = 'EXECUTE'
       )
       OR has_function_privilege('anon', 'public.get_patient_clinical_reports(uuid)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.get_patient_clinical_reports(uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: replaced report RPC privileges incorrect';
    END IF;

    -- Immediately after application every pre-existing report must retain NULL
    -- snapshot metadata. Structured reports are created only by explicit finalization.
    IF EXISTS (
        SELECT 1 FROM public.clinical_reports
         WHERE report_snapshot IS NOT NULL OR snapshot_version IS NOT NULL
            OR reviewed_by IS NOT NULL OR reviewed_at IS NOT NULL OR finalized_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: legacy report rows were unexpectedly backfilled';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid='public.clinical_reports'::regclass AND contype='u'
    ) OR EXISTS (
        SELECT 1 FROM pg_index AS index_record
         WHERE index_record.indrelid='public.clinical_reports'::regclass
           AND index_record.indisunique AND NOT index_record.indisprimary
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: unexpected report uniqueness exists';
    END IF;

    IF to_regclass('public.icd10_catalog') IS NOT NULL
       OR to_regclass('public.icd_catalog') IS NOT NULL THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Migration 020 must not introduce an ICD catalog';
    END IF;
END
$verify$;
