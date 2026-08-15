-- Migration 028: require exact authenticated-Doctor ownership for every Doctor history row.
-- Admin behavior and the Migration 023 enrichment wrapper remain unchanged.
BEGIN;

CREATE OR REPLACE FUNCTION security.list_doctor_consultation_history_base()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_actor_id uuid;
    v_actor_role text;
    v_result jsonb;
BEGIN
    SELECT actor.id, actor.role INTO v_actor_id, v_actor_role
      FROM security.consultation_history_actor() AS actor;
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'CONSULTATION_HISTORY_AUTHORIZATION_DENIED' USING ERRCODE = '42501';
    END IF;

    WITH eligible AS (
        SELECT consultation.*
          FROM public.consultations AS consultation
         WHERE v_actor_role = 'admin'
            OR (v_actor_role = 'doctor' AND consultation.doctor_id = v_actor_id)
    ), consultation_rows AS (
        SELECT consultation.*, matched.id AS report_id,
               matched.tooth_id, matched.tooth_status, matched.symptoms AS report_symptoms,
               matched.doctor_notes, matched.ai_draft_report,
               matched.final_medical_report, matched.humanized_report,
               matched.status AS report_status, matched.created_at AS report_created_at,
               matched.updated_at AS report_updated_at,
               coalesce(procedures.items, '[]'::jsonb) AS procedures
          FROM eligible AS consultation
          LEFT JOIN LATERAL (
              SELECT report.*
                FROM public.clinical_reports AS report
               WHERE report.patient_id = consultation.patient_id
                 AND (v_actor_role = 'admin' OR report.doctor_id = v_actor_id)
                 AND (report.doctor_id IS NULL OR consultation.doctor_id IS NULL
                      OR report.doctor_id = consultation.doctor_id)
                 AND (
                     report.consultation_id = consultation.id
                     OR (report.consultation_id IS NULL
                         AND consultation.appointment_id IS NOT NULL
                         AND report.appointment_id = consultation.appointment_id)
                     OR (report.consultation_id IS NULL
                         AND consultation.doctor_id IS NOT NULL
                         AND report.doctor_id = consultation.doctor_id
                         AND (report.appointment_id IS NULL OR consultation.appointment_id IS NULL)
                         AND (report.created_at IS NULL OR consultation.created_at IS NULL
                              OR report.created_at >= consultation.created_at))
                     OR (report.consultation_id IS NULL
                         AND (report.doctor_id IS NULL OR consultation.doctor_id IS NULL)
                         AND report.appointment_id IS NULL
                         AND consultation.appointment_id IS NULL
                         AND report.created_at::date =
                             coalesce(consultation.last_updated, consultation.created_at)::date)
                 )
               ORDER BY CASE
                          WHEN report.consultation_id = consultation.id THEN -1
                          WHEN consultation.appointment_id IS NOT NULL
                           AND report.appointment_id = consultation.appointment_id THEN 0
                          WHEN consultation.doctor_id IS NOT NULL
                           AND report.doctor_id = consultation.doctor_id THEN 1
                          ELSE 2
                        END,
                        report.created_at DESC NULLS LAST, report.id DESC
               LIMIT 1
          ) AS matched ON true
          LEFT JOIN LATERAL (
              SELECT coalesce(jsonb_agg(jsonb_build_object(
                         'id', selection.id, 'name', selection.procedure_name_snapshot,
                         'unitPrice', to_char(selection.unit_price_snapshot, 'FM999999999999990.00'),
                         'quantity', selection.quantity,
                         'lineTotal', to_char(selection.line_total, 'FM999999999999990.00')
                     ) ORDER BY selection.created_at, selection.id), '[]'::jsonb) AS items
                FROM public.consultation_procedures AS selection
               WHERE selection.consultation_id = consultation.id
          ) AS procedures ON true
    ), used_reports AS (
        SELECT DISTINCT row.report_id FROM consultation_rows AS row WHERE row.report_id IS NOT NULL
    ), history AS (
        SELECT consultation.id::text AS stable_id,
               consultation.last_updated AS sort_updated,
               consultation.created_at AS sort_created,
               0 AS sort_kind,
               jsonb_build_object(
                   'id', coalesce(consultation.report_id::text, 'consultation:' || consultation.id::text),
                   'reportId', consultation.report_id,
                   'patient_id', consultation.patient_id,
                   'patient_name', coalesce(patient.name, 'Unknown'),
                   'doctor_id', consultation.doctor_id,
                   'appointment_id', consultation.appointment_id,
                   'tooth_id', consultation.tooth_id,
                   'tooth_status', consultation.tooth_status,
                   'symptoms', CASE WHEN consultation.symptoms_snapshot IS NOT NULL
                         THEN consultation.symptoms_snapshot
                         ELSE security.consultation_history_json_array(consultation.report_symptoms) END,
                   'doctor_notes', consultation.doctor_notes,
                   'ai_draft_report', consultation.ai_draft_report,
                   'final_medical_report', consultation.final_medical_report,
                   'humanized_report', consultation.humanized_report,
                   'status', coalesce(consultation.report_status, 'completed'),
                   'created_at', consultation.created_at,
                   'updated_at', consultation.last_updated,
                   'report_created_at', consultation.report_created_at,
                   'report_updated_at', consultation.report_updated_at,
                   'consultationId', consultation.id,
                   'sessionNote', consultation.session_note,
                   'procedures', consultation.procedures,
                   'reportOnly', false
               ) AS payload
          FROM consultation_rows AS consultation
          LEFT JOIN public.patients AS patient ON patient.id = consultation.patient_id
        UNION ALL
        SELECT report.id::text, report.updated_at, report.created_at, 1,
               jsonb_build_object(
                   'id', report.id, 'reportId', report.id,
                   'patient_id', report.patient_id,
                   'patient_name', coalesce(patient.name, 'Unknown'),
                   'doctor_id', report.doctor_id, 'appointment_id', report.appointment_id,
                   'tooth_id', report.tooth_id, 'tooth_status', report.tooth_status,
                   'symptoms', security.consultation_history_json_array(report.symptoms),
                   'doctor_notes', report.doctor_notes,
                   'ai_draft_report', report.ai_draft_report,
                   'final_medical_report', report.final_medical_report,
                   'humanized_report', report.humanized_report,
                   'status', coalesce(report.status, 'completed'),
                   'created_at', report.created_at, 'updated_at', report.updated_at,
                   'consultationId', NULL, 'sessionNote', NULL,
                   'procedures', '[]'::jsonb, 'reportOnly', true
               )
          FROM public.clinical_reports AS report
          LEFT JOIN public.patients AS patient ON patient.id = report.patient_id
         WHERE NOT EXISTS (SELECT 1 FROM used_reports AS used WHERE used.report_id = report.id)
           AND (v_actor_role = 'admin'
                OR (v_actor_role = 'doctor' AND report.doctor_id = v_actor_id))
    )
    SELECT coalesce(jsonb_agg(history.payload ORDER BY
               history.sort_updated DESC NULLS LAST,
               history.sort_created DESC NULLS LAST,
               history.sort_kind, history.stable_id DESC), '[]'::jsonb)
      INTO v_result FROM history;
    RETURN v_result;
END
$function$;

REVOKE ALL ON FUNCTION security.list_doctor_consultation_history_base() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.list_doctor_consultation_history() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_doctor_consultation_history() FROM anon;
GRANT EXECUTE ON FUNCTION public.list_doctor_consultation_history() TO authenticated;

COMMIT;
