-- Migration 021: surface report snapshot metadata through the already-contained
-- Doctor history projection. No clinical report data is mutated or backfilled.
BEGIN;

CREATE OR REPLACE FUNCTION public.list_doctor_consultation_history()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_base jsonb;
    v_result jsonb;
BEGIN
    -- This private base function retains the authoritative Doctor/Admin
    -- relationship and report-only legacy containment implemented by 016-019.
    v_base := security.list_doctor_consultation_history_base();

    SELECT coalesce(jsonb_agg(item.value || jsonb_build_object(
               'clinicalFindings', consultation.clinical_findings_snapshot,
               'reportSnapshot', report.report_snapshot,
               'snapshotVersion', report.snapshot_version,
               'reviewedAt', report.reviewed_at,
               'finalizedAt', report.finalized_at
           ) ORDER BY item.ordinality), '[]'::jsonb)
      INTO v_result
      FROM jsonb_array_elements(v_base) WITH ORDINALITY AS item(value, ordinality)
      LEFT JOIN public.consultations AS consultation
        ON consultation.id = nullif(item.value ->> 'consultationId', '')::uuid
      LEFT JOIN public.clinical_reports AS report
        ON report.id = nullif(item.value ->> 'reportId', '')::uuid;

    RETURN v_result;
END
$function$;

REVOKE ALL ON FUNCTION public.list_doctor_consultation_history() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_doctor_consultation_history() FROM anon;
GRANT EXECUTE ON FUNCTION public.list_doctor_consultation_history() TO authenticated;

COMMIT;
