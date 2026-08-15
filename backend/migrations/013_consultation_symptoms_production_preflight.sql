-- READ-ONLY production inventory for the C6 Symptoms vertical slice.
-- Run manually and review every result before approving Migration 013.

-- A. Table existence.
SELECT to_regclass('public.symptoms') AS symptoms_table;

-- B. Columns and exact PostgreSQL types.
SELECT
    column_name,
    ordinal_position,
    data_type,
    udt_schema,
    udt_name,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'symptoms'
ORDER BY ordinal_position;

-- C. Constraints, including primary and foreign keys.
SELECT
    constraint_row.conname AS constraint_name,
    constraint_row.contype AS constraint_type,
    pg_get_constraintdef(constraint_row.oid, true) AS definition
FROM pg_constraint AS constraint_row
WHERE constraint_row.conrelid = 'public.symptoms'::regclass
ORDER BY constraint_row.contype, constraint_row.conname;

-- D. RLS enabled and forced state.
SELECT
    namespace.nspname AS schema_name,
    relation.relname AS table_name,
    relation.relrowsecurity AS rls_enabled,
    relation.relforcerowsecurity AS rls_forced
FROM pg_class AS relation
JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
WHERE namespace.nspname = 'public'
  AND relation.relname = 'symptoms';

-- E. Existing policies.
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'symptoms'
ORDER BY policyname;

-- F. Existing grants, including grants to PUBLIC.
SELECT
    grantor,
    grantee,
    privilege_type,
    is_grantable
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'symptoms'
ORDER BY grantee, privilege_type, grantor;

-- G. Existing triggers.
SELECT
    trigger_name,
    action_timing,
    event_manipulation,
    action_orientation,
    action_condition,
    action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND event_object_table = 'symptoms'
ORDER BY trigger_name, event_manipulation;

-- H/I. Total, active, and inactive row counts.
SELECT
    count(*) AS row_count,
    count(*) FILTER (WHERE is_active <> 0) AS active_count,
    count(*) FILTER (WHERE is_active = 0) AS inactive_count,
    count(*) FILTER (WHERE is_active IS NULL) AS null_active_state_count
FROM public.symptoms;

-- J. Duplicate logical names using the target normalization.
SELECT
    lower(btrim(name)) AS normalized_name,
    count(*) AS duplicate_count,
    array_agg(id::text ORDER BY id::text) AS symptom_ids,
    array_agg(name ORDER BY id::text) AS stored_names
FROM public.symptoms
WHERE name IS NOT NULL
  AND btrim(name) <> ''
GROUP BY lower(btrim(name))
HAVING count(*) > 1
ORDER BY normalized_name;

-- K. NULL or blank names.
SELECT id, name, created_by, is_active, created_at
FROM public.symptoms
WHERE name IS NULL OR btrim(name) = ''
ORDER BY id::text;

-- L. created_by values without a matching application user.
SELECT symptom.id, symptom.name, symptom.created_by
FROM public.symptoms AS symptom
LEFT JOIN public.users AS creator ON creator.id = symptom.created_by
WHERE symptom.created_by IS NOT NULL
  AND creator.id IS NULL
ORDER BY lower(btrim(symptom.name)), symptom.id::text;

-- M. Existing rows in deterministic display order.
SELECT id, name, created_by, is_active, created_at
FROM public.symptoms
ORDER BY lower(btrim(name)) NULLS LAST, id::text;
