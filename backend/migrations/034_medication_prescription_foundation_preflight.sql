-- Migration 034 preflight: Medication + Prescription foundation.
-- READ ONLY. Run this first and inspect every CONFLICT before running 034.

WITH required_relations(name) AS (
    VALUES ('users'), ('patients'), ('appointments'), ('consultations'),
           ('clinical_reports'), ('clinic_settings'), ('logs'), ('consultation_lab_items')
), required_columns(table_name, column_name, expected_type) AS (
    VALUES
      ('users','id','uuid'), ('users','supabase_user_id','uuid'),
      ('users','role',NULL), ('users','is_active','boolean'),
      ('users','approved_at','timestamp with time zone'),
      ('patients','id','uuid'),
      ('appointments','id','uuid'), ('appointments','patient_id','uuid'),
      ('appointments','doctor_id','uuid'),
      ('consultations','id','uuid'), ('consultations','patient_id','uuid'),
      ('consultations','doctor_id','uuid'), ('consultations','appointment_id','uuid'),
      ('consultations','lab_note','text')
), required_functions(signature) AS (
    VALUES
      ('security.current_app_user_id()'),
      ('security.current_app_role()'),
      ('security.consultation_history_actor()'),
      ('security.get_patient_consultation_history_base(uuid)'),
      ('security.list_doctor_consultation_history_base()'),
      ('public.get_patient_consultation_history(uuid)'),
      ('public.list_doctor_consultation_history()'),
      ('public.finish_appointment_by_patient(uuid,uuid)'),
      ('public.format_clinic_data()')
), target_relations(name) AS (
    VALUES ('dental_medications'), ('medication_clinical_presets'),
           ('doctor_medication_presets'), ('medication_import_batches'),
           ('medication_import_rejections'), ('prescriptions'), ('prescription_items')
), target_functions(signature) AS (
    VALUES
      ('security.medication_prescription_actor()'),
      ('security.prescription_projection(uuid)'),
      ('security.prevent_approved_prescription_mutation()'),
      ('security.prevent_approved_prescription_item_mutation()'),
      ('public.search_dental_medications(text,integer)'),
      ('public.create_custom_medication(text,text,text,text,text,text,text)'),
      ('public.get_effective_medication_preset(uuid)'),
      ('public.upsert_doctor_medication_preset(uuid,text,text,text,text,text)'),
      ('public.delete_doctor_medication_preset(uuid)'),
      ('public.get_consultation_prescription(uuid)'),
      ('public.save_prescription_draft(uuid,integer,jsonb)'),
      ('public.approve_prescription(uuid,integer)')
), base_diagnostics AS (
    SELECT 10 AS ordinal, 'prerequisite.relation.' || required.name AS check_name,
           CASE WHEN to_regclass('public.' || required.name) IS NULL THEN 'CONFLICT' ELSE 'CLEAN' END AS status,
           coalesce(to_regclass('public.' || required.name)::text, 'missing') AS detail
      FROM required_relations required
    UNION ALL
    SELECT 20, 'prerequisite.column.' || required.table_name || '.' || required.column_name,
           CASE WHEN column_record.column_name IS NULL THEN 'CONFLICT'
                WHEN required.expected_type IS NOT NULL
                 AND column_record.data_type <> required.expected_type THEN 'CONFLICT'
                ELSE 'CLEAN' END,
           coalesce(column_record.data_type || CASE WHEN column_record.udt_name IS NULL THEN '' ELSE ' (' || column_record.udt_name || ')' END,
                    'missing; expected ' || coalesce(required.expected_type, 'existing project type'))
      FROM required_columns required
      LEFT JOIN information_schema.columns column_record
        ON column_record.table_schema='public'
       AND column_record.table_name=required.table_name
       AND column_record.column_name=required.column_name
    UNION ALL
    SELECT 30, 'prerequisite.function.' || required.signature,
           CASE WHEN to_regprocedure(required.signature) IS NULL THEN 'CONFLICT' ELSE 'CLEAN' END,
           coalesce(to_regprocedure(required.signature)::text, 'missing')
      FROM required_functions required
    UNION ALL
    SELECT 40, 'target.relation.' || target.name,
           CASE WHEN to_regclass('public.' || target.name) IS NULL THEN 'CLEAN' ELSE 'CONFLICT' END,
           CASE WHEN to_regclass('public.' || target.name) IS NULL
                THEN 'not present' ELSE 'Migration 034 may already be partially applied' END
      FROM target_relations target
    UNION ALL
    SELECT 50, 'target.function.' || target.signature,
           CASE WHEN to_regprocedure(target.signature) IS NULL THEN 'CLEAN' ELSE 'CONFLICT' END,
           CASE WHEN to_regprocedure(target.signature) IS NULL
                THEN 'not present' ELSE 'Migration 034 may already be partially applied' END
      FROM target_functions target
    UNION ALL
    SELECT 60, 'identity.uuid_fk_compatibility',
           CASE WHEN count(*) FILTER (WHERE data_type='uuid')=7 THEN 'CLEAN' ELSE 'CONFLICT' END,
           jsonb_object_agg(table_name || '.' || column_name, data_type)::text
      FROM information_schema.columns
     WHERE table_schema='public'
       AND (table_name,column_name) IN (
         ('users','id'),('patients','id'),('appointments','id'),
         ('consultations','id'),('consultations','patient_id'),
         ('consultations','doctor_id'),('consultations','appointment_id'))
    UNION ALL
    SELECT 70, 'postgres.full_text_support', 'CLEAN',
           'Built-in tsvector/to_tsvector available; no extension will be enabled'
    UNION ALL
    SELECT 80, 'tenancy.model',
           CASE WHEN EXISTS (
             SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND column_name='clinic_id'
                AND table_name IN ('users','patients','appointments','consultations'))
             THEN 'CONFLICT' ELSE 'CLEAN' END,
           CASE WHEN EXISTS (
             SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND column_name='clinic_id'
                AND table_name IN ('users','patients','appointments','consultations'))
             THEN 'clinic_id detected: Migration 034 single-clinic assumptions require review'
             ELSE 'single-clinic database; no clinic_id exists on clinical ownership tables' END
), blocking_summary AS (
    SELECT count(*) FILTER (WHERE status='CONFLICT') AS conflict_count
      FROM base_diagnostics
), diagnostics AS (
    SELECT ordinal, check_name, status, detail
      FROM base_diagnostics
    UNION ALL
    SELECT 90, 'migration_034.overall',
           CASE WHEN conflict_count>0 THEN 'CONFLICT' ELSE 'CLEAN' END,
           CASE WHEN conflict_count>0
                THEN conflict_count::text || ' blocking diagnostic(s) reported CONFLICT'
                ELSE 'All prerequisite, compatibility, tenancy, and target namespace diagnostics are CLEAN' END
      FROM blocking_summary
)
SELECT check_name, status, detail
  FROM diagnostics
 ORDER BY ordinal, check_name;
