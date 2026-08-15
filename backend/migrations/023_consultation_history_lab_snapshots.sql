-- Migration 023: add immutable Lab snapshots to the contained Doctor history projection.
-- This migration does not alter Lab tables, clinical_reports, or Medical Report functions.
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
    -- The private base remains the sole authority for Doctor/Admin history rows.
    v_base := security.list_doctor_consultation_history_base();

    SELECT coalesce(jsonb_agg(item.value || jsonb_build_object(
               'clinicalFindings', consultation.clinical_findings_snapshot,
               'reportSnapshot', report.report_snapshot,
               'snapshotVersion', report.snapshot_version,
               'reviewedAt', report.reviewed_at,
               'finalizedAt', report.finalized_at,
               'labNote', consultation.lab_note,
               'labItems', coalesce(lab_snapshot.items, '[]'::jsonb)
           ) ORDER BY item.ordinality), '[]'::jsonb)
      INTO v_result
      FROM jsonb_array_elements(v_base) WITH ORDINALITY AS item(value, ordinality)
      LEFT JOIN public.consultations AS consultation
        ON consultation.id = nullif(item.value ->> 'consultationId', '')::uuid
      LEFT JOIN public.clinical_reports AS report
        ON report.id = nullif(item.value ->> 'reportId', '')::uuid
      LEFT JOIN LATERAL (
          SELECT coalesce(jsonb_agg(jsonb_build_object(
                     'labId', lab_item.lab_id,
                     'labProductId', lab_item.lab_product_id,
                     'labName', lab_item.lab_name_snapshot,
                     'productName', lab_item.product_name_snapshot,
                     'unitPrice', lab_item.unit_price_snapshot,
                     'quantity', lab_item.quantity,
                     'totalAmount', lab_item.total_amount
                 ) ORDER BY lab_item.created_at,
                            lower(lab_item.lab_name_snapshot),
                            lower(lab_item.product_name_snapshot),
                            lab_item.id), '[]'::jsonb) AS items
            FROM public.consultation_lab_items AS lab_item
           WHERE lab_item.consultation_id=consultation.id
      ) AS lab_snapshot ON true;

    RETURN v_result;
END
$function$;

REVOKE ALL ON FUNCTION public.list_doctor_consultation_history() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_doctor_consultation_history() FROM anon;
GRANT EXECUTE ON FUNCTION public.list_doctor_consultation_history() TO authenticated;

COMMIT;
