-- Migration 021 preflight: read-only production assumption checks.
DO $preflight$
BEGIN
    IF to_regprocedure('public.list_doctor_consultation_history()') IS NULL
       OR to_regprocedure('public.get_patient_clinical_reports(uuid)') IS NULL
       OR to_regprocedure('security.list_doctor_consultation_history_base()') IS NULL THEN
        RAISE EXCEPTION 'PREFLIGHT BLOCKED: required history functions are missing';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM (VALUES
              ('report_snapshot','jsonb'), ('snapshot_version','integer'),
              ('reviewed_at','timestamp with time zone'),
              ('finalized_at','timestamp with time zone')
          ) AS expected(column_name, data_type)
         WHERE NOT EXISTS (
             SELECT 1 FROM information_schema.columns AS column_record
              WHERE column_record.table_schema='public'
                AND column_record.table_name='clinical_reports'
                AND column_record.column_name=expected.column_name
                AND column_record.data_type=expected.data_type
         )
    ) THEN
        RAISE EXCEPTION 'PREFLIGHT BLOCKED: Migration 020 report metadata columns are incomplete';
    END IF;
END
$preflight$;

SELECT 'function.signatures' AS check_name, 'INFO' AS status,
       jsonb_build_object(
           'history', to_regprocedure('public.list_doctor_consultation_history()'),
           'patientReports', to_regprocedure('public.get_patient_clinical_reports(uuid)'),
           'historyBase', to_regprocedure('security.list_doctor_consultation_history_base()')
       )::text AS details
UNION ALL
SELECT 'function.history_definition', 'INFO',
       pg_get_functiondef('public.list_doctor_consultation_history()'::regprocedure)
UNION ALL
SELECT 'function.patient_reports_definition', 'INFO',
       pg_get_functiondef('public.get_patient_clinical_reports(uuid)'::regprocedure)
UNION ALL
SELECT 'function.history_posture', 'INFO',
       jsonb_build_object(
           'owner', pg_get_userbyid(proc.proowner),
           'securityDefiner', proc.prosecdef,
           'config', proc.proconfig,
           'authenticatedExecute', has_function_privilege(
               'authenticated', proc.oid, 'EXECUTE'),
           'anonExecute', has_function_privilege('anon', proc.oid, 'EXECUTE'),
           'publicExecute', EXISTS (
               SELECT 1
                 FROM aclexplode(coalesce(proc.proacl, acldefault('f', proc.proowner))) AS acl_entry
                WHERE acl_entry.grantee=0 AND acl_entry.privilege_type='EXECUTE'
           )
       )::text
  FROM pg_proc AS proc
 WHERE proc.oid='public.list_doctor_consultation_history()'::regprocedure
UNION ALL
SELECT 'schema.report_metadata_columns',
       CASE WHEN count(*)=4 THEN 'OK' ELSE 'BLOCK' END,
       jsonb_agg(jsonb_build_object('column', column_name, 'type', data_type)
                 ORDER BY column_name)::text
  FROM information_schema.columns
 WHERE table_schema='public' AND table_name='clinical_reports'
   AND column_name IN ('report_snapshot','snapshot_version','reviewed_at','finalized_at')
UNION ALL
SELECT 'data.report_only_rows', 'INFO',
       jsonb_build_object(
           'reportOnlyRows', count(*),
           'doctorOwnedWithoutOwnedAppointmentOrConsultation', count(*) FILTER (
               WHERE report.doctor_id IS NOT NULL
                 AND NOT EXISTS (
                     SELECT 1 FROM public.appointments AS appointment
                      WHERE appointment.patient_id=report.patient_id
                        AND appointment.doctor_id=report.doctor_id
                 )
                 AND NOT EXISTS (
                     SELECT 1 FROM public.consultations AS consultation
                      WHERE consultation.patient_id=report.patient_id
                        AND consultation.doctor_id=report.doctor_id
                 )
           )
       )::text
  FROM public.clinical_reports AS report
 WHERE report.consultation_id IS NULL
UNION ALL
SELECT 'data.finalized_snapshots', 'INFO',
       jsonb_build_object(
           'finalizedReports', count(*) FILTER (WHERE finalized_at IS NOT NULL),
           'snapshotsPresent', count(*) FILTER (WHERE report_snapshot IS NOT NULL),
           'snapshotsMissingNarrative', count(*) FILTER (
               WHERE report_snapshot IS NOT NULL
                 AND nullif(report_snapshot ->> 'finalNarrative', '') IS NULL
           )
       )::text
  FROM public.clinical_reports;
