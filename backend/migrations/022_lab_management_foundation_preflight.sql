-- READ-ONLY production preflight for Migration 022.
-- Returns one consolidated result set for review in the Supabase SQL Editor.
-- This file does not mutate schema or data.

WITH target_relations(name) AS (
    VALUES ('labs'), ('lab_products'), ('consultation_lab_items')
), target_functions(signature) AS (
    VALUES
        ('security.lab_actor()'),
        ('public.list_labs(boolean)'),
        ('public.create_lab(text)'),
        ('public.archive_lab(uuid)'),
        ('public.list_lab_products(uuid,boolean)'),
        ('public.create_lab_product(uuid,text,numeric)'),
        ('public.update_lab_product_price(uuid,numeric)'),
        ('public.archive_lab_product(uuid)'),
        ('public.get_consultation_lab_items(uuid)'),
        ('public.save_consultation_lab_items(uuid,jsonb,text,boolean)')
), required_columns AS (
    SELECT column_row.table_name, column_row.column_name, column_row.ordinal_position,
           column_row.data_type, column_row.udt_schema, column_row.udt_name,
           column_row.is_nullable, column_row.column_default
      FROM information_schema.columns AS column_row
     WHERE column_row.table_schema = 'public'
       AND column_row.table_name IN ('consultations', 'appointments', 'patients', 'users', 'clinic_procedures', 'consultation_procedures')
), consultation_constraints AS (
    SELECT constraint_record.conname, constraint_record.contype,
           pg_get_constraintdef(constraint_record.oid, true) AS definition
      FROM pg_constraint AS constraint_record
     WHERE constraint_record.conrelid = to_regclass('public.consultations')
), money_columns AS (
    SELECT column_row.table_name, column_row.column_name, column_row.data_type,
           column_row.numeric_precision, column_row.numeric_scale
      FROM information_schema.columns AS column_row
     WHERE column_row.table_schema = 'public'
       AND column_row.data_type = 'numeric'
), function_inventory AS (
    SELECT proc.oid, namespace.nspname || '.' || proc.oid::regprocedure::text AS signature,
           proc.prosecdef, proc.proconfig, proc.proowner, proc.proacl
      FROM pg_proc AS proc
      JOIN pg_namespace AS namespace ON namespace.oid = proc.pronamespace
     WHERE namespace.nspname IN ('public', 'security')
), checks AS (
    SELECT 10 AS sort_group, 'required.relations'::text AS check_name,
           CASE WHEN to_regclass('public.consultations') IS NOT NULL
                     AND to_regclass('public.patients') IS NOT NULL
                     AND to_regclass('public.users') IS NOT NULL
                     AND to_regclass('public.appointments') IS NOT NULL
                THEN 'OK' ELSE 'CONFLICT' END AS status,
           jsonb_build_object(
               'consultations', to_regclass('public.consultations'),
               'patients', to_regclass('public.patients'),
               'users', to_regclass('public.users'),
               'appointments', to_regclass('public.appointments')
           )::text AS details

    UNION ALL
    SELECT 20, 'target.relation.' || target.name,
           CASE WHEN to_regclass('public.' || target.name) IS NULL THEN 'READY' ELSE 'CONFLICT' END,
           coalesce(to_regclass('public.' || target.name)::text, 'Relation does not exist.')
      FROM target_relations AS target

    UNION ALL
    SELECT 30, 'consultations.lab_note',
           CASE WHEN NOT EXISTS (
                    SELECT 1 FROM required_columns
                     WHERE table_name = 'consultations' AND column_name = 'lab_note'
                ) THEN 'READY' ELSE 'CONFLICT' END,
           coalesce((SELECT jsonb_build_object(
               'data_type', data_type, 'udt_schema', udt_schema,
               'udt_name', udt_name, 'nullable', is_nullable,
               'default', column_default
           )::text FROM required_columns
             WHERE table_name = 'consultations' AND column_name = 'lab_note'),
             'Column does not exist.')

    UNION ALL
    SELECT 40, 'ownership.column_types',
           CASE WHEN (SELECT udt_name FROM required_columns WHERE table_name='consultations' AND column_name='id')='uuid'
                     AND (SELECT udt_name FROM required_columns WHERE table_name='consultations' AND column_name='patient_id')='uuid'
                     AND (SELECT udt_name FROM required_columns WHERE table_name='consultations' AND column_name='doctor_id')='uuid'
                     AND (SELECT udt_name FROM required_columns WHERE table_name='patients' AND column_name='id')='uuid'
                     AND (SELECT udt_name FROM required_columns WHERE table_name='users' AND column_name='id')='uuid'
                THEN 'OK' ELSE 'CONFLICT' END,
           coalesce((SELECT jsonb_agg(jsonb_build_object(
               'table', table_name, 'column', column_name,
               'type', udt_schema || '.' || udt_name, 'nullable', is_nullable
           ) ORDER BY table_name, ordinal_position)::text
             FROM required_columns
            WHERE (table_name, column_name) IN (
                ('consultations','id'), ('consultations','patient_id'),
                ('consultations','doctor_id'), ('consultations','appointment_id'),
                ('appointments','id'), ('appointments','patient_id'), ('appointments','doctor_id'),
                ('patients','id'), ('users','id'), ('users','supabase_user_id'),
                ('users','role'), ('users','is_active'), ('users','approved_at')
            )), '[]')

    UNION ALL
    SELECT 50, 'consultations.constraints', 'INFO',
           coalesce((SELECT jsonb_agg(jsonb_build_object(
               'name', conname, 'type', contype, 'definition', definition
           ) ORDER BY conname)::text FROM consultation_constraints), '[]')

    UNION ALL
    SELECT 60, 'money.numeric_conventions', 'INFO',
           coalesce((SELECT jsonb_agg(jsonb_build_object(
               'table', table_name, 'column', column_name,
               'precision', numeric_precision, 'scale', numeric_scale
           ) ORDER BY table_name, column_name)::text FROM money_columns), '[]')

    UNION ALL
    SELECT 70, 'target.function.' || target.signature,
           CASE WHEN to_regprocedure(target.signature) IS NULL THEN 'READY' ELSE 'CONFLICT' END,
           coalesce(to_regprocedure(target.signature)::text, 'Function does not exist.')
      FROM target_functions AS target

    UNION ALL
    SELECT 80, 'existing.security_definer_conventions', 'INFO',
           coalesce((SELECT jsonb_agg(jsonb_build_object(
               'signature', signature, 'security_definer', prosecdef,
               'fixed_search_path', ('search_path=pg_catalog, pg_temp'=ANY(coalesce(proconfig, ARRAY[]::text[]))),
               'authenticated_execute', has_function_privilege('authenticated', oid, 'EXECUTE'),
               'anon_execute', has_function_privilege('anon', oid, 'EXECUTE'),
               'public_execute', EXISTS (
                   SELECT 1 FROM aclexplode(coalesce(proacl, acldefault('f', proowner))) AS acl_entry
                    WHERE acl_entry.grantee=0 AND acl_entry.privilege_type='EXECUTE'
               )
           ) ORDER BY signature)::text FROM function_inventory
             WHERE prosecdef AND signature LIKE 'public.%'), '[]')

    UNION ALL
    SELECT 90, 'existing.rls_and_privileges', 'INFO',
           coalesce((SELECT jsonb_agg(jsonb_build_object(
               'table', relation.relname,
               'rls_enabled', relation.relrowsecurity,
               'rls_forced', relation.relforcerowsecurity,
               'authenticated_select', has_table_privilege('authenticated', relation.oid, 'SELECT'),
               'authenticated_write', has_table_privilege('authenticated', relation.oid, 'INSERT,UPDATE,DELETE'),
               'anon_access', has_table_privilege('anon', relation.oid, 'SELECT,INSERT,UPDATE,DELETE')
           ) ORDER BY relation.relname)::text
             FROM pg_class AS relation
             JOIN pg_namespace AS namespace ON namespace.oid=relation.relnamespace
            WHERE namespace.nspname='public'
              AND relation.relname IN ('consultations','clinic_procedures','consultation_procedures')), '[]')

    UNION ALL
    SELECT 100, 'medical_report.isolation_baseline', 'INFO',
           jsonb_build_object(
               'clinical_reports', to_regclass('public.clinical_reports'),
               'finalize_rpc', to_regprocedure('public.finalize_clinical_report(uuid,jsonb,text,text)'),
               'history_rpc', to_regprocedure('public.list_doctor_consultation_history()'),
               'patient_reports_rpc', to_regprocedure('public.get_patient_clinical_reports(uuid)'),
               'clinical_report_lab_columns', coalesce((
                   SELECT jsonb_agg(column_name ORDER BY column_name)
                     FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='clinical_reports'
                      AND column_name LIKE '%lab%'
               ), '[]'::jsonb)
           )::text

    UNION ALL
    SELECT 110, 'schema.conflicting_state',
           CASE WHEN EXISTS (SELECT 1 FROM target_relations WHERE to_regclass('public.' || name) IS NOT NULL)
                      OR EXISTS (SELECT 1 FROM target_functions WHERE to_regprocedure(signature) IS NOT NULL)
                      OR EXISTS (SELECT 1 FROM required_columns WHERE table_name='consultations' AND column_name='lab_note')
                THEN 'CONFLICT' ELSE 'NONE' END,
           jsonb_build_object(
               'existing_relations', coalesce((SELECT jsonb_agg(name) FROM target_relations WHERE to_regclass('public.' || name) IS NOT NULL), '[]'::jsonb),
               'existing_functions', coalesce((SELECT jsonb_agg(signature) FROM target_functions WHERE to_regprocedure(signature) IS NOT NULL), '[]'::jsonb),
               'lab_note_exists', EXISTS (SELECT 1 FROM required_columns WHERE table_name='consultations' AND column_name='lab_note')
           )::text
)
SELECT check_name, status, details
  FROM checks
 ORDER BY sort_group, check_name;
