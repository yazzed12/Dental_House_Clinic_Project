-- Guarded rollback for migration 003. Refuses to discard any F1 catalog/history data.
BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

LOCK TABLE public.consultations IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.clinic_procedures IN ACCESS EXCLUSIVE MODE;
LOCK TABLE public.consultation_procedures IN ACCESS EXCLUSIVE MODE;

DO $guard$
BEGIN
    IF to_regclass('public.clinic_procedures') IS NULL
       OR to_regclass('public.consultation_procedures') IS NULL THEN
        RAISE EXCEPTION 'F1 tables are missing; inspect partial state manually';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'consultations'
          AND column_name = 'procedures_version'
    ) THEN
        RAISE EXCEPTION 'consultations.procedures_version is missing';
    END IF;

    IF EXISTS (SELECT 1 FROM public.consultation_procedures)
       OR EXISTS (SELECT 1 FROM public.clinic_procedures) THEN
        RAISE EXCEPTION 'Rollback refused: F1 catalog or historical rows exist';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.consultations WHERE procedures_version <> 0
    ) THEN
        RAISE EXCEPTION 'Rollback refused: procedures_version has been used';
    END IF;
END
$guard$;

DROP TABLE public.consultation_procedures;
DROP TRIGGER clinic_procedures_set_updated_at ON public.clinic_procedures;
DROP FUNCTION public.phase_f1_set_updated_at();
DROP TABLE public.clinic_procedures;
ALTER TABLE public.consultations DROP COLUMN procedures_version;

COMMIT;
