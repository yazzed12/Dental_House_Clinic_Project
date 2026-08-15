-- Financial Phases F2-F5: immutable payment revisions, procedure allocations,
-- and history-safe quantity corrections.
-- Prepared from a read-only production audit on 2026-08-10.
-- Execute manually only after explicit approval.
BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

LOCK TABLE public.consultations IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.consultation_procedures IN SHARE ROW EXCLUSIVE MODE;

DO $preflight$
DECLARE
    actual_type text;
    target_name text;
BEGIN
    FOREACH target_name IN ARRAY ARRAY[
        'financial_payment_records',
        'financial_payment_allocations',
        'financial_charge_adjustments'
    ] LOOP
        IF to_regclass('public.' || target_name) IS NOT NULL THEN
            RAISE EXCEPTION 'Target relation public.% already exists', target_name;
        END IF;
    END LOOP;

    IF EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.consultations'::regclass
          AND attname = 'billing_version'
          AND attnum > 0
          AND NOT attisdropped
    ) THEN
        RAISE EXCEPTION 'consultations.billing_version already exists';
    END IF;

    SELECT format_type(a.atttypid, a.atttypmod) INTO actual_type
    FROM pg_attribute a
    WHERE a.attrelid = 'public.consultations'::regclass
      AND a.attname = 'id' AND a.attnum > 0 AND NOT a.attisdropped;
    IF actual_type IS DISTINCT FROM 'uuid' THEN
        RAISE EXCEPTION 'Expected consultations.id uuid, found %', actual_type;
    END IF;

    SELECT format_type(a.atttypid, a.atttypmod) INTO actual_type
    FROM pg_attribute a
    WHERE a.attrelid = 'public.consultation_procedures'::regclass
      AND a.attname = 'id' AND a.attnum > 0 AND NOT a.attisdropped;
    IF actual_type IS DISTINCT FROM 'uuid' THEN
        RAISE EXCEPTION 'Expected consultation_procedures.id uuid, found %', actual_type;
    END IF;

    SELECT format_type(a.atttypid, a.atttypmod) INTO actual_type
    FROM pg_attribute a
    WHERE a.attrelid = 'public.users'::regclass
      AND a.attname = 'id' AND a.attnum > 0 AND NOT a.attisdropped;
    IF actual_type IS DISTINCT FROM 'uuid' THEN
        RAISE EXCEPTION 'Expected users.id uuid, found %', actual_type;
    END IF;

    IF to_regprocedure('public.phase_f2_validate_payment_record()') IS NOT NULL
       OR to_regprocedure('public.phase_f2_validate_allocation()') IS NOT NULL
       OR to_regprocedure('public.phase_f2_prepare_charge_adjustment()') IS NOT NULL
       OR to_regprocedure('public.phase_f2_reject_immutable_change()') IS NOT NULL THEN
        RAISE EXCEPTION 'A Phase F2 function name already exists';
    END IF;
END
$preflight$;

CREATE TEMP TABLE phase_f2_migration_guard ON COMMIT DROP AS
SELECT
    (SELECT count(*) FROM public.consultations)::bigint AS consultation_count,
    (SELECT count(*) FROM public.consultation_procedures)::bigint AS procedure_count;

ALTER TABLE public.consultations
    ADD COLUMN billing_version integer NOT NULL DEFAULT 0,
    ADD CONSTRAINT consultations_billing_version_nonnegative_ck
        CHECK (billing_version >= 0);

-- One immutable row per payment revision. payment_id is the stable logical
-- payment identity; the greatest revision_number is authoritative.
CREATE TABLE public.financial_payment_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id uuid NOT NULL,
    consultation_id uuid NOT NULL,
    revision_number integer NOT NULL,
    amount numeric(15, 2) NOT NULL,
    paid_at timestamptz NOT NULL,
    correction_reason text,
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT financial_payment_records_consultation_fk
        FOREIGN KEY (consultation_id)
        REFERENCES public.consultations(id) ON DELETE RESTRICT,
    CONSTRAINT financial_payment_records_created_by_fk
        FOREIGN KEY (created_by)
        REFERENCES public.users(id) ON DELETE RESTRICT,
    CONSTRAINT financial_payment_records_revision_positive_ck
        CHECK (revision_number >= 1),
    CONSTRAINT financial_payment_records_amount_positive_ck
        CHECK (amount > 0),
    CONSTRAINT financial_payment_records_reason_ck
        CHECK (
            (revision_number = 1 AND correction_reason IS NULL)
            OR
            (revision_number > 1 AND trim(coalesce(correction_reason, '')) <> '')
        ),
    CONSTRAINT financial_payment_records_payment_revision_uq
        UNIQUE (payment_id, revision_number)
);

-- Each allocation belongs to one exact immutable payment revision and one
-- historical F1 procedure snapshot.
CREATE TABLE public.financial_payment_allocations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_record_id uuid NOT NULL,
    consultation_procedure_id uuid NOT NULL,
    allocated_amount numeric(15, 2) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT financial_payment_allocations_record_fk
        FOREIGN KEY (payment_record_id)
        REFERENCES public.financial_payment_records(id) ON DELETE RESTRICT,
    CONSTRAINT financial_payment_allocations_procedure_fk
        FOREIGN KEY (consultation_procedure_id)
        REFERENCES public.consultation_procedures(id) ON DELETE RESTRICT,
    CONSTRAINT financial_payment_allocations_amount_positive_ck
        CHECK (allocated_amount > 0),
    CONSTRAINT financial_payment_allocations_record_procedure_uq
        UNIQUE (payment_record_id, consultation_procedure_id)
);

-- quantity_delta is an amount to subtract from the original F1 quantity.
-- Positive values reduce the bill; negative values reverse a prior reduction.
-- Effective quantity = original quantity - SUM(quantity_delta).
CREATE TABLE public.financial_charge_adjustments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    consultation_procedure_id uuid NOT NULL,
    quantity_delta integer NOT NULL,
    unit_price_snapshot numeric(12, 2) NOT NULL,
    line_total_delta numeric(15, 2)
        GENERATED ALWAYS AS (unit_price_snapshot * quantity_delta) STORED,
    reason text NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT financial_charge_adjustments_procedure_fk
        FOREIGN KEY (consultation_procedure_id)
        REFERENCES public.consultation_procedures(id) ON DELETE RESTRICT,
    CONSTRAINT financial_charge_adjustments_created_by_fk
        FOREIGN KEY (created_by)
        REFERENCES public.users(id) ON DELETE RESTRICT,
    CONSTRAINT financial_charge_adjustments_delta_nonzero_ck
        CHECK (quantity_delta <> 0),
    CONSTRAINT financial_charge_adjustments_price_nonnegative_ck
        CHECK (unit_price_snapshot >= 0),
    CONSTRAINT financial_charge_adjustments_reason_nonempty_ck
        CHECK (trim(reason) <> '')
);

CREATE INDEX financial_payment_records_consultation_idx
    ON public.financial_payment_records
    (consultation_id, payment_id, revision_number DESC);
CREATE INDEX financial_payment_records_created_by_idx
    ON public.financial_payment_records (created_by)
    WHERE created_by IS NOT NULL;
CREATE INDEX financial_payment_allocations_procedure_idx
    ON public.financial_payment_allocations (consultation_procedure_id);
CREATE INDEX financial_charge_adjustments_procedure_idx
    ON public.financial_charge_adjustments
    (consultation_procedure_id, created_at, id);

-- Enforce an original revision 1 followed by gap-free corrections for the
-- same consultation. Locking the latest row serializes corrections to one
-- logical payment.
CREATE FUNCTION public.phase_f2_validate_payment_record()
RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, public AS $function$
DECLARE
    previous_record public.financial_payment_records%ROWTYPE;
BEGIN
    SELECT r.* INTO previous_record
      FROM public.financial_payment_records r
     WHERE r.payment_id = NEW.payment_id
     ORDER BY r.revision_number DESC
     LIMIT 1
     FOR UPDATE;

    IF NOT FOUND THEN
        IF NEW.revision_number <> 1 THEN
            RAISE EXCEPTION 'The first payment revision must be revision 1';
        END IF;
    ELSE
        IF NEW.consultation_id <> previous_record.consultation_id THEN
            RAISE EXCEPTION 'Payment revisions cannot change consultation';
        END IF;
        IF NEW.revision_number <> previous_record.revision_number + 1 THEN
            RAISE EXCEPTION 'Payment revision must follow the current revision';
        END IF;
    END IF;

    RETURN NEW;
END
$function$;

CREATE TRIGGER financial_payment_records_validate
BEFORE INSERT ON public.financial_payment_records
FOR EACH ROW EXECUTE FUNCTION public.phase_f2_validate_payment_record();

-- Enforce same-consultation allocation and cap allocations at the exact
-- revision amount. Same consultation also prevents cross-patient allocation.
CREATE FUNCTION public.phase_f2_validate_allocation()
RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, public AS $function$
DECLARE
    record_amount numeric(15, 2);
    payment_consultation_id uuid;
    procedure_consultation_id uuid;
    allocated_total numeric(15, 2);
BEGIN
    SELECT r.amount, r.consultation_id
      INTO record_amount, payment_consultation_id
      FROM public.financial_payment_records r
     WHERE r.id = NEW.payment_record_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment record % does not exist', NEW.payment_record_id;
    END IF;

    SELECT cp.consultation_id INTO procedure_consultation_id
      FROM public.consultation_procedures cp
     WHERE cp.id = NEW.consultation_procedure_id;

    IF procedure_consultation_id IS DISTINCT FROM payment_consultation_id THEN
        RAISE EXCEPTION 'Payment and procedure must belong to the same consultation';
    END IF;

    SELECT coalesce(sum(a.allocated_amount), 0) + NEW.allocated_amount
      INTO allocated_total
      FROM public.financial_payment_allocations a
     WHERE a.payment_record_id = NEW.payment_record_id;

    IF allocated_total > record_amount THEN
        RAISE EXCEPTION 'Allocations cannot exceed the payment revision amount';
    END IF;

    RETURN NEW;
END
$function$;

CREATE TRIGGER financial_payment_allocations_validate
BEFORE INSERT ON public.financial_payment_allocations
FOR EACH ROW EXECUTE FUNCTION public.phase_f2_validate_allocation();

-- Copy the price from the immutable F1 snapshot and ensure all cumulative
-- adjustments leave an effective quantity between zero and 999.
CREATE FUNCTION public.phase_f2_prepare_charge_adjustment()
RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, public AS $function$
DECLARE
    original_quantity integer;
    snapshot_price numeric(12, 2);
    effective_quantity integer;
BEGIN
    SELECT cp.quantity, cp.unit_price_snapshot
      INTO original_quantity, snapshot_price
      FROM public.consultation_procedures cp
     WHERE cp.id = NEW.consultation_procedure_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Consultation procedure % does not exist',
            NEW.consultation_procedure_id;
    END IF;

    SELECT original_quantity
           - coalesce(sum(a.quantity_delta), 0)
           - NEW.quantity_delta
      INTO effective_quantity
      FROM public.financial_charge_adjustments a
     WHERE a.consultation_procedure_id = NEW.consultation_procedure_id;

    IF effective_quantity < 0 OR effective_quantity > 999 THEN
        RAISE EXCEPTION 'Effective procedure quantity must be between 0 and 999';
    END IF;

    NEW.unit_price_snapshot := snapshot_price;
    RETURN NEW;
END
$function$;

CREATE TRIGGER financial_charge_adjustments_prepare
BEFORE INSERT ON public.financial_charge_adjustments
FOR EACH ROW EXECUTE FUNCTION public.phase_f2_prepare_charge_adjustment();

CREATE FUNCTION public.phase_f2_reject_immutable_change()
RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog AS $function$
BEGIN
    RAISE EXCEPTION '% rows are append-only', TG_TABLE_NAME;
END
$function$;

CREATE TRIGGER financial_payment_records_immutable
BEFORE UPDATE OR DELETE ON public.financial_payment_records
FOR EACH ROW EXECUTE FUNCTION public.phase_f2_reject_immutable_change();
CREATE TRIGGER financial_payment_allocations_immutable
BEFORE UPDATE OR DELETE ON public.financial_payment_allocations
FOR EACH ROW EXECUTE FUNCTION public.phase_f2_reject_immutable_change();
CREATE TRIGGER financial_charge_adjustments_immutable
BEFORE UPDATE OR DELETE ON public.financial_charge_adjustments
FOR EACH ROW EXECUTE FUNCTION public.phase_f2_reject_immutable_change();

ALTER TABLE public.financial_payment_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financial_payment_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financial_charge_adjustments ENABLE ROW LEVEL SECURITY;

-- No direct browser policies are created. FastAPI remains authoritative.
REVOKE ALL ON TABLE public.financial_payment_records FROM anon, authenticated;
REVOKE ALL ON TABLE public.financial_payment_allocations FROM anon, authenticated;
REVOKE ALL ON TABLE public.financial_charge_adjustments FROM anon, authenticated;

DO $preservation$
BEGIN
    IF (SELECT count(*) FROM public.consultations)
       <> (SELECT consultation_count FROM pg_temp.phase_f2_migration_guard) THEN
        RAISE EXCEPTION 'Consultation row count changed during migration';
    END IF;
    IF (SELECT count(*) FROM public.consultation_procedures)
       <> (SELECT procedure_count FROM pg_temp.phase_f2_migration_guard) THEN
        RAISE EXCEPTION 'Consultation procedure row count changed during migration';
    END IF;
    IF EXISTS (SELECT 1 FROM public.consultations WHERE billing_version <> 0) THEN
        RAISE EXCEPTION 'Existing consultations did not receive billing_version 0';
    END IF;
    IF EXISTS (SELECT 1 FROM public.financial_payment_records)
       OR EXISTS (SELECT 1 FROM public.financial_payment_allocations)
       OR EXISTS (SELECT 1 FROM public.financial_charge_adjustments) THEN
        RAISE EXCEPTION 'Migration unexpectedly created financial rows';
    END IF;
END
$preservation$;

COMMIT;
