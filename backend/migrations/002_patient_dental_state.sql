BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

LOCK TABLE public.patients IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.consultations IN SHARE ROW EXCLUSIVE MODE;

DO $migration$
DECLARE
    patients_id_type text;
    consultations_id_type text;
    consultations_patient_id_type text;
    consultations_data_type text;
    consultations_version_type text;
    consultations_created_at_type text;
    consultations_last_updated_type text;
    consultation_count_before bigint;
    consultation_count_after bigint;
    consultation_fingerprint_before text;
    consultation_fingerprint_after text;
    expected_state_count bigint;
    actual_state_count bigint;
    mismatched_state_count bigint;
BEGIN
    IF to_regclass('public.patient_dental_state') IS NOT NULL THEN
        RAISE EXCEPTION
            'public.patient_dental_state already exists; refusing to recreate or overwrite it';
    END IF;

    SELECT format_type(a.atttypid, a.atttypmod)
      INTO patients_id_type
      FROM pg_attribute a
     WHERE a.attrelid = 'public.patients'::regclass
       AND a.attname = 'id'
       AND NOT a.attisdropped;

    SELECT format_type(a.atttypid, a.atttypmod)
      INTO consultations_id_type
      FROM pg_attribute a
     WHERE a.attrelid = 'public.consultations'::regclass
       AND a.attname = 'id'
       AND NOT a.attisdropped;

    SELECT format_type(a.atttypid, a.atttypmod)
      INTO consultations_patient_id_type
      FROM pg_attribute a
     WHERE a.attrelid = 'public.consultations'::regclass
       AND a.attname = 'patient_id'
       AND NOT a.attisdropped;

    SELECT format_type(a.atttypid, a.atttypmod)
      INTO consultations_data_type
      FROM pg_attribute a
     WHERE a.attrelid = 'public.consultations'::regclass
       AND a.attname = 'data'
       AND NOT a.attisdropped;

    SELECT format_type(a.atttypid, a.atttypmod)
      INTO consultations_version_type
      FROM pg_attribute a
     WHERE a.attrelid = 'public.consultations'::regclass
       AND a.attname = 'version'
       AND NOT a.attisdropped;

    SELECT format_type(a.atttypid, a.atttypmod)
      INTO consultations_created_at_type
      FROM pg_attribute a
     WHERE a.attrelid = 'public.consultations'::regclass
       AND a.attname = 'created_at'
       AND NOT a.attisdropped;

    SELECT format_type(a.atttypid, a.atttypmod)
      INTO consultations_last_updated_type
      FROM pg_attribute a
     WHERE a.attrelid = 'public.consultations'::regclass
       AND a.attname = 'last_updated'
       AND NOT a.attisdropped;

    IF patients_id_type <> 'uuid'
       OR consultations_id_type <> 'uuid'
       OR consultations_patient_id_type <> 'uuid' THEN
        RAISE EXCEPTION
            'Expected UUID identifiers; patients.id=%, consultations.id=%, consultations.patient_id=%',
            patients_id_type,
            consultations_id_type,
            consultations_patient_id_type;
    END IF;

    IF consultations_data_type <> 'text'
       OR consultations_version_type <> 'integer'
       OR consultations_created_at_type <> 'timestamp with time zone'
       OR consultations_last_updated_type <> 'timestamp with time zone' THEN
        RAISE EXCEPTION
            'Unexpected consultation types; data=%, version=%, created_at=%, last_updated=%',
            consultations_data_type,
            consultations_version_type,
            consultations_created_at_type,
            consultations_last_updated_type;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM public.consultations
         WHERE patient_id IS NULL
            OR data IS NULL
            OR jsonb_typeof(data::jsonb) <> 'object'
    ) THEN
        RAISE EXCEPTION
            'Consultation backfill source contains a null patient, null data, invalid JSON, or non-object JSON value';
    END IF;

    SELECT
        count(*),
        md5(
            COALESCE(
                string_agg(to_jsonb(c)::text, '' ORDER BY c.id),
                ''
            )
        )
      INTO consultation_count_before, consultation_fingerprint_before
      FROM public.consultations c;

    CREATE TABLE public.patient_dental_state (
        patient_id uuid NOT NULL,
        data text NOT NULL,
        version integer NOT NULL DEFAULT 1,
        updated_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,

        CONSTRAINT patient_dental_state_pkey
            PRIMARY KEY (patient_id),

        CONSTRAINT patient_dental_state_patient_id_fkey
            FOREIGN KEY (patient_id)
            REFERENCES public.patients(id)
            ON DELETE CASCADE,

        CONSTRAINT patient_dental_state_version_check
            CHECK (version >= 1),

        CONSTRAINT patient_dental_state_data_object_check
            CHECK (jsonb_typeof(data::jsonb) = 'object')
    );

    WITH ranked_consultations AS (
        SELECT
            c.patient_id,
            c.data,
            c.created_at,
            c.last_updated,
            c.id,
            row_number() OVER (
                PARTITION BY c.patient_id
                ORDER BY
                    c.created_at DESC NULLS LAST,
                    c.last_updated DESC NULLS LAST,
                    c.id DESC
            ) AS session_rank
        FROM public.consultations c
    )
    INSERT INTO public.patient_dental_state (
        patient_id,
        data,
        version,
        updated_at
    )
    SELECT
        patient_id,
        data,
        1,
        COALESCE(last_updated, created_at, CURRENT_TIMESTAMP)
    FROM ranked_consultations
    WHERE session_rank = 1;

    SELECT count(DISTINCT patient_id)
      INTO expected_state_count
      FROM public.consultations;

    SELECT count(*)
      INTO actual_state_count
      FROM public.patient_dental_state;

    IF actual_state_count <> expected_state_count THEN
        RAISE EXCEPTION
            'Dental-state backfill count mismatch: expected %, found %',
            expected_state_count,
            actual_state_count;
    END IF;

    WITH deterministic_latest AS (
        SELECT patient_id, data, created_at, last_updated
        FROM (
            SELECT
                c.patient_id,
                c.data,
                c.created_at,
                c.last_updated,
                c.id,
                row_number() OVER (
                    PARTITION BY c.patient_id
                    ORDER BY
                        c.created_at DESC NULLS LAST,
                        c.last_updated DESC NULLS LAST,
                        c.id DESC
                ) AS session_rank
            FROM public.consultations c
        ) ranked
        WHERE session_rank = 1
    )
    SELECT count(*)
      INTO mismatched_state_count
      FROM deterministic_latest latest
      FULL OUTER JOIN public.patient_dental_state state
        ON state.patient_id = latest.patient_id
     WHERE latest.patient_id IS NULL
        OR state.patient_id IS NULL
        OR state.data IS DISTINCT FROM latest.data
        OR state.version <> 1
        OR state.updated_at IS DISTINCT FROM
           COALESCE(latest.last_updated, latest.created_at, state.updated_at);

    IF mismatched_state_count <> 0 THEN
        RAISE EXCEPTION
            'One or more backfilled dental-state rows differ from their deterministic latest consultation snapshot';
    END IF;

    SELECT
        count(*),
        md5(
            COALESCE(
                string_agg(to_jsonb(c)::text, '' ORDER BY c.id),
                ''
            )
        )
      INTO consultation_count_after, consultation_fingerprint_after
      FROM public.consultations c;

    IF consultation_count_after <> consultation_count_before
       OR consultation_fingerprint_after IS DISTINCT FROM consultation_fingerprint_before THEN
        RAISE EXCEPTION
            'Consultation preservation check failed; the migration will be rolled back';
    END IF;
END
$migration$;

COMMIT;
