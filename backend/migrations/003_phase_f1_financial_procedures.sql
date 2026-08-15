-- Phase F1: procedure catalog and immutable consultation price snapshots.
-- Production target verified read-only on 2026-08-10: PostgreSQL 17.6.
-- This migration is intentionally fail-closed and has not been executed.

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

LOCK TABLE public.consultations IN SHARE ROW EXCLUSIVE MODE;

DO $preflight$
DECLARE
    actual_type text;
BEGIN
    SELECT format_type(a.atttypid, a.atttypmod)
      INTO actual_type
      FROM pg_attribute a
     WHERE a.attrelid = 'public.consultations'::regclass
       AND a.attname = 'id'
       AND a.attnum > 0
       AND NOT a.attisdropped;
    IF actual_type IS DISTINCT FROM 'uuid' THEN
        RAISE EXCEPTION 'Expected consultations.id uuid, found %', actual_type;
    END IF;

    SELECT format_type(a.atttypid, a.atttypmod)
      INTO actual_type
      FROM pg_attribute a
     WHERE a.attrelid = 'public.consultations'::regclass
       AND a.attname = 'created_at'
       AND a.attnum > 0
       AND NOT a.attisdropped;
    IF actual_type IS DISTINCT FROM 'timestamp with time zone' THEN
        RAISE EXCEPTION 'Expected consultations.created_at timestamptz, found %', actual_type;
    END IF;

    IF to_regclass('public.clinic_procedures') IS NOT NULL
       OR to_regclass('public.consultation_procedures') IS NOT NULL THEN
        RAISE EXCEPTION 'An F1 target table already exists; inspect partial state manually';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_attribute
         WHERE attrelid = 'public.consultations'::regclass
           AND attname = 'procedures_version'
           AND attnum > 0
           AND NOT attisdropped
    ) THEN
        RAISE EXCEPTION 'consultations.procedures_version already exists; inspect partial state manually';
    END IF;

    IF to_regclass('public.clinic_procedures_name_ci_uq') IS NOT NULL
       OR to_regclass('public.consultation_procedures_consultation_idx') IS NOT NULL
       OR to_regclass('public.consultation_procedures_procedure_idx') IS NOT NULL THEN
        RAISE EXCEPTION 'An F1 target index name already exists';
    END IF;

    IF to_regprocedure('public.phase_f1_set_updated_at()') IS NOT NULL THEN
        RAISE EXCEPTION 'F1 timestamp function already exists';
    END IF;
END
$preflight$;

CREATE TEMP TABLE phase_f1_migration_guard ON COMMIT DROP AS
SELECT count(*)::bigint AS consultation_count
FROM public.consultations;

CREATE TABLE public.clinic_procedures (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    price numeric(12, 2) NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT clinic_procedures_name_nonempty_ck CHECK (trim(name) <> ''),
    CONSTRAINT clinic_procedures_price_nonnegative_ck CHECK (price >= 0)
);

CREATE UNIQUE INDEX clinic_procedures_name_ci_uq
    ON public.clinic_procedures (lower(trim(name)));

CREATE FUNCTION public.phase_f1_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $function$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END
$function$;

CREATE TRIGGER clinic_procedures_set_updated_at
BEFORE UPDATE ON public.clinic_procedures
FOR EACH ROW
EXECUTE FUNCTION public.phase_f1_set_updated_at();

ALTER TABLE public.consultations
    ADD COLUMN procedures_version integer NOT NULL DEFAULT 0,
    ADD CONSTRAINT consultations_procedures_version_nonnegative_ck
        CHECK (procedures_version >= 0);

CREATE TABLE public.consultation_procedures (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    consultation_id uuid NOT NULL,
    procedure_id uuid NOT NULL,
    procedure_name_snapshot text NOT NULL,
    unit_price_snapshot numeric(12, 2) NOT NULL,
    quantity integer NOT NULL,
    line_total numeric(15, 2)
        GENERATED ALWAYS AS (unit_price_snapshot * quantity) STORED,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT consultation_procedures_consultation_fk
        FOREIGN KEY (consultation_id)
        REFERENCES public.consultations(id)
        ON DELETE RESTRICT,
    CONSTRAINT consultation_procedures_procedure_fk
        FOREIGN KEY (procedure_id)
        REFERENCES public.clinic_procedures(id)
        ON DELETE RESTRICT,
    CONSTRAINT consultation_procedures_name_nonempty_ck
        CHECK (trim(procedure_name_snapshot) <> ''),
    CONSTRAINT consultation_procedures_unit_price_nonnegative_ck
        CHECK (unit_price_snapshot >= 0),
    CONSTRAINT consultation_procedures_quantity_ck
        CHECK (quantity BETWEEN 1 AND 999),
    CONSTRAINT consultation_procedures_consultation_procedure_uq
        UNIQUE (consultation_id, procedure_id)
);

CREATE INDEX consultation_procedures_consultation_idx
    ON public.consultation_procedures (consultation_id);

CREATE INDEX consultation_procedures_procedure_idx
    ON public.consultation_procedures (procedure_id);

ALTER TABLE public.clinic_procedures ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consultation_procedures ENABLE ROW LEVEL SECURITY;

-- The browser receives no direct access in F1. The FastAPI PostgreSQL connection
-- remains authoritative; no service-role key or credential is exposed to frontend code.
REVOKE ALL ON TABLE public.clinic_procedures FROM anon, authenticated;
REVOKE ALL ON TABLE public.consultation_procedures FROM anon, authenticated;

DO $preservation$
BEGIN
    IF (SELECT count(*) FROM public.consultations)
       <> (SELECT consultation_count FROM phase_f1_migration_guard) THEN
        RAISE EXCEPTION 'Consultation row count changed during F1 migration';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.consultations WHERE procedures_version <> 0
    ) THEN
        RAISE EXCEPTION 'Existing consultations did not receive procedures_version 0';
    END IF;

    IF EXISTS (SELECT 1 FROM public.clinic_procedures)
       OR EXISTS (SELECT 1 FROM public.consultation_procedures) THEN
        RAISE EXCEPTION 'F1 migration unexpectedly created data rows';
    END IF;
END
$preservation$;

COMMIT;
