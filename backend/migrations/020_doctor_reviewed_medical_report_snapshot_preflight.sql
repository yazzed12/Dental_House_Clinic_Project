-- Migration 020 production preflight. READ ONLY. One consolidated result set.
WITH checks(check_name, status, details) AS (
    SELECT 'clinical_reports.columns', 'INFO',
           coalesce(string_agg(column_name || ' ' || data_type ||
                    CASE WHEN is_nullable = 'YES' THEN ' NULL' ELSE ' NOT NULL' END,
                    ', ' ORDER BY ordinal_position), 'table missing')
      FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'clinical_reports'

    UNION ALL
    SELECT 'snapshot_columns.existing',
           CASE WHEN count(*) = 0 THEN 'OK' ELSE 'REVIEW' END,
           CASE WHEN count(*) = 0 THEN 'No Migration 020 columns exist.'
                ELSE string_agg(column_name || ' ' || data_type, ', ' ORDER BY column_name) END
      FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'clinical_reports'
       AND column_name IN ('report_snapshot','snapshot_version','reviewed_by','reviewed_at','finalized_at')

    UNION ALL
    SELECT 'report_rpc.signatures', 'INFO',
           coalesce(string_agg(namespace.nspname || '.' || procedure.proname ||
                    '(' || pg_get_function_identity_arguments(procedure.oid) || ')',
                    ', ' ORDER BY procedure.proname, procedure.oid), 'none')
      FROM pg_proc AS procedure
      JOIN pg_namespace AS namespace ON namespace.oid = procedure.pronamespace
     WHERE namespace.nspname IN ('public','security')
       AND procedure.proname IN (
           'save_clinical_report','update_clinical_report','get_patient_clinical_reports',
           'finalize_clinical_report'
       )

    UNION ALL
    SELECT 'report_rpc.privileges', 'INFO',
           coalesce(string_agg(
               procedure.proname || '(' || pg_get_function_identity_arguments(procedure.oid) || ')' ||
               ': authenticated=' || has_function_privilege('authenticated', procedure.oid, 'EXECUTE') ||
               ', anon=' || has_function_privilege('anon', procedure.oid, 'EXECUTE') ||
               ', public=' || has_function_privilege('public', procedure.oid, 'EXECUTE'),
               '; ' ORDER BY procedure.proname, procedure.oid), 'none')
      FROM pg_proc AS procedure
      JOIN pg_namespace AS namespace ON namespace.oid = procedure.pronamespace
     WHERE namespace.nspname = 'public'
       AND procedure.proname IN (
           'save_clinical_report','update_clinical_report','get_patient_clinical_reports',
           'finalize_clinical_report'
       )

    UNION ALL
    SELECT 'report_counts.total', 'INFO', count(*)::text FROM public.clinical_reports
    UNION ALL
    SELECT 'report_counts.consultation_id_null', 'INFO', count(*)::text
      FROM public.clinical_reports WHERE consultation_id IS NULL
    UNION ALL
    SELECT 'report_counts.consultation_id_present', 'INFO', count(*)::text
      FROM public.clinical_reports WHERE consultation_id IS NOT NULL

    UNION ALL
    SELECT 'report_linkage.broken_consultation',
           CASE WHEN count(*) = 0 THEN 'OK' ELSE 'BLOCK' END, count(*)::text
      FROM public.clinical_reports AS report
      LEFT JOIN public.consultations AS consultation ON consultation.id = report.consultation_id
     WHERE report.consultation_id IS NOT NULL AND consultation.id IS NULL

    UNION ALL
    SELECT 'report_linkage.identity_mismatch',
           CASE WHEN count(*) = 0 THEN 'OK' ELSE 'BLOCK' END, count(*)::text
      FROM public.clinical_reports AS report
      JOIN public.consultations AS consultation ON consultation.id = report.consultation_id
     WHERE report.patient_id IS DISTINCT FROM consultation.patient_id
        OR report.doctor_id IS DISTINCT FROM consultation.doctor_id
        OR report.appointment_id IS DISTINCT FROM consultation.appointment_id

    UNION ALL
    SELECT 'unexpected_finalized_columns',
           CASE WHEN count(*) = 0 THEN 'OK' ELSE 'REVIEW' END,
           CASE WHEN count(*) = 0 THEN 'Migration 020 finalized columns are absent.'
                ELSE 'Existing finalized_at column detected; inspect before applying.' END
      FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'clinical_reports'
       AND column_name = 'finalized_at'

    UNION ALL
    SELECT 'report_counts.already_finalized',
           CASE WHEN count(*) = 0 THEN 'OK' ELSE 'BLOCK' END,
           count(*)::text
      FROM public.clinical_reports AS report
     WHERE nullif(to_jsonb(report) ->> 'finalized_at', '') IS NOT NULL

    UNION ALL
    SELECT 'report_counts.existing_snapshots',
           CASE WHEN count(*) = 0 THEN 'OK' ELSE 'BLOCK' END,
           count(*)::text
      FROM public.clinical_reports AS report
     WHERE nullif(to_jsonb(report) ->> 'report_snapshot', '') IS NOT NULL

    UNION ALL
    SELECT 'dependency.consultation_findings',
           CASE WHEN EXISTS (
               SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='consultations'
                  AND column_name='clinical_findings_snapshot' AND data_type='jsonb'
           ) THEN 'OK' ELSE 'BLOCK' END,
           'public.consultations.clinical_findings_snapshot jsonb'

    UNION ALL
    SELECT 'dependency.findings_validator',
           CASE WHEN to_regprocedure('security.clinical_findings_snapshot_valid(jsonb)') IS NOT NULL
                THEN 'OK' ELSE 'BLOCK' END,
           coalesce(to_regprocedure('security.clinical_findings_snapshot_valid(jsonb)')::text, 'missing')

    UNION ALL
    SELECT 'dependency.financial_effective_items',
           CASE WHEN to_regprocedure('security.financial_effective_items(uuid)') IS NOT NULL
                THEN 'OK' ELSE 'BLOCK' END,
           coalesce(to_regprocedure('security.financial_effective_items(uuid)')::text, 'missing')

    UNION ALL
    SELECT 'dependency.procedure_tables',
           CASE WHEN to_regclass('public.consultation_procedures') IS NOT NULL
                  AND to_regclass('public.clinic_procedures') IS NOT NULL
                THEN 'OK' ELSE 'BLOCK' END,
           'consultation_procedures=' || coalesce(to_regclass('public.consultation_procedures')::text,'missing') ||
           ', clinic_procedures=' || coalesce(to_regclass('public.clinic_procedures')::text,'missing')

    UNION ALL
    SELECT 'dependency.clinic_settings',
           CASE WHEN to_regclass('public.clinic_settings') IS NOT NULL THEN 'OK' ELSE 'BLOCK' END,
           coalesce(to_regclass('public.clinic_settings')::text, 'missing')

    UNION ALL
    SELECT 'dependency.report_actor',
           CASE WHEN to_regprocedure('security.clinical_report_actor()') IS NOT NULL
                THEN 'OK' ELSE 'BLOCK' END,
           coalesce(to_regprocedure('security.clinical_report_actor()')::text, 'missing')

    UNION ALL
    SELECT 'update_clinical_report.definition', 'INFO',
           coalesce(pg_get_functiondef(to_regprocedure('public.update_clinical_report(uuid,jsonb)')), 'missing')

    UNION ALL
    SELECT 'get_patient_clinical_reports.definition', 'INFO',
           coalesce(pg_get_functiondef(to_regprocedure('public.get_patient_clinical_reports(uuid)')), 'missing')

    UNION ALL
    SELECT 'schema_conflicts',
           CASE WHEN EXISTS (
               SELECT 1 FROM pg_proc AS procedure
               JOIN pg_namespace AS namespace ON namespace.oid=procedure.pronamespace
               WHERE namespace.nspname IN ('public','security')
                 AND procedure.proname IN (
                   'medical_report_snapshot_valid','prevent_finalized_report_mutation',
                   'finalize_clinical_report','update_clinical_report_legacy',
                   'get_patient_clinical_reports_legacy'
                 )
           ) THEN 'REVIEW' ELSE 'OK' END,
           'Existing Migration 020-named functions must be reviewed before application.'
)
SELECT check_name, status, details FROM checks ORDER BY check_name;
