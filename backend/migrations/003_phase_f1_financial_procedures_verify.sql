-- Read-only post-migration verification. Safe to run in production after migration 003.
BEGIN TRANSACTION READ ONLY;

SELECT
    current_setting('transaction_read_only') = 'on' AS transaction_is_read_only,
    to_regclass('public.clinic_procedures') IS NOT NULL AS clinic_procedures_exists,
    to_regclass('public.consultation_procedures') IS NOT NULL AS consultation_procedures_exists;

SELECT table_name, column_name, data_type, udt_name, is_nullable,
       numeric_precision, numeric_scale, is_generated, generation_expression,
       column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('clinic_procedures', 'consultation_procedures', 'consultations')
  AND column_name IN (
      'id', 'price', 'is_active', 'created_at', 'updated_at',
      'procedures_version', 'consultation_id', 'procedure_id',
      'procedure_name_snapshot', 'unit_price_snapshot', 'quantity',
      'line_total'
  )
ORDER BY table_name, ordinal_position;

SELECT conrelid::regclass::text AS table_name, conname, contype,
       pg_get_constraintdef(oid, true) AS definition
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
  AND conrelid IN (
      'public.clinic_procedures'::regclass,
      'public.consultation_procedures'::regclass,
      'public.consultations'::regclass
  )
  AND (
      conrelid <> 'public.consultations'::regclass
      OR conname = 'consultations_procedures_version_nonnegative_ck'
  )
ORDER BY table_name, conname;

SELECT c.relname AS table_name, c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('clinic_procedures', 'consultation_procedures')
ORDER BY c.relname;

SELECT schemaname, tablename, policyname, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('clinic_procedures', 'consultation_procedures')
ORDER BY tablename, policyname;

SELECT role_name, table_name,
       has_table_privilege(role_name, 'public.' || table_name, 'SELECT') AS can_select,
       has_table_privilege(role_name, 'public.' || table_name, 'INSERT') AS can_insert,
       has_table_privilege(role_name, 'public.' || table_name, 'UPDATE') AS can_update,
       has_table_privilege(role_name, 'public.' || table_name, 'DELETE') AS can_delete
FROM (VALUES ('anon'), ('authenticated')) AS roles(role_name)
CROSS JOIN (VALUES ('clinic_procedures'), ('consultation_procedures')) AS tables(table_name)
ORDER BY role_name, table_name;

SELECT
    count(*) FILTER (WHERE procedures_version IS NULL) AS null_versions,
    count(*) FILTER (WHERE procedures_version < 0) AS negative_versions,
    min(procedures_version) AS minimum_version,
    max(procedures_version) AS maximum_version
FROM public.consultations;

SELECT
    count(*) FILTER (WHERE price < 0) AS negative_catalog_prices,
    count(*) FILTER (WHERE trim(name) = '') AS empty_catalog_names
FROM public.clinic_procedures;

SELECT
    count(*) FILTER (WHERE unit_price_snapshot < 0) AS negative_snapshot_prices,
    count(*) FILTER (WHERE quantity < 1 OR quantity > 999) AS invalid_quantities,
    count(*) FILTER (WHERE line_total <> unit_price_snapshot * quantity)
        AS nondeterministic_totals
FROM public.consultation_procedures;

ROLLBACK;
