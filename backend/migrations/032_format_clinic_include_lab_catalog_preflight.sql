-- Migration 032 preflight. Read-only; run manually before the migration.
DO $preflight$
DECLARE
  v_missing text;
BEGIN
  SELECT string_agg(name, ', ' ORDER BY name) INTO v_missing
  FROM unnest(ARRAY[
    'notifications','financial_payment_allocations','financial_charge_adjustments',
    'financial_payment_records','consultation_procedures','lab_payments',
    'consultation_lab_items','clinical_reports','patient_dental_state','records',
    'logs','consultations','appointments','patients','lab_products','labs'
  ]) AS required(name)
  WHERE to_regclass('public.' || name) IS NULL;

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'CONFLICT: missing approved Format tables: %', v_missing;
  END IF;

  IF to_regprocedure('public.format_clinic_data()') IS NULL
     OR to_regprocedure('security.admin_user_actor()') IS NULL THEN
    RAISE EXCEPTION 'CONFLICT: Migration 031 Format/Admin foundation is missing';
  END IF;

  IF to_regclass('public.users') IS NULL
     OR to_regclass('public.clinic_settings') IS NULL
     OR to_regclass('public.clinic_procedures') IS NULL
     OR to_regclass('public.symptoms') IS NULL
     OR to_regclass('public.appointment_conditions') IS NULL THEN
    RAISE EXCEPTION 'CONFLICT: a required preserved table is missing';
  END IF;
END
$preflight$;

WITH approved(name) AS (VALUES
  ('notifications'),('financial_payment_allocations'),('financial_charge_adjustments'),
  ('financial_payment_records'),('consultation_procedures'),('lab_payments'),
  ('consultation_lab_items'),('clinical_reports'),('patient_dental_state'),('records'),
  ('logs'),('consultations'),('appointments'),('patients'),('lab_products'),('labs')
), checks AS (
  SELECT 10 AS ordinal, 'format.current_definition' AS check_name, 'INFO' AS status,
    pg_get_functiondef('public.format_clinic_data()'::regprocedure) AS details
  UNION ALL
  SELECT 20, 'format.current_truncate_statement', 'INFO',
    coalesce((regexp_match(
      pg_get_functiondef('public.format_clinic_data()'::regprocedure),
      '(?is)truncate[[:space:]]+table[[:space:]]+(.+?);'
    ))[1], 'TRUNCATE statement not found')
  UNION ALL
  SELECT 30, 'format.approved_row_counts', 'INFO',
    jsonb_object_agg(
      approved.name,
      ((xpath('/row/count/text()', query_to_xml(
        format('select count(*) as count from public.%I', approved.name), false, true, ''
      )))[1]::text::bigint)
      ORDER BY approved.name
    )::text
  FROM approved
  UNION ALL
  SELECT 40, 'format.lab_catalog_counts', 'INFO', jsonb_build_object(
    'labs', (SELECT count(*) FROM public.labs),
    'labProducts', (SELECT count(*) FROM public.lab_products),
    'labPayments', (SELECT count(*) FROM public.lab_payments),
    'consultationLabItems', (SELECT count(*) FROM public.consultation_lab_items)
  )::text
  UNION ALL
  SELECT 50, 'format.lab_catalog_foreign_keys', 'INFO',
    coalesce(jsonb_agg(jsonb_build_object(
      'childTable', child_ns.nspname || '.' || child.relname,
      'constraint', constraint_row.conname,
      'parentTable', parent_ns.nspname || '.' || parent.relname,
      'definition', pg_get_constraintdef(constraint_row.oid)
    ) ORDER BY child.relname, constraint_row.conname), '[]'::jsonb)::text
  FROM pg_constraint AS constraint_row
  JOIN pg_class AS child ON child.oid = constraint_row.conrelid
  JOIN pg_namespace AS child_ns ON child_ns.oid = child.relnamespace
  JOIN pg_class AS parent ON parent.oid = constraint_row.confrelid
  JOIN pg_namespace AS parent_ns ON parent_ns.oid = parent.relnamespace
  WHERE constraint_row.contype = 'f'
    AND parent_ns.nspname = 'public'
    AND parent.relname IN ('labs', 'lab_products')
  UNION ALL
  SELECT 60, 'format.unapproved_fk_children',
    CASE WHEN count(*) = 0 THEN 'OK' ELSE 'CONFLICT' END,
    CASE WHEN count(*) = 0
      THEN 'All FK children of labs/lab_products are included in the explicit Format set'
      ELSE 'CONFLICT: adding labs/lab_products requires unapproved FK child tables: ' ||
        string_agg(format('%I.%I (%I)', child_ns.nspname, child.relname, constraint_row.conname), ', ' ORDER BY child.relname, constraint_row.conname)
    END
  FROM pg_constraint AS constraint_row
  JOIN pg_class AS child ON child.oid = constraint_row.conrelid
  JOIN pg_namespace AS child_ns ON child_ns.oid = child.relnamespace
  JOIN pg_class AS parent ON parent.oid = constraint_row.confrelid
  JOIN pg_namespace AS parent_ns ON parent_ns.oid = parent.relnamespace
  WHERE constraint_row.contype = 'f'
    AND parent_ns.nspname = 'public'
    AND parent.relname IN ('labs', 'lab_products')
    AND NOT (child_ns.nspname = 'public' AND child.relname IN (SELECT name FROM approved))
  UNION ALL
  SELECT 70, 'preserved.row_counts', 'INFO', jsonb_build_object(
    'users', (SELECT count(*) FROM public.users),
    'authLinkedUsers', (SELECT count(*) FROM public.users WHERE supabase_user_id IS NOT NULL),
    'clinicSettings', (SELECT count(*) FROM public.clinic_settings),
    'clinicProcedures', (SELECT count(*) FROM public.clinic_procedures),
    'symptoms', (SELECT count(*) FROM public.symptoms),
    'appointmentConditions', (SELECT count(*) FROM public.appointment_conditions)
  )::text
  UNION ALL
  SELECT 80, 'format.rpc_acls', 'INFO', coalesce(jsonb_agg(acl::text ORDER BY acl::text), '[]'::jsonb)::text
  FROM pg_proc AS procedure
  CROSS JOIN LATERAL aclexplode(coalesce(procedure.proacl, acldefault('f', procedure.proowner))) AS acl
  WHERE procedure.oid = 'public.format_clinic_data()'::regprocedure
  UNION ALL
  SELECT 90, 'migration_032.existing_conflicts',
    CASE WHEN count(*) = 0 THEN 'OK' ELSE 'CONFLICT' END,
    CASE WHEN count(*) = 0 THEN 'No conflicting Migration 032 database objects found'
      ELSE 'CONFLICT: unexpected 032 database object: ' || string_agg(conflict, ', ' ORDER BY conflict)
    END
  FROM (
    SELECT procedure.oid::regprocedure::text AS conflict
    FROM pg_proc AS procedure
    JOIN pg_namespace AS namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'public'
      AND procedure.proname LIKE '%format_clinic_include_lab_catalog%'
  ) AS conflicts
), summary AS (
  SELECT 999 AS ordinal, 'summary' AS check_name,
    CASE WHEN bool_or(status = 'CONFLICT') THEN 'CONFLICT' ELSE 'CLEAN' END AS status,
    CASE WHEN bool_or(status = 'CONFLICT')
      THEN 'CONFLICT: Migration 032 Lab catalog format expansion does not match current schema; inspect the CONFLICT row(s) above'
      ELSE 'CLEAN: Migration 032 Lab catalog format expansion matches current schema'
    END AS details
  FROM checks
)
SELECT check_name, status, details
FROM (SELECT * FROM checks UNION ALL SELECT * FROM summary) AS report
ORDER BY ordinal;
