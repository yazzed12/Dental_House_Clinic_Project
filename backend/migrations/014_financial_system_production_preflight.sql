-- READ-ONLY production inventory for the complete C6 financial vertical slice.
-- Execute manually and review before approving Migration 014.

-- Relations required by this slice.
SELECT relation_name, to_regclass('public.' || relation_name) AS relation
FROM unnest(ARRAY[
    'clinic_procedures', 'consultation_procedures', 'consultations',
    'financial_payment_records', 'financial_payment_allocations',
    'financial_charge_adjustments'
]) AS relation_name
ORDER BY relation_name;

-- Exact columns and PostgreSQL types.
SELECT table_name, ordinal_position, column_name, data_type, udt_schema, udt_name,
       is_nullable, column_default, is_generated, generation_expression
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
      'clinic_procedures', 'consultation_procedures', 'consultations',
      'financial_payment_records', 'financial_payment_allocations',
      'financial_charge_adjustments'
  )
ORDER BY table_name, ordinal_position;

-- PK, FK, unique, and check constraints.
SELECT conrelid::regclass AS table_name, conname, contype,
       pg_get_constraintdef(oid, true) AS definition
FROM pg_constraint
WHERE conrelid IN (
    'public.clinic_procedures'::regclass,
    'public.consultation_procedures'::regclass,
    'public.consultations'::regclass,
    'public.financial_payment_records'::regclass,
    'public.financial_payment_allocations'::regclass,
    'public.financial_charge_adjustments'::regclass
)
ORDER BY conrelid::regclass::text, contype, conname;

-- Enum types used by any required table column, plus values.
SELECT DISTINCT table_name, column_name, type_namespace.nspname AS enum_schema,
       enum_type.typname AS enum_name, enum_value.enumsortorder, enum_value.enumlabel
FROM information_schema.columns AS column_row
JOIN pg_namespace AS type_namespace ON type_namespace.nspname = column_row.udt_schema
JOIN pg_type AS enum_type
  ON enum_type.typnamespace = type_namespace.oid AND enum_type.typname = column_row.udt_name
JOIN pg_enum AS enum_value ON enum_value.enumtypid = enum_type.oid
WHERE column_row.table_schema = 'public'
  AND column_row.table_name IN (
      'clinic_procedures', 'consultation_procedures', 'consultations',
      'financial_payment_records', 'financial_payment_allocations',
      'financial_charge_adjustments'
  )
ORDER BY table_name, column_name, enum_value.enumsortorder;

-- RLS enabled/forced state.
SELECT relation.relname AS table_name, relation.relrowsecurity AS rls_enabled,
       relation.relforcerowsecurity AS rls_forced
FROM pg_class AS relation
JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
WHERE namespace.nspname = 'public'
  AND relation.relname IN (
      'clinic_procedures', 'consultation_procedures', 'consultations',
      'financial_payment_records', 'financial_payment_allocations',
      'financial_charge_adjustments'
  )
ORDER BY relation.relname;

-- Policies and table grants.
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
      'clinic_procedures', 'consultation_procedures', 'consultations',
      'financial_payment_records', 'financial_payment_allocations',
      'financial_charge_adjustments'
  )
ORDER BY tablename, policyname;

SELECT table_name, grantor, grantee, privilege_type, is_grantable
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name IN (
      'clinic_procedures', 'consultation_procedures', 'consultations',
      'financial_payment_records', 'financial_payment_allocations',
      'financial_charge_adjustments'
  )
ORDER BY table_name, grantee, privilege_type;

-- Triggers, including immutable-ledger enforcement.
SELECT event_object_table AS table_name, trigger_name, action_timing,
       event_manipulation, action_orientation, action_condition, action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND event_object_table IN (
      'clinic_procedures', 'consultation_procedures', 'consultations',
      'financial_payment_records', 'financial_payment_allocations',
      'financial_charge_adjustments'
  )
ORDER BY event_object_table, trigger_name, event_manipulation;

-- A. Catalog inventory and anomalies.
SELECT count(*) AS total_count,
       count(*) FILTER (WHERE is_active) AS active_count,
       count(*) FILTER (WHERE NOT is_active) AS inactive_count,
       count(*) FILTER (WHERE name IS NULL OR btrim(name) = '') AS blank_name_count,
       count(*) FILTER (WHERE price IS NULL OR price < 0) AS invalid_price_count
FROM public.clinic_procedures;

SELECT lower(btrim(name)) AS normalized_name, count(*) AS duplicate_count,
       array_agg(id ORDER BY id) AS procedure_ids
FROM public.clinic_procedures
GROUP BY lower(btrim(name))
HAVING count(*) > 1
ORDER BY normalized_name;

SELECT id, name, price, is_active, created_at, updated_at
FROM public.clinic_procedures
ORDER BY lower(btrim(name)), id;

-- B. Selection counts, invalid data, duplicates, and orphans.
SELECT count(*) AS row_count,
       count(*) FILTER (WHERE quantity NOT BETWEEN 1 AND 999) AS invalid_quantity_count,
       count(*) FILTER (WHERE unit_price_snapshot < 0) AS invalid_snapshot_price_count,
       min(quantity) AS min_quantity, max(quantity) AS max_quantity,
       min(unit_price_snapshot) AS min_snapshot_price,
       max(unit_price_snapshot) AS max_snapshot_price
FROM public.consultation_procedures;

SELECT consultation_id, procedure_id, count(*) AS duplicate_count
FROM public.consultation_procedures
GROUP BY consultation_id, procedure_id
HAVING count(*) > 1
ORDER BY consultation_id, procedure_id;

SELECT selection.id, selection.consultation_id, selection.procedure_id
FROM public.consultation_procedures AS selection
LEFT JOIN public.consultations AS consultation ON consultation.id = selection.consultation_id
LEFT JOIN public.clinic_procedures AS procedure ON procedure.id = selection.procedure_id
WHERE consultation.id IS NULL OR procedure.id IS NULL
ORDER BY selection.id;

-- C. Financial version distributions and consultation relationship anomalies.
SELECT count(*) AS consultation_count,
       count(*) FILTER (WHERE procedures_version IS NULL OR procedures_version < 0) AS invalid_procedures_version_count,
       count(*) FILTER (WHERE billing_version IS NULL OR billing_version < 0) AS invalid_billing_version_count,
       min(procedures_version) AS min_procedures_version,
       max(procedures_version) AS max_procedures_version,
       min(billing_version) AS min_billing_version,
       max(billing_version) AS max_billing_version
FROM public.consultations;

SELECT procedures_version, billing_version, count(*) AS consultation_count
FROM public.consultations
GROUP BY procedures_version, billing_version
ORDER BY procedures_version, billing_version;

SELECT consultation.id, consultation.patient_id, consultation.doctor_id,
       consultation.appointment_id, appointment.patient_id AS appointment_patient_id,
       appointment.doctor_id AS appointment_doctor_id
FROM public.consultations AS consultation
LEFT JOIN public.appointments AS appointment ON appointment.id = consultation.appointment_id
WHERE consultation.appointment_id IS NOT NULL
  AND (
      appointment.id IS NULL
      OR consultation.patient_id IS DISTINCT FROM appointment.patient_id
      OR (consultation.doctor_id IS NOT NULL AND appointment.doctor_id IS NOT NULL
          AND consultation.doctor_id IS DISTINCT FROM appointment.doctor_id)
  )
ORDER BY consultation.id;

-- D. Immutable payment revisions, values, chains, and orphans.
SELECT count(*) AS record_count, count(DISTINCT payment_id) AS logical_payment_count,
       count(*) FILTER (WHERE amount IS NULL OR amount <= 0) AS invalid_amount_count,
       count(*) FILTER (WHERE revision_number IS NULL OR revision_number < 1) AS invalid_revision_count,
       min(amount) AS min_amount, max(amount) AS max_amount,
       min(revision_number) AS min_revision, max(revision_number) AS max_revision
FROM public.financial_payment_records;

SELECT payment_id, consultation_id, array_agg(revision_number ORDER BY revision_number) AS revisions,
       min(revision_number) AS first_revision, max(revision_number) AS last_revision,
       count(*) AS revision_count
FROM public.financial_payment_records
GROUP BY payment_id, consultation_id
HAVING min(revision_number) <> 1
    OR max(revision_number) <> count(*)
ORDER BY payment_id;

SELECT payment_id, count(DISTINCT consultation_id) AS consultation_count
FROM public.financial_payment_records
GROUP BY payment_id
HAVING count(DISTINCT consultation_id) > 1
ORDER BY payment_id;

SELECT payment.id, payment.payment_id, payment.consultation_id, payment.created_by
FROM public.financial_payment_records AS payment
LEFT JOIN public.consultations AS consultation ON consultation.id = payment.consultation_id
LEFT JOIN public.users AS creator ON creator.id = payment.created_by
WHERE consultation.id IS NULL OR creator.id IS NULL
ORDER BY payment.payment_id, payment.revision_number;

-- E. Allocation validity, orphan checks, cross-consultation checks, and totals.
SELECT count(*) AS allocation_count,
       count(*) FILTER (WHERE allocated_amount IS NULL OR allocated_amount <= 0) AS invalid_amount_count,
       min(allocated_amount) AS min_amount, max(allocated_amount) AS max_amount
FROM public.financial_payment_allocations;

SELECT allocation.id, allocation.payment_record_id,
       allocation.consultation_procedure_id
FROM public.financial_payment_allocations AS allocation
LEFT JOIN public.financial_payment_records AS payment ON payment.id = allocation.payment_record_id
LEFT JOIN public.consultation_procedures AS selection ON selection.id = allocation.consultation_procedure_id
WHERE payment.id IS NULL OR selection.id IS NULL
   OR payment.consultation_id IS DISTINCT FROM selection.consultation_id
ORDER BY allocation.id;

SELECT payment.id AS payment_record_id, payment.payment_id, payment.revision_number,
       payment.amount, coalesce(sum(allocation.allocated_amount), 0) AS allocated_total,
       payment.amount - coalesce(sum(allocation.allocated_amount), 0) AS unallocated_credit
FROM public.financial_payment_records AS payment
LEFT JOIN public.financial_payment_allocations AS allocation
  ON allocation.payment_record_id = payment.id
GROUP BY payment.id, payment.payment_id, payment.revision_number, payment.amount
HAVING coalesce(sum(allocation.allocated_amount), 0) > payment.amount
    OR coalesce(sum(allocation.allocated_amount), 0) < payment.amount
ORDER BY payment.payment_id, payment.revision_number;

-- F. Charge adjustments, orphan checks, snapshot consistency, effective quantities.
SELECT count(*) AS adjustment_count,
       count(*) FILTER (WHERE quantity_delta = 0) AS zero_delta_count,
       count(*) FILTER (WHERE unit_price_snapshot < 0) AS invalid_price_count,
       min(quantity_delta) AS min_delta, max(quantity_delta) AS max_delta
FROM public.financial_charge_adjustments;

SELECT adjustment.id, adjustment.consultation_procedure_id,
       adjustment.unit_price_snapshot, selection.unit_price_snapshot AS selection_price,
       adjustment.created_by
FROM public.financial_charge_adjustments AS adjustment
LEFT JOIN public.consultation_procedures AS selection
  ON selection.id = adjustment.consultation_procedure_id
LEFT JOIN public.users AS creator ON creator.id = adjustment.created_by
WHERE selection.id IS NULL OR creator.id IS NULL
   OR adjustment.unit_price_snapshot IS DISTINCT FROM selection.unit_price_snapshot
ORDER BY adjustment.id;

SELECT selection.id, selection.consultation_id, selection.quantity AS original_quantity,
       coalesce(sum(adjustment.quantity_delta), 0) AS cumulative_delta,
       selection.quantity - coalesce(sum(adjustment.quantity_delta), 0) AS effective_quantity
FROM public.consultation_procedures AS selection
LEFT JOIN public.financial_charge_adjustments AS adjustment
  ON adjustment.consultation_procedure_id = selection.id
GROUP BY selection.id, selection.consultation_id, selection.quantity
HAVING selection.quantity - coalesce(sum(adjustment.quantity_delta), 0) NOT BETWEEN 0 AND 999
ORDER BY selection.consultation_id, selection.id;
