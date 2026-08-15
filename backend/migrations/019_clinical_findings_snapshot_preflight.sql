-- Read-only production preflight for Migration 019.
-- Returns one consolidated result set for the Supabase SQL Editor.
-- Execute manually only after separate production approval.

WITH consultation_columns AS (
    SELECT column_name, ordinal_position, data_type, udt_schema, udt_name,
           is_nullable, column_default
      FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'consultations'
), consultation_constraints AS (
    SELECT constraint_record.conname, constraint_record.contype,
           pg_get_constraintdef(constraint_record.oid, true) AS definition
      FROM pg_constraint AS constraint_record
     WHERE constraint_record.conrelid = 'public.consultations'::regclass
), save_functions AS (
    SELECT proc.oid, proc.oid::regprocedure::text AS signature,
           proc.prosecdef, proc.proconfig, proc.proowner, proc.proacl
      FROM pg_proc AS proc
      JOIN pg_namespace AS namespace ON namespace.oid = proc.pronamespace
     WHERE namespace.nspname = 'public'
       AND proc.proname = 'save_current_consultation'
), history_functions AS (
    SELECT proc.oid, proc.proname, proc.oid::regprocedure::text AS signature,
           proc.prosecdef, proc.proconfig, proc.proowner, proc.proacl
      FROM pg_proc AS proc
      JOIN pg_namespace AS namespace ON namespace.oid = proc.pronamespace
     WHERE namespace.nspname = 'public'
       AND proc.proname IN (
           'get_patient_consultation_history',
           'list_doctor_consultation_history'
       )
), consultation_counts AS (
    SELECT count(*) AS consultations,
           count(*) FILTER (WHERE symptoms_snapshot IS NULL) AS legacy_null_symptoms,
           count(*) FILTER (WHERE symptoms_snapshot = '[]'::jsonb) AS explicit_empty_symptoms
      FROM public.consultations
), checks AS (
    SELECT 10 AS sort_group, 'clinical_findings_snapshot.column'::text AS check_name,
           CASE
               WHEN NOT EXISTS (
                   SELECT 1 FROM consultation_columns
                    WHERE column_name = 'clinical_findings_snapshot'
               ) THEN 'READY'
               WHEN EXISTS (
                   SELECT 1 FROM consultation_columns
                    WHERE column_name = 'clinical_findings_snapshot'
                      AND data_type = 'jsonb' AND is_nullable = 'YES'
               ) THEN 'ALREADY_PRESENT'
               ELSE 'CONFLICT'
           END AS status,
           coalesce((
               SELECT jsonb_build_object(
                   'data_type', data_type,
                   'udt_schema', udt_schema,
                   'udt_name', udt_name,
                   'is_nullable', is_nullable,
                   'column_default', column_default
               )::text
                 FROM consultation_columns
                WHERE column_name = 'clinical_findings_snapshot'
           ), 'Column does not exist; Migration 019 can add it.') AS details

    UNION ALL
    SELECT 20, 'consultations.columns',
           CASE WHEN EXISTS (SELECT 1 FROM consultation_columns) THEN 'OK' ELSE 'CONFLICT' END,
           coalesce((SELECT jsonb_agg(jsonb_build_object(
               'name', column_name, 'position', ordinal_position,
               'data_type', data_type, 'udt_schema', udt_schema, 'udt_name', udt_name,
               'nullable', is_nullable, 'default', column_default
           ) ORDER BY ordinal_position)::text FROM consultation_columns), '[]')

    UNION ALL
    SELECT 30, 'consultations.constraints', 'INFO',
           coalesce((SELECT jsonb_agg(jsonb_build_object(
               'name', conname, 'type', contype, 'definition', definition
           ) ORDER BY conname)::text FROM consultation_constraints), '[]')

    UNION ALL
    SELECT 40, 'save_current_consultation.signature.' || save.signature,
           CASE WHEN save.prosecdef
                     AND ('search_path=pg_catalog, pg_temp' = ANY(save.proconfig))
                THEN 'OK' ELSE 'REVIEW' END,
           jsonb_build_object(
               'signature', save.signature,
               'security_definer', save.prosecdef,
               'fixed_search_path', ('search_path=pg_catalog, pg_temp' = ANY(save.proconfig)),
               'authenticated_execute', has_function_privilege('authenticated', save.oid, 'EXECUTE'),
               'anon_execute', has_function_privilege('anon', save.oid, 'EXECUTE'),
               'public_execute', EXISTS (
                   SELECT 1
                     FROM aclexplode(coalesce(save.proacl, acldefault('f', save.proowner))) AS acl_entry
                    WHERE acl_entry.grantee = 0 AND acl_entry.privilege_type = 'EXECUTE'
               )
           )::text
      FROM save_functions AS save

    UNION ALL
    SELECT 50, 'save_current_consultation.expected_018_state',
           CASE
               WHEN EXISTS (
                   SELECT 1 FROM save_functions
                    WHERE signature = 'save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean)'
               )
                AND EXISTS (
                   SELECT 1 FROM save_functions
                    WHERE signature = 'save_current_consultation(uuid,jsonb,integer,integer,text,boolean)'
               )
                AND NOT EXISTS (
                   SELECT 1 FROM save_functions
                    WHERE signature = 'save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)'
               ) THEN 'READY'
               ELSE 'CONFLICT'
           END,
           jsonb_build_object(
               'six_parameter_exists', EXISTS (
                   SELECT 1 FROM save_functions
                    WHERE signature = 'save_current_consultation(uuid,jsonb,integer,integer,text,boolean)'
               ),
               'eight_parameter_exists', EXISTS (
                   SELECT 1 FROM save_functions
                    WHERE signature = 'save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean)'
               ),
               'ten_parameter_already_exists', EXISTS (
                   SELECT 1 FROM save_functions
                    WHERE signature = 'save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)'
               )
           )::text

    UNION ALL
    SELECT 60, 'history_rpc.' || expected.name,
           CASE
               WHEN history.oid IS NULL THEN 'CONFLICT'
               WHEN history.prosecdef
                    AND ('search_path=pg_catalog, pg_temp' = ANY(history.proconfig))
                    AND has_function_privilege('authenticated', history.oid, 'EXECUTE')
                    AND NOT has_function_privilege('anon', history.oid, 'EXECUTE')
                    AND NOT EXISTS (
                        SELECT 1
                          FROM aclexplode(coalesce(history.proacl, acldefault('f', history.proowner))) AS acl_entry
                         WHERE acl_entry.grantee = 0 AND acl_entry.privilege_type = 'EXECUTE'
                    ) THEN 'OK'
               ELSE 'REVIEW'
           END,
           CASE WHEN history.oid IS NULL THEN
               jsonb_build_object('exists', false, 'expected_signature', expected.signature)::text
           ELSE jsonb_build_object(
               'exists', true,
               'signature', history.signature,
               'security_definer', history.prosecdef,
               'fixed_search_path', ('search_path=pg_catalog, pg_temp' = ANY(history.proconfig)),
               'authenticated_execute', has_function_privilege('authenticated', history.oid, 'EXECUTE'),
               'anon_execute', has_function_privilege('anon', history.oid, 'EXECUTE'),
               'public_execute', EXISTS (
                   SELECT 1
                     FROM aclexplode(coalesce(history.proacl, acldefault('f', history.proowner))) AS acl_entry
                    WHERE acl_entry.grantee = 0 AND acl_entry.privilege_type = 'EXECUTE'
               )
           )::text END
      FROM (VALUES
          ('get_patient_consultation_history', 'get_patient_consultation_history(uuid)'),
          ('list_doctor_consultation_history', 'list_doctor_consultation_history()')
      ) AS expected(name, signature)
      LEFT JOIN history_functions AS history
        ON history.proname = expected.name AND history.signature = expected.signature

    UNION ALL
    SELECT 70, 'consultations.count', 'INFO', consultations::text FROM consultation_counts
    UNION ALL
    SELECT 71, 'consultations.symptoms_snapshot.null_count', 'INFO', legacy_null_symptoms::text FROM consultation_counts
    UNION ALL
    SELECT 72, 'consultations.symptoms_snapshot.explicit_empty_count', 'INFO', explicit_empty_symptoms::text FROM consultation_counts

    UNION ALL
    SELECT 80, 'schema.conflicting_state',
           CASE
               WHEN EXISTS (
                   SELECT 1 FROM consultation_columns
                    WHERE column_name = 'clinical_findings_snapshot'
                      AND (data_type <> 'jsonb' OR is_nullable <> 'YES')
               ) OR EXISTS (
                   SELECT 1 FROM save_functions
                    WHERE signature = 'save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)'
               ) THEN 'CONFLICT'
               ELSE 'NONE'
           END,
           jsonb_build_object(
               'wrong_clinical_findings_column', EXISTS (
                   SELECT 1 FROM consultation_columns
                    WHERE column_name = 'clinical_findings_snapshot'
                      AND (data_type <> 'jsonb' OR is_nullable <> 'YES')
               ),
               'migration_019_signature_already_present', EXISTS (
                   SELECT 1 FROM save_functions
                    WHERE signature = 'save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)'
               )
           )::text
)
SELECT check_name, status, details
  FROM checks
 ORDER BY sort_group, check_name;
