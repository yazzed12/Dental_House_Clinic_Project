-- Guarded rollback for the simplified Migration 004.
-- Refuses to remove any financial history or used billing versions.
BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

LOCK TABLE public.consultations IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.financial_payment_records IN ACCESS EXCLUSIVE MODE;
LOCK TABLE public.financial_payment_allocations IN ACCESS EXCLUSIVE MODE;
LOCK TABLE public.financial_charge_adjustments IN ACCESS EXCLUSIVE MODE;

DO $guard$
BEGIN
    IF to_regclass('public.financial_payment_records') IS NULL
       OR to_regclass('public.financial_payment_allocations') IS NULL
       OR to_regclass('public.financial_charge_adjustments') IS NULL THEN
        RAISE EXCEPTION 'A Migration 004 table is missing; inspect partial state manually';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'consultations'
          AND column_name = 'billing_version'
    ) THEN
        RAISE EXCEPTION 'consultations.billing_version is missing';
    END IF;
    IF EXISTS (SELECT 1 FROM public.financial_payment_records)
       OR EXISTS (SELECT 1 FROM public.financial_payment_allocations)
       OR EXISTS (SELECT 1 FROM public.financial_charge_adjustments) THEN
        RAISE EXCEPTION 'Rollback refused: financial history exists';
    END IF;
    IF EXISTS (SELECT 1 FROM public.consultations WHERE billing_version <> 0) THEN
        RAISE EXCEPTION 'Rollback refused: billing_version has been used';
    END IF;
END
$guard$;

DROP TABLE public.financial_payment_allocations;
DROP TABLE public.financial_payment_records;
DROP TABLE public.financial_charge_adjustments;
DROP FUNCTION public.phase_f2_validate_payment_record();
DROP FUNCTION public.phase_f2_validate_allocation();
DROP FUNCTION public.phase_f2_prepare_charge_adjustment();
DROP FUNCTION public.phase_f2_reject_immutable_change();
ALTER TABLE public.consultations DROP COLUMN billing_version;

COMMIT;
