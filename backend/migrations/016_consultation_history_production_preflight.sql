-- READ-ONLY production inventory for the Consultation History slice.
-- Execute manually only after separate approval. This file performs no writes.

SELECT table_name, column_name, ordinal_position, data_type, udt_schema, udt_name,
       is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
      'consultations', 'appointments', 'patients', 'users',
      'clinical_reports', 'consultation_procedures'
  )
ORDER BY table_name, ordinal_position;

SELECT conrelid::regclass AS table_name, conname, contype,
       pg_get_constraintdef(oid, true) AS definition
FROM pg_constraint
WHERE conrelid IN (
    'public.consultations'::regclass,
    'public.appointments'::regclass,
    'public.patients'::regclass,
    'public.users'::regclass,
    'public.clinical_reports'::regclass,
    'public.consultation_procedures'::regclass
)
ORDER BY conrelid::regclass::text, conname;

SELECT n.nspname AS schema_name, c.relname AS table_name,
       c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS rls_forced
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
      'consultations', 'appointments', 'patients', 'users',
      'clinical_reports', 'consultation_procedures'
  )
ORDER BY c.relname;

SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
      'consultations', 'appointments', 'patients', 'users',
      'clinical_reports', 'consultation_procedures'
  )
ORDER BY tablename, policyname;

SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN (
      'consultations', 'appointments', 'patients', 'users',
      'clinical_reports', 'consultation_procedures'
  )
ORDER BY table_name, grantee, privilege_type;

SELECT event_object_table AS table_name, trigger_name, action_timing,
       event_manipulation, action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND event_object_table IN (
      'consultations', 'appointments', 'patients', 'users',
      'clinical_reports', 'consultation_procedures'
  )
ORDER BY event_object_table, trigger_name, event_manipulation;

SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('consultations', 'clinical_reports', 'appointments')
ORDER BY tablename, indexname;

SELECT
    count(*) AS consultation_count,
    count(*) FILTER (WHERE patient_id IS NULL) AS null_patient_id,
    count(*) FILTER (WHERE doctor_id IS NULL) AS null_doctor_id,
    count(*) FILTER (WHERE appointment_id IS NULL) AS null_appointment_id,
    count(*) FILTER (WHERE created_at IS NULL) AS null_created_at,
    count(*) FILTER (WHERE last_updated IS NULL) AS null_last_updated,
    count(*) FILTER (WHERE version IS NULL OR version < 0) AS invalid_version
FROM public.consultations;

SELECT appointment_id, count(*) AS duplicate_consultation_count,
       array_agg(id ORDER BY last_updated DESC NULLS LAST,
                 created_at DESC NULLS LAST, id DESC) AS consultation_ids
FROM public.consultations
WHERE appointment_id IS NOT NULL
GROUP BY appointment_id
HAVING count(*) > 1
ORDER BY duplicate_consultation_count DESC, appointment_id;

SELECT count(*) AS broken_patient_references
FROM public.consultations AS consultation
LEFT JOIN public.patients AS patient ON patient.id = consultation.patient_id
WHERE consultation.patient_id IS NULL OR patient.id IS NULL;

SELECT count(*) AS broken_doctor_references
FROM public.consultations AS consultation
LEFT JOIN public.users AS doctor ON doctor.id = consultation.doctor_id
WHERE consultation.doctor_id IS NOT NULL AND doctor.id IS NULL;

SELECT count(*) AS broken_appointment_references
FROM public.consultations AS consultation
LEFT JOIN public.appointments AS appointment ON appointment.id = consultation.appointment_id
WHERE consultation.appointment_id IS NOT NULL AND appointment.id IS NULL;

SELECT count(*) AS consultation_appointment_identity_mismatches
FROM public.consultations AS consultation
JOIN public.appointments AS appointment ON appointment.id = consultation.appointment_id
WHERE consultation.patient_id IS DISTINCT FROM appointment.patient_id
   OR (consultation.doctor_id IS NOT NULL
       AND appointment.doctor_id IS NOT NULL
       AND consultation.doctor_id IS DISTINCT FROM appointment.doctor_id);

SELECT
    count(*) AS report_count,
    count(*) FILTER (WHERE patient_id IS NULL) AS null_patient_id,
    count(*) FILTER (WHERE doctor_id IS NULL) AS null_doctor_id,
    count(*) FILTER (WHERE appointment_id IS NULL) AS null_appointment_id,
    count(*) FILTER (WHERE created_at IS NULL) AS null_created_at,
    count(*) FILTER (WHERE symptoms IS NULL OR btrim(symptoms) = '') AS missing_symptoms
FROM public.clinical_reports;

SELECT count(*) AS report_broken_patient_references
FROM public.clinical_reports AS report
LEFT JOIN public.patients AS patient ON patient.id = report.patient_id
WHERE patient.id IS NULL;

SELECT count(*) AS report_broken_doctor_references
FROM public.clinical_reports AS report
LEFT JOIN public.users AS doctor ON doctor.id = report.doctor_id
WHERE report.doctor_id IS NOT NULL AND doctor.id IS NULL;

SELECT count(*) AS report_broken_appointment_references
FROM public.clinical_reports AS report
LEFT JOIN public.appointments AS appointment ON appointment.id = report.appointment_id
WHERE report.appointment_id IS NOT NULL AND appointment.id IS NULL;

SELECT count(*) AS report_appointment_identity_mismatches
FROM public.clinical_reports AS report
JOIN public.appointments AS appointment ON appointment.id = report.appointment_id
WHERE report.patient_id IS DISTINCT FROM appointment.patient_id
   OR (report.doctor_id IS NOT NULL
       AND appointment.doctor_id IS NOT NULL
       AND report.doctor_id IS DISTINCT FROM appointment.doctor_id);

SELECT report.id AS report_id, report.patient_id, report.doctor_id, report.appointment_id,
       count(consultation.id) AS exact_consultation_matches
FROM public.clinical_reports AS report
LEFT JOIN public.consultations AS consultation
  ON consultation.patient_id = report.patient_id
 AND consultation.appointment_id = report.appointment_id
WHERE report.appointment_id IS NOT NULL
GROUP BY report.id, report.patient_id, report.doctor_id, report.appointment_id
HAVING count(consultation.id) <> 1
ORDER BY exact_consultation_matches DESC, report.id;

SELECT count(*) AS orphaned_consultation_procedures
FROM public.consultation_procedures AS selection
LEFT JOIN public.consultations AS consultation ON consultation.id = selection.consultation_id
WHERE consultation.id IS NULL;
