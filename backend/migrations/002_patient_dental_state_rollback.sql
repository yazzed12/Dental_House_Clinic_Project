BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

DO $rollback_preflight$
BEGIN
    IF to_regclass('public.patient_dental_state') IS NULL THEN
        RAISE EXCEPTION
            'public.patient_dental_state does not exist; there is nothing to roll back';
    END IF;
END
$rollback_preflight$;

LOCK TABLE public.consultations IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.patient_dental_state IN SHARE ROW EXCLUSIVE MODE;

DO $rollback_guard$
DECLARE
    mismatched_state_count bigint;
BEGIN

    IF EXISTS (
        SELECT 1
        FROM public.patient_dental_state
        WHERE version <> 1
    ) THEN
        RAISE EXCEPTION
            'Rollback refused: patient dental-state versions show post-backfill application writes';
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
        OR state.updated_at IS DISTINCT FROM
           COALESCE(latest.last_updated, latest.created_at, state.updated_at);

    IF mismatched_state_count <> 0 THEN
        RAISE EXCEPTION
            'Rollback refused: current dental state has diverged from the deterministic backfill';
    END IF;
END
$rollback_guard$;

DROP TABLE public.patient_dental_state;

COMMIT;
