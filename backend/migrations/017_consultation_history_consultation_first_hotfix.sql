-- Migration 017: make consultations authoritative for Doctor Consultation History.
-- Reports remain optional enrichment; unmatched legacy reports remain visible.

BEGIN;

CREATE OR REPLACE FUNCTION public.list_doctor_consultation_history()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_caller_id uuid;
    v_caller_role text;
    v_result jsonb;
BEGIN
    SELECT actor.id, actor.role
      INTO v_caller_id, v_caller_role
      FROM security.consultation_history_actor() AS actor;
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'CONSULTATION_HISTORY_AUTHORIZATION_DENIED'
            USING ERRCODE = '42501';
    END IF;

    WITH eligible_consultations AS (
        SELECT consultation.*
          FROM public.consultations AS consultation
         WHERE v_caller_role = 'admin'
            OR consultation.doctor_id = v_caller_id
            OR (
                consultation.doctor_id IS NULL
                AND EXISTS (
                    SELECT 1
                      FROM public.appointments AS relationship_appointment
                     WHERE relationship_appointment.patient_id = consultation.patient_id
                       AND relationship_appointment.doctor_id = v_caller_id
                    UNION ALL
                    SELECT 1
                      FROM public.consultations AS owned_consultation
                     WHERE owned_consultation.patient_id = consultation.patient_id
                       AND owned_consultation.doctor_id = v_caller_id
                )
            )
    ),
    consultation_items AS (
        SELECT
            consultation.id AS consultation_id,
            consultation.patient_id,
            consultation.doctor_id,
            consultation.appointment_id,
            consultation.session_note,
            consultation.created_at AS consultation_created_at,
            consultation.last_updated AS consultation_last_updated,
            report.id AS report_id,
            report.tooth_id,
            report.tooth_status,
            report.symptoms,
            report.doctor_notes,
            report.ai_draft_report,
            report.final_medical_report,
            report.humanized_report,
            report.status AS report_status,
            report.created_at AS report_created_at,
            report.updated_at AS report_updated_at,
            coalesce(procedures.items, '[]'::jsonb) AS procedures
        FROM eligible_consultations AS consultation
        LEFT JOIN LATERAL (
            SELECT candidate.*
              FROM public.clinical_reports AS candidate
             WHERE candidate.patient_id = consultation.patient_id
               AND (
                   candidate.doctor_id IS NULL
                   OR consultation.doctor_id IS NULL
                   OR candidate.doctor_id = consultation.doctor_id
               )
               AND (
                   (
                       consultation.appointment_id IS NOT NULL
                       AND candidate.appointment_id = consultation.appointment_id
                   )
                   OR (
                       consultation.doctor_id IS NOT NULL
                       AND candidate.doctor_id = consultation.doctor_id
                       AND (
                           candidate.appointment_id IS NULL
                           OR consultation.appointment_id IS NULL
                       )
                       AND (
                           candidate.created_at IS NULL
                           OR consultation.created_at IS NULL
                           OR candidate.created_at >= consultation.created_at
                       )
                   )
                   OR (
                       (candidate.doctor_id IS NULL OR consultation.doctor_id IS NULL)
                       AND candidate.appointment_id IS NULL
                       AND consultation.appointment_id IS NULL
                       AND candidate.created_at::date =
                           coalesce(consultation.last_updated, consultation.created_at)::date
                   )
               )
             ORDER BY
                   CASE
                       WHEN consultation.appointment_id IS NOT NULL
                            AND candidate.appointment_id = consultation.appointment_id THEN 0
                       WHEN consultation.doctor_id IS NOT NULL
                            AND candidate.doctor_id = consultation.doctor_id THEN 1
                       ELSE 2
                   END,
                   candidate.created_at DESC NULLS LAST,
                   candidate.id DESC
             LIMIT 1
        ) AS report ON true
        LEFT JOIN LATERAL (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                       'id', selection.id,
                       'name', selection.procedure_name_snapshot,
                       'unitPrice', to_char(selection.unit_price_snapshot, 'FM999999999999990.00'),
                       'quantity', selection.quantity,
                       'lineTotal', to_char(selection.line_total, 'FM999999999999990.00')
                   ) ORDER BY selection.created_at, selection.id), '[]'::jsonb) AS items
              FROM public.consultation_procedures AS selection
             WHERE selection.consultation_id = consultation.id
        ) AS procedures ON true
    ),
    matched_report_ids AS (
        SELECT DISTINCT item.report_id
          FROM consultation_items AS item
         WHERE item.report_id IS NOT NULL
    ),
    history_rows AS (
        SELECT
            item.consultation_id::text AS stable_id,
            jsonb_build_object(
                'id', coalesce(item.report_id::text, 'consultation:' || item.consultation_id::text),
                'reportId', item.report_id,
                'patient_id', item.patient_id,
                'patient_name', coalesce(patient.name, 'Unknown'),
                'doctor_id', item.doctor_id,
                'appointment_id', item.appointment_id,
                'tooth_id', item.tooth_id,
                'tooth_status', item.tooth_status,
                'symptoms', security.consultation_history_json_array(item.symptoms),
                'doctor_notes', item.doctor_notes,
                'ai_draft_report', item.ai_draft_report,
                'final_medical_report', item.final_medical_report,
                'humanized_report', item.humanized_report,
                'status', coalesce(item.report_status, 'completed'),
                'created_at', item.consultation_created_at,
                'updated_at', item.consultation_last_updated,
                'report_created_at', item.report_created_at,
                'report_updated_at', item.report_updated_at,
                'consultationId', item.consultation_id,
                'sessionNote', item.session_note,
                'procedures', item.procedures,
                'reportOnly', false
            ) AS payload,
            item.consultation_last_updated AS sort_updated,
            item.consultation_created_at AS sort_created,
            0 AS sort_kind
          FROM consultation_items AS item
          LEFT JOIN public.patients AS patient ON patient.id = item.patient_id

        UNION ALL

        SELECT
            report.id::text AS stable_id,
            jsonb_build_object(
                'id', report.id,
                'reportId', report.id,
                'patient_id', report.patient_id,
                'patient_name', coalesce(patient.name, 'Unknown'),
                'doctor_id', report.doctor_id,
                'appointment_id', report.appointment_id,
                'tooth_id', report.tooth_id,
                'tooth_status', report.tooth_status,
                'symptoms', security.consultation_history_json_array(report.symptoms),
                'doctor_notes', report.doctor_notes,
                'ai_draft_report', report.ai_draft_report,
                'final_medical_report', report.final_medical_report,
                'humanized_report', report.humanized_report,
                'status', coalesce(report.status, 'completed'),
                'created_at', report.created_at,
                'updated_at', report.updated_at,
                'report_created_at', report.created_at,
                'report_updated_at', report.updated_at,
                'consultationId', NULL,
                'sessionNote', NULL,
                'procedures', '[]'::jsonb,
                'reportOnly', true
            ) AS payload,
            report.updated_at AS sort_updated,
            report.created_at AS sort_created,
            1 AS sort_kind
          FROM public.clinical_reports AS report
          LEFT JOIN public.patients AS patient ON patient.id = report.patient_id
         WHERE NOT EXISTS (
                   SELECT 1 FROM matched_report_ids AS matched
                    WHERE matched.report_id = report.id
               )
           AND (
               v_caller_role = 'admin'
               OR report.doctor_id = v_caller_id
               OR (
                   report.doctor_id IS NULL
                   AND EXISTS (
                       SELECT 1 FROM public.appointments AS relationship_appointment
                        WHERE relationship_appointment.patient_id = report.patient_id
                          AND relationship_appointment.doctor_id = v_caller_id
                       UNION ALL
                       SELECT 1 FROM public.consultations AS owned_consultation
                        WHERE owned_consultation.patient_id = report.patient_id
                          AND owned_consultation.doctor_id = v_caller_id
                   )
               )
           )
    )
    SELECT coalesce(jsonb_agg(history.payload
               ORDER BY history.sort_updated DESC NULLS LAST,
                        history.sort_created DESC NULLS LAST,
                        history.sort_kind,
                        history.stable_id DESC), '[]'::jsonb)
      INTO v_result
      FROM history_rows AS history;

    RETURN v_result;
END
$function$;

REVOKE ALL ON FUNCTION public.list_doctor_consultation_history() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_doctor_consultation_history() FROM anon;
GRANT EXECUTE ON FUNCTION public.list_doctor_consultation_history() TO authenticated;

COMMIT;
