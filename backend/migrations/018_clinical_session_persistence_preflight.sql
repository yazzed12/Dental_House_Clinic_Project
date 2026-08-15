-- READ-ONLY production preflight for clinical-session symptoms and report persistence.
-- Execute manually only after separate approval.

SELECT table_name, column_name, ordinal_position, data_type, udt_schema, udt_name,
       is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('consultations', 'clinical_reports', 'logs', 'appointments', 'patients', 'users')
ORDER BY table_name, ordinal_position;

SELECT conrelid::regclass AS table_name, conname, contype,
       pg_get_constraintdef(oid, true) AS definition
FROM pg_constraint
WHERE conrelid IN (
    'public.consultations'::regclass, 'public.clinical_reports'::regclass,
    'public.logs'::regclass
)
ORDER BY conrelid::regclass::text, conname;

SELECT n.nspname, c.relname, c.relrowsecurity, c.relforcerowsecurity
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('consultations', 'clinical_reports', 'logs');

SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('consultations', 'clinical_reports', 'logs')
ORDER BY tablename, policyname;

SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('consultations', 'clinical_reports', 'logs')
ORDER BY table_name, grantee, privilege_type;

SELECT event_object_table, trigger_name, action_timing, event_manipulation, action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND event_object_table IN ('consultations', 'clinical_reports', 'logs')
ORDER BY event_object_table, trigger_name, event_manipulation;

SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('consultations', 'clinical_reports', 'logs')
ORDER BY tablename, indexname;

SELECT count(*) AS consultation_count,
       count(*) FILTER (WHERE data IS NULL OR btrim(data) = '') AS missing_data,
       count(*) FILTER (WHERE version IS NULL OR version < 0) AS invalid_versions,
       min(version) AS minimum_version, max(version) AS maximum_version
FROM public.consultations;

SELECT id, patient_id, doctor_id, appointment_id, version,
       left(data, 1000) AS data_sample, session_note, created_at, last_updated
FROM public.consultations
ORDER BY last_updated DESC NULLS LAST, created_at DESC NULLS LAST, id DESC
LIMIT 25;

SELECT count(*) AS consultations_with_embedded_symptom_keys
FROM public.consultations
WHERE data ILIKE '%symptom%';

SELECT count(*) AS report_count,
       count(*) FILTER (WHERE patient_id IS NULL) AS null_patient_id,
       count(*) FILTER (WHERE doctor_id IS NULL) AS null_doctor_id,
       count(*) FILTER (WHERE appointment_id IS NULL) AS null_appointment_id,
       count(*) FILTER (WHERE symptoms IS NULL OR btrim(symptoms) = '') AS missing_symptoms,
       count(*) FILTER (WHERE final_medical_report IS NULL OR btrim(final_medical_report) = '') AS missing_final_report,
       count(*) FILTER (WHERE humanized_report IS NULL OR btrim(humanized_report) = '') AS missing_humanized_report
FROM public.clinical_reports;

SELECT status, count(*) AS report_count
FROM public.clinical_reports
GROUP BY status
ORDER BY status;

SELECT id, patient_id, doctor_id, appointment_id, tooth_id, tooth_status,
       symptoms, status, created_at, updated_at,
       left(ai_draft_report, 250) AS ai_draft_sample,
       left(final_medical_report, 250) AS final_report_sample,
       left(humanized_report, 250) AS humanized_report_sample
FROM public.clinical_reports
ORDER BY created_at DESC NULLS LAST, id DESC
LIMIT 25;

SELECT patient_id, appointment_id, doctor_id, tooth_id,
       count(*) AS duplicate_business_key_count,
       array_agg(id ORDER BY created_at DESC NULLS LAST, id DESC) AS report_ids
FROM public.clinical_reports
GROUP BY patient_id, appointment_id, doctor_id, tooth_id
HAVING count(*) > 1
ORDER BY duplicate_business_key_count DESC, patient_id;

SELECT count(*) AS report_patient_link_errors
FROM public.clinical_reports AS report
LEFT JOIN public.patients AS patient ON patient.id = report.patient_id
WHERE patient.id IS NULL;

SELECT count(*) AS report_doctor_link_errors
FROM public.clinical_reports AS report
LEFT JOIN public.users AS doctor ON doctor.id = report.doctor_id
WHERE report.doctor_id IS NOT NULL AND doctor.id IS NULL;

SELECT count(*) AS report_appointment_link_errors
FROM public.clinical_reports AS report
LEFT JOIN public.appointments AS appointment ON appointment.id = report.appointment_id
WHERE report.appointment_id IS NOT NULL AND appointment.id IS NULL;

SELECT message, count(*) AS log_count,
       min(created_at) AS first_seen, max(created_at) AS last_seen
FROM public.logs
WHERE lower(message) LIKE '%clinical report%'
GROUP BY message
ORDER BY last_seen DESC NULLS LAST, message;
