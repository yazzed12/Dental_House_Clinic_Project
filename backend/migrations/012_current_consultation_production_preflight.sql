-- READ-ONLY production inventory for manual execution before approving 012.
-- This file must not be run by the implementation task.

SELECT table_name, column_name, ordinal_position, data_type, udt_schema, udt_name,
       is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('consultations', 'patient_dental_state', 'appointments', 'patients', 'logs', 'users')
ORDER BY table_name, ordinal_position;

SELECT conrelid::regclass AS table_name, conname, contype,
       pg_get_constraintdef(oid, true) AS definition
FROM pg_constraint
WHERE conrelid IN (
    'public.consultations'::regclass,
    'public.patient_dental_state'::regclass,
    'public.appointments'::regclass,
    'public.logs'::regclass
)
ORDER BY conrelid::regclass::text, conname;

SELECT n.nspname AS schema_name, c.relname AS table_name,
       c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('consultations', 'patient_dental_state', 'appointments', 'patients', 'logs');

SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('consultations', 'patient_dental_state', 'appointments', 'patients', 'logs')
ORDER BY tablename, policyname;

SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('consultations', 'patient_dental_state', 'appointments', 'patients', 'logs')
ORDER BY table_name, grantee, privilege_type;

SELECT event_object_table AS table_name, trigger_name, action_timing,
       event_manipulation, action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND event_object_table IN ('consultations', 'patient_dental_state', 'appointments', 'logs')
ORDER BY event_object_table, trigger_name, event_manipulation;

SELECT t.typname AS enum_name, e.enumsortorder, e.enumlabel
FROM pg_type t
JOIN pg_namespace n ON n.oid = t.typnamespace
JOIN pg_enum e ON e.enumtypid = t.oid
WHERE n.nspname = 'public'
  AND t.typname IN ('appointment_status', 'appointment_type')
ORDER BY t.typname, e.enumsortorder;

SELECT
    count(*) FILTER (WHERE patient_id IS NULL) AS null_patient_id,
    count(*) FILTER (WHERE doctor_id IS NULL) AS null_doctor_id,
    count(*) FILTER (WHERE appointment_id IS NULL) AS null_appointment_id,
    count(*) FILTER (WHERE version IS NULL) AS null_version,
    min(version) AS min_version,
    max(version) AS max_version
FROM public.consultations;

SELECT count(*) AS invalid_consultation_appointment_links
FROM public.consultations c
JOIN public.appointments a ON a.id = c.appointment_id
WHERE c.patient_id IS DISTINCT FROM a.patient_id
   OR (c.doctor_id IS NOT NULL AND a.doctor_id IS NOT NULL AND c.doctor_id IS DISTINCT FROM a.doctor_id);

SELECT appointment_id, count(*) AS consultation_count
FROM public.consultations
WHERE appointment_id IS NOT NULL
GROUP BY appointment_id
HAVING count(*) > 1
ORDER BY consultation_count DESC, appointment_id;

SELECT
    count(*) AS dental_state_rows,
    count(*) FILTER (WHERE version IS NULL OR version < 1) AS invalid_versions,
    min(version) AS min_version,
    max(version) AS max_version
FROM public.patient_dental_state;

SELECT status::text, count(*)
FROM public.appointments
GROUP BY status::text
ORDER BY status::text;

SELECT count(*) AS today_eligible_legacy_null_doctor_rows
FROM public.appointments
WHERE (date = CURRENT_DATE OR appointment_date = CURRENT_DATE)
  AND status::text IN ('pending', 'confirmed')
  AND doctor_id IS NULL;
