BEGIN TRANSACTION READ ONLY;

SELECT to_regclass('public.patient_dental_state') AS dental_state_table;

SELECT
    column_name,
    data_type,
    udt_name,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'patient_dental_state'
ORDER BY ordinal_position;

SELECT
    c.conname,
    c.contype,
    pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c
WHERE c.conrelid = 'public.patient_dental_state'::regclass
ORDER BY c.conname;

SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'patient_dental_state'
ORDER BY indexname;

SELECT
    (SELECT count(*) FROM public.patients) AS patient_rows,
    (SELECT count(*) FROM public.consultations) AS consultation_rows,
    (SELECT count(DISTINCT patient_id) FROM public.consultations)
        AS patients_with_consultations,
    (SELECT count(*) FROM public.patient_dental_state) AS dental_state_rows,
    (SELECT count(*)
       FROM public.patients p
      WHERE NOT EXISTS (
          SELECT 1
          FROM public.consultations c
          WHERE c.patient_id = p.id
      )) AS patients_without_consultations;

SELECT
    count(*) FILTER (WHERE version < 1) AS invalid_versions,
    count(*) FILTER (WHERE data IS NULL) AS null_data,
    count(*) FILTER (WHERE jsonb_typeof(data::jsonb) <> 'object')
        AS non_object_data,
    count(*) - count(DISTINCT patient_id) AS duplicate_patient_rows
FROM public.patient_dental_state;

SELECT count(*) AS orphan_patient_references
FROM public.patient_dental_state state
LEFT JOIN public.patients patient
  ON patient.id = state.patient_id
WHERE patient.id IS NULL;

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
SELECT count(*) AS mismatched_latest_snapshots
FROM deterministic_latest latest
FULL OUTER JOIN public.patient_dental_state state
  ON state.patient_id = latest.patient_id
WHERE latest.patient_id IS NULL
   OR state.patient_id IS NULL
   OR state.data IS DISTINCT FROM latest.data
   OR state.version <> 1
   OR state.updated_at IS DISTINCT FROM
      COALESCE(latest.last_updated, latest.created_at, state.updated_at);

SELECT
    count(*) AS current_consultation_rows,
    md5(
        COALESCE(
            string_agg(to_jsonb(c)::text, '' ORDER BY c.id),
            ''
        )
    ) AS current_consultation_fingerprint,
    count(*) = 21
        AND md5(
            COALESCE(
                string_agg(to_jsonb(c)::text, '' ORDER BY c.id),
                ''
            )
        ) = 'a1cf24544799b9cb17d12afd6d697d93'
        AS matches_2026_08_09_preflight_snapshot
FROM public.consultations c;

ROLLBACK;
