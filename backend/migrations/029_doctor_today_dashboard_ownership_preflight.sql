-- Migration 029 preflight: read-only Doctor dashboard appointment ownership audit.
-- Run manually before Migration 029. This file does not mutate schema or data.
DO $preflight$
BEGIN
    IF to_regprocedure('public.get_appointments()') IS NULL
       OR to_regprocedure('security.current_app_user_id()') IS NULL
       OR to_regprocedure('security.current_app_role()') IS NULL THEN
        RAISE EXCEPTION 'CONFLICT: required appointment or identity functions are missing';
    END IF;
    IF to_regclass('public.appointments') IS NULL
       OR to_regclass('public.consultations') IS NULL
       OR to_regclass('public.users') IS NULL THEN
        RAISE EXCEPTION 'CONFLICT: required dashboard relations are missing';
    END IF;
END
$preflight$;

WITH function_state AS (
    SELECT lower(pg_get_functiondef(proc.oid)) definition,proc.oid,proc.prosecdef,proc.proconfig,
           has_function_privilege('authenticated',proc.oid,'EXECUTE') authenticated_execute,
           has_function_privilege('anon',proc.oid,'EXECUTE') anon_execute,
           EXISTS(SELECT 1 FROM aclexplode(coalesce(proc.proacl,acldefault('f',proc.proowner))) entry
                   WHERE entry.grantee=0 AND entry.privilege_type='EXECUTE') public_execute
      FROM pg_proc proc WHERE proc.oid='public.get_appointments()'::regprocedure
), checks AS (
    SELECT 10 ordinal,'dashboard.current_rpc' check_name,'INFO' status,definition details FROM function_state
    UNION ALL
    SELECT 20,'dashboard.current_ownership',
           CASE WHEN definition LIKE '%appointment.doctor_id = v_actor_id%' THEN 'OK' ELSE 'CONFLICT' END,
           CASE WHEN definition LIKE '%appointment.doctor_id = v_actor_id%'
                THEN 'Doctor ownership predicate exists'
                ELSE 'Current get_appointments() returns clinic-wide rows after authentication only' END FROM function_state
    UNION ALL
    SELECT 30,'dashboard.identity_helpers',
           CASE WHEN lower(pg_get_functiondef('security.current_app_user_id()'::regprocedure)) LIKE '%supabase_user_id = auth.uid()%'
                     AND lower(pg_get_functiondef('security.current_app_user_id()'::regprocedure)) LIKE '%is_active = true%'
                     AND lower(pg_get_functiondef('security.current_app_user_id()'::regprocedure)) LIKE '%approved_at is not null%'
                     AND lower(pg_get_functiondef('security.current_app_role()'::regprocedure)) LIKE '%security.current_app_user_id()%' THEN 'OK' ELSE 'CONFLICT' END,
           'auth.uid -> active approved public.users identity and role'
    UNION ALL
    SELECT 40,'dashboard.acl',CASE WHEN prosecdef
                    AND 'search_path=pg_catalog, pg_temp'=ANY(coalesce(proconfig,ARRAY[]::text[]))
                    AND authenticated_execute AND NOT anon_execute AND NOT public_execute
                  THEN 'OK' ELSE 'CONFLICT' END,
           jsonb_build_object('authenticated',authenticated_execute,'anon',anon_execute,'public',public_execute)::text FROM function_state
    UNION ALL
    SELECT 50,'data.today_total','INFO',jsonb_build_object('count',count(*))::text
      FROM public.appointments WHERE date=current_date
    UNION ALL
    SELECT 60,'data.today_per_doctor','INFO',coalesce(jsonb_agg(jsonb_build_object(
           'doctorId',rows.doctor_id,'count',rows.row_count) ORDER BY rows.doctor_id NULLS FIRST),'[]'::jsonb)::text
      FROM (SELECT doctor_id,count(*) row_count FROM public.appointments
             WHERE date=current_date GROUP BY doctor_id) rows
    UNION ALL
    SELECT 70,'data.today_null_ownership','INFO',jsonb_build_object('count',count(*))::text
      FROM public.appointments WHERE date=current_date AND doctor_id IS NULL
    UNION ALL
    SELECT 80,'data.today_consultation_mismatches','INFO',jsonb_build_object('count',count(*))::text
      FROM public.appointments appointment JOIN public.consultations consultation
        ON consultation.appointment_id=appointment.id
     WHERE appointment.date=current_date
       AND consultation.doctor_id IS DISTINCT FROM appointment.doctor_id
    UNION ALL
    SELECT 90,'data.today_same_patient_multi_doctor','INFO',jsonb_build_object('count',count(*))::text
      FROM (SELECT patient_id FROM public.appointments WHERE date=current_date AND doctor_id IS NOT NULL
            GROUP BY patient_id HAVING count(DISTINCT doctor_id)>1) patients
), summary AS (
    SELECT 999 ordinal,'summary' check_name,
           CASE WHEN bool_or(status='CONFLICT' AND check_name<>'dashboard.current_ownership') THEN 'CONFLICT' ELSE 'CLEAN' END status,
           CASE WHEN bool_or(status='CONFLICT' AND check_name<>'dashboard.current_ownership')
                THEN 'CONFLICT: Migration 029 Doctor Today Dashboard assumptions do not match current schema'
                ELSE 'CLEAN: Migration 029 Doctor Today Dashboard assumptions match current schema' END details
      FROM checks
)
SELECT check_name,status,details FROM (SELECT * FROM checks UNION ALL SELECT * FROM summary) output ORDER BY ordinal;
