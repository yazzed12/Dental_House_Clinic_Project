-- Read-only verification for the simplified Migration 004.
BEGIN TRANSACTION READ ONLY;

SELECT current_setting('transaction_read_only') = 'on' AS transaction_is_read_only;

SELECT
    to_regclass('public.financial_payment_records') IS NOT NULL
        AS payment_records_exists,
    to_regclass('public.financial_payment_allocations') IS NOT NULL
        AS payment_allocations_exists,
    to_regclass('public.financial_charge_adjustments') IS NOT NULL
        AS charge_adjustments_exists;

SELECT table_name, column_name, data_type, udt_name, is_nullable,
       numeric_precision, numeric_scale, is_generated, generation_expression,
       column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
      'consultations', 'financial_payment_records',
      'financial_payment_allocations', 'financial_charge_adjustments'
  )
  AND (table_name <> 'consultations' OR column_name = 'billing_version')
ORDER BY table_name, ordinal_position;

SELECT conrelid::regclass::text AS table_name, conname, contype,
       pg_get_constraintdef(oid, true) AS definition
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
  AND conrelid IN (
      'public.consultations'::regclass,
      'public.financial_payment_records'::regclass,
      'public.financial_payment_allocations'::regclass,
      'public.financial_charge_adjustments'::regclass
  )
  AND (conrelid <> 'public.consultations'::regclass
       OR conname = 'consultations_billing_version_nonnegative_ck')
ORDER BY table_name, conname;

SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN (
      'financial_payment_records', 'financial_payment_allocations',
      'financial_charge_adjustments'
  )
ORDER BY tablename, indexname;

SELECT c.relname AS table_name, c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
      'financial_payment_records', 'financial_payment_allocations',
      'financial_charge_adjustments'
  )
ORDER BY c.relname;

SELECT schemaname, tablename, policyname, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
      'financial_payment_records', 'financial_payment_allocations',
      'financial_charge_adjustments'
  )
ORDER BY tablename, policyname;

SELECT role_name, table_name,
       has_table_privilege(role_name, 'public.' || table_name, 'SELECT') AS can_select,
       has_table_privilege(role_name, 'public.' || table_name, 'INSERT') AS can_insert,
       has_table_privilege(role_name, 'public.' || table_name, 'UPDATE') AS can_update,
       has_table_privilege(role_name, 'public.' || table_name, 'DELETE') AS can_delete
FROM (VALUES ('anon'), ('authenticated')) roles(role_name)
CROSS JOIN (VALUES
    ('financial_payment_records'),
    ('financial_payment_allocations'),
    ('financial_charge_adjustments')
) tables(table_name)
ORDER BY role_name, table_name;

SELECT tgrelid::regclass::text AS table_name, tgname,
       pg_get_triggerdef(oid, true) AS definition
FROM pg_trigger
WHERE NOT tgisinternal
  AND tgrelid IN (
      'public.financial_payment_records'::regclass,
      'public.financial_payment_allocations'::regclass,
      'public.financial_charge_adjustments'::regclass
  )
ORDER BY table_name, tgname;

SELECT p.proname, pg_get_functiondef(p.oid) AS definition,
       p.proconfig AS configuration
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
      'phase_f2_validate_payment_record',
      'phase_f2_validate_allocation',
      'phase_f2_prepare_charge_adjustment',
      'phase_f2_reject_immutable_change'
  )
ORDER BY p.proname;

SELECT
    (SELECT count(*) FROM public.financial_payment_records) AS payment_records,
    (SELECT count(*) FROM public.financial_payment_allocations) AS allocations,
    (SELECT count(*) FROM public.financial_charge_adjustments) AS adjustments,
    (SELECT count(*) FROM public.consultations WHERE billing_version IS NULL)
        AS null_versions,
    (SELECT count(*) FROM public.consultations WHERE billing_version <> 0)
        AS nonzero_versions;

ROLLBACK;
