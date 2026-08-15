-- Migration 028 preflight: read-only Doctor Consultation History ownership audit.
-- Run manually before Migration 028. This file does not mutate schema or data.
DO $preflight$
BEGIN
    IF to_regprocedure('security.consultation_history_actor()') IS NULL
       OR to_regprocedure('security.list_doctor_consultation_history_base()') IS NULL
       OR to_regprocedure('public.list_doctor_consultation_history()') IS NULL THEN
        RAISE EXCEPTION 'CONFLICT: required Consultation History functions are missing';
    END IF;
    IF to_regclass('public.consultations') IS NULL
       OR to_regclass('public.clinical_reports') IS NULL
       OR to_regclass('public.consultation_lab_items') IS NULL THEN
        RAISE EXCEPTION 'CONFLICT: required Consultation History relations are missing';
    END IF;
END
$preflight$;

WITH definitions AS (
    SELECT lower(pg_get_functiondef('security.consultation_history_actor()'::regprocedure)) AS actor,
           lower(pg_get_functiondef('security.list_doctor_consultation_history_base()'::regprocedure)) AS base,
           lower(pg_get_functiondef('public.list_doctor_consultation_history()'::regprocedure)) AS wrapper
), acl AS (
    SELECT proc.oid,proc.prosecdef,proc.proconfig,
           has_function_privilege('authenticated',proc.oid,'EXECUTE') AS authenticated_execute,
           has_function_privilege('anon',proc.oid,'EXECUTE') AS anon_execute,
           EXISTS(SELECT 1 FROM aclexplode(coalesce(proc.proacl,acldefault('f',proc.proowner))) entry
                   WHERE entry.grantee=0 AND entry.privilege_type='EXECUTE') AS public_execute
      FROM pg_proc proc WHERE proc.oid='public.list_doctor_consultation_history()'::regprocedure
), checks AS (
    SELECT 10 ordinal,'identity.actor' check_name,
           CASE WHEN actor LIKE '%supabase_user_id = auth.uid()%'
                     AND actor LIKE '%is_active = true%'
                     AND actor LIKE '%approved_at is not null%'
                     AND actor LIKE '%role in (''doctor'', ''admin'')%' THEN 'OK' ELSE 'CONFLICT' END status,
           actor details FROM definitions
    UNION ALL
    SELECT 20,'history.current_base','INFO',base FROM definitions
    UNION ALL
    SELECT 30,'history.current_leak_condition',
           CASE WHEN base LIKE '%consultation.doctor_id is null and exists%'
                  OR base LIKE '%report.doctor_id is null and exists%' THEN 'CONFLICT' ELSE 'OK' END,
           'NULL-owned rows currently inherit access from same-patient appointment/consultation evidence' FROM definitions
    UNION ALL
    SELECT 40,'history.wrapper_023_compatibility',
           CASE WHEN wrapper LIKE '%security.list_doctor_consultation_history_base()%'
                     AND wrapper LIKE '%''clinicalfindings''%'
                     AND wrapper LIKE '%''reportsnapshot''%'
                     AND wrapper LIKE '%''snapshotversion''%'
                     AND wrapper LIKE '%''reviewedat''%'
                     AND wrapper LIKE '%''finalizedat''%'
                     AND wrapper LIKE '%''labnote''%'
                     AND wrapper LIKE '%''labitems''%'
                     AND wrapper LIKE '%order by item.ordinality%' THEN 'OK' ELSE 'CONFLICT' END,
           wrapper FROM definitions
    UNION ALL
    SELECT 50,'history.acl',CASE WHEN prosecdef
                    AND 'search_path=pg_catalog, pg_temp'=ANY(coalesce(proconfig,ARRAY[]::text[]))
                    AND authenticated_execute AND NOT anon_execute AND NOT public_execute
                  THEN 'OK' ELSE 'CONFLICT' END,
           jsonb_build_object('authenticated',authenticated_execute,'anon',anon_execute,'public',public_execute)::text FROM acl
    UNION ALL
    SELECT 60,'data.multi_doctor_patients','INFO',jsonb_build_object('count',count(*))::text
      FROM (SELECT patient_id FROM public.consultations WHERE doctor_id IS NOT NULL
            GROUP BY patient_id HAVING count(DISTINCT doctor_id)>1) patients
    UNION ALL
    SELECT 70,'data.null_owned_leak_candidates','INFO',jsonb_build_object(
           'consultations',(SELECT count(*) FROM public.consultations WHERE doctor_id IS NULL),
           'reports',(SELECT count(*) FROM public.clinical_reports WHERE doctor_id IS NULL),
           'samePatientDoctorPairs',(SELECT count(*) FROM (
               SELECT DISTINCT unowned.patient_id,owned.doctor_id
                 FROM public.consultations unowned JOIN public.consultations owned
                   ON owned.patient_id=unowned.patient_id AND owned.doctor_id IS NOT NULL
                WHERE unowned.doctor_id IS NULL
               UNION
               SELECT DISTINCT unowned.patient_id,appointment.doctor_id
                 FROM public.consultations unowned JOIN public.appointments appointment
                   ON appointment.patient_id=unowned.patient_id AND appointment.doctor_id IS NOT NULL
                WHERE unowned.doctor_id IS NULL) pairs))::text
), summary AS (
    SELECT 999 ordinal,'summary' check_name,
           CASE WHEN bool_or(status='CONFLICT' AND check_name<>'history.current_leak_condition') THEN 'CONFLICT' ELSE 'CLEAN' END status,
           CASE WHEN bool_or(status='CONFLICT' AND check_name<>'history.current_leak_condition')
                THEN 'CONFLICT: Migration 028 Doctor history ownership assumptions do not match current schema'
                ELSE 'CLEAN: Migration 028 Doctor history ownership assumptions match current schema' END details
      FROM checks
)
SELECT check_name,status,details FROM (SELECT * FROM checks UNION ALL SELECT * FROM summary) output ORDER BY ordinal;
