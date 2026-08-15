-- Consultation Session Notes
-- Verified target: Supabase PostgreSQL
-- Expected pre-migration consultation row count: 13
--
-- Existing created_at values are initialized from last_updated.
-- last_updated is the best available historical timestamp proxy; it is not
-- guaranteed to represent the original creation time.

BEGIN;

LOCK TABLE public.consultations IN SHARE ROW EXCLUSIVE MODE;

DO $preflight$
DECLARE
    actual_type TEXT;
    consultation_count BIGINT;
BEGIN
    SELECT format_type(a.atttypid, a.atttypmod)
      INTO actual_type
      FROM pg_attribute AS a
     WHERE a.attrelid = 'public.users'::regclass
       AND a.attname = 'id'
       AND a.attnum > 0
       AND NOT a.attisdropped;

    IF actual_type IS DISTINCT FROM 'uuid' THEN
        RAISE EXCEPTION
            'Expected public.users.id to be uuid, found %',
            actual_type;
    END IF;

    SELECT format_type(a.atttypid, a.atttypmod)
      INTO actual_type
      FROM pg_attribute AS a
     WHERE a.attrelid = 'public.appointments'::regclass
       AND a.attname = 'id'
       AND a.attnum > 0
       AND NOT a.attisdropped;

    IF actual_type IS DISTINCT FROM 'uuid' THEN
        RAISE EXCEPTION
            'Expected public.appointments.id to be uuid, found %',
            actual_type;
    END IF;

    SELECT format_type(a.atttypid, a.atttypmod)
      INTO actual_type
      FROM pg_attribute AS a
     WHERE a.attrelid = 'public.consultations'::regclass
       AND a.attname = 'id'
       AND a.attnum > 0
       AND NOT a.attisdropped;

    IF actual_type IS DISTINCT FROM 'uuid' THEN
        RAISE EXCEPTION
            'Expected public.consultations.id to remain uuid, found %',
            actual_type;
    END IF;

    SELECT format_type(a.atttypid, a.atttypmod)
      INTO actual_type
      FROM pg_attribute AS a
     WHERE a.attrelid = 'public.consultations'::regclass
       AND a.attname = 'patient_id'
       AND a.attnum > 0
       AND NOT a.attisdropped;

    IF actual_type IS DISTINCT FROM 'uuid' THEN
        RAISE EXCEPTION
            'Expected public.consultations.patient_id to be uuid, found %',
            actual_type;
    END IF;

    SELECT format_type(a.atttypid, a.atttypmod)
      INTO actual_type
      FROM pg_attribute AS a
     WHERE a.attrelid = 'public.consultations'::regclass
       AND a.attname = 'version'
       AND a.attnum > 0
       AND NOT a.attisdropped;

    IF actual_type IS DISTINCT FROM 'integer' THEN
        RAISE EXCEPTION
            'Expected public.consultations.version to be integer, found %',
            actual_type;
    END IF;

    SELECT format_type(a.atttypid, a.atttypmod)
      INTO actual_type
      FROM pg_attribute AS a
     WHERE a.attrelid = 'public.consultations'::regclass
       AND a.attname = 'last_updated'
       AND a.attnum > 0
       AND NOT a.attisdropped;

    IF actual_type IS DISTINCT FROM 'timestamp with time zone' THEN
        RAISE EXCEPTION
            'Expected public.consultations.last_updated to be timestamp with time zone, found %',
            actual_type;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_attribute AS a
         WHERE a.attrelid = 'public.consultations'::regclass
           AND a.attname IN (
               'session_note',
               'doctor_id',
               'appointment_id',
               'created_at'
           )
           AND a.attnum > 0
           AND NOT a.attisdropped
    ) THEN
        RAISE EXCEPTION
            'One or more target columns already exist; inspect partial migration state manually';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint AS c
         WHERE c.conrelid = 'public.consultations'::regclass
           AND c.conname = 'consultations_patient_id_key'
           AND c.contype = 'u'
           AND pg_get_constraintdef(c.oid, true) = 'UNIQUE (patient_id)'
    ) THEN
        RAISE EXCEPTION
            'Expected consultations_patient_id_key UNIQUE (patient_id) was not found';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint AS c
         WHERE c.conrelid = 'public.consultations'::regclass
           AND c.conname = 'consultations_patient_id_fkey'
           AND c.contype = 'f'
           AND pg_get_constraintdef(c.oid, true)
               = 'FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE'
    ) THEN
        RAISE EXCEPTION
            'Expected consultations_patient_id_fkey was not found or differs from the verified definition';
    END IF;

    SELECT COUNT(*)
      INTO consultation_count
      FROM public.consultations;

    IF consultation_count <> 13 THEN
        RAISE EXCEPTION
            'Expected 13 consultation rows from preflight, found %. Re-run the schema/data preflight before proceeding.',
            consultation_count;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM public.consultations
         WHERE patient_id IS NULL
            OR version IS NULL
            OR last_updated IS NULL
    ) THEN
        RAISE EXCEPTION
            'Unexpected NULL patient_id, version, or last_updated found; manual review required';
    END IF;

    IF to_regclass('public.ix_consultations_patient_id') IS NOT NULL
       OR to_regclass('public.ix_consultations_doctor_id') IS NOT NULL
       OR to_regclass('public.ix_consultations_appointment_id') IS NOT NULL THEN
        RAISE EXCEPTION
            'One or more target index names already exist; inspect schema state manually';
    END IF;
END
$preflight$;

-- Transaction-local preservation snapshot. It is automatically removed at COMMIT.
CREATE TEMP TABLE consultation_session_notes_snapshot
ON COMMIT DROP
AS
SELECT
    id,
    patient_id,
    data,
    version,
    last_updated
FROM public.consultations;

ALTER TABLE public.consultations
    ADD COLUMN session_note TEXT NULL,
    ADD COLUMN doctor_id UUID NULL,
    ADD COLUMN appointment_id UUID NULL,
    ADD COLUMN created_at TIMESTAMP WITH TIME ZONE NULL;

-- Historical proxy only; this does not claim last_updated is the true creation time.
UPDATE public.consultations
   SET created_at = last_updated;

ALTER TABLE public.consultations
    ALTER COLUMN created_at SET DEFAULT CURRENT_TIMESTAMP,
    ALTER COLUMN created_at SET NOT NULL,
    ADD CONSTRAINT consultations_doctor_id_fkey
        FOREIGN KEY (doctor_id)
        REFERENCES public.users(id)
        ON DELETE SET NULL,
    ADD CONSTRAINT consultations_appointment_id_fkey
        FOREIGN KEY (appointment_id)
        REFERENCES public.appointments(id)
        ON DELETE SET NULL;

-- Remove only the verified one-consultation-per-patient constraint.
ALTER TABLE public.consultations
    DROP CONSTRAINT consultations_patient_id_key;

CREATE INDEX ix_consultations_patient_id
    ON public.consultations (patient_id);

CREATE INDEX ix_consultations_doctor_id
    ON public.consultations (doctor_id);

CREATE INDEX ix_consultations_appointment_id
    ON public.consultations (appointment_id);

DO $preservation_check$
BEGIN
    IF (SELECT COUNT(*) FROM public.consultations) <> 13 THEN
        RAISE EXCEPTION
            'Consultation row count changed during migration; rolling back';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM consultation_session_notes_snapshot AS before_row
          FULL OUTER JOIN public.consultations AS after_row
            ON after_row.id = before_row.id
         WHERE before_row.id IS NULL
            OR after_row.id IS NULL
            OR after_row.patient_id IS DISTINCT FROM before_row.patient_id
            OR after_row.data IS DISTINCT FROM before_row.data
            OR after_row.version IS DISTINCT FROM before_row.version
            OR after_row.last_updated IS DISTINCT FROM before_row.last_updated
    ) THEN
        RAISE EXCEPTION
            'Existing consultation data changed during migration; rolling back';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM public.consultations
         WHERE created_at IS DISTINCT FROM last_updated
    ) THEN
        RAISE EXCEPTION
            'Historical created_at initialization differs from last_updated; rolling back';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM public.consultations
         WHERE session_note IS NOT NULL
            OR doctor_id IS NOT NULL
            OR appointment_id IS NOT NULL
    ) THEN
        RAISE EXCEPTION
            'Unexpected speculative session metadata was introduced; rolling back';
    END IF;

    IF EXISTS (
        SELECT patient_id
          FROM public.consultations
         WHERE patient_id IS NOT NULL
         GROUP BY patient_id
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION
            'Unexpected duplicate patient sessions appeared during migration; rolling back';
    END IF;
END
$preservation_check$;

COMMIT;
