-- C6 Consultation History: read-only Supabase projections.
-- Report generation, report persistence, and report mutations remain out of scope.

BEGIN;

REVOKE ALL ON TABLE public.clinical_reports FROM PUBLIC;
REVOKE ALL ON TABLE public.clinical_reports FROM anon;
REVOKE ALL ON TABLE public.clinical_reports FROM authenticated;
ALTER TABLE public.clinical_reports ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION security.consultation_history_actor()
RETURNS TABLE(id uuid, role text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT app_user.id, app_user.role
      FROM public.users AS app_user
     WHERE app_user.supabase_user_id = auth.uid()
       AND app_user.is_active = true
       AND app_user.approved_at IS NOT NULL
       AND app_user.role IN ('doctor', 'admin')
     LIMIT 1
$function$;

CREATE OR REPLACE FUNCTION security.consultation_history_json_array(p_value text)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_value jsonb;
BEGIN
    IF p_value IS NULL OR btrim(p_value) = '' THEN
        RETURN '[]'::jsonb;
    END IF;
    v_value := p_value::jsonb;
    IF jsonb_typeof(v_value) <> 'array' THEN
        RETURN '[]'::jsonb;
    END IF;
    RETURN v_value;
EXCEPTION WHEN invalid_text_representation THEN
    RETURN '[]'::jsonb;
END
$function$;

CREATE OR REPLACE FUNCTION public.get_patient_consultation_history(p_patient_id uuid)
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

    IF NOT EXISTS (SELECT 1 FROM public.patients AS patient WHERE patient.id = p_patient_id) THEN
        RAISE EXCEPTION 'CONSULTATION_HISTORY_PATIENT_NOT_FOUND'
            USING ERRCODE = 'P2101';
    END IF;

    -- A Doctor-patient relationship must be independently established before
    -- legacy NULL-owned consultations are included in the patient's clinical history.
    IF v_caller_role = 'doctor' AND NOT EXISTS (
        SELECT 1
          FROM public.appointments AS appointment
         WHERE appointment.patient_id = p_patient_id
           AND appointment.doctor_id = v_caller_id
        UNION ALL
        SELECT 1
          FROM public.consultations AS owned_consultation
         WHERE owned_consultation.patient_id = p_patient_id
           AND owned_consultation.doctor_id = v_caller_id
    ) THEN
        RAISE EXCEPTION 'CONSULTATION_HISTORY_AUTHORIZATION_DENIED'
            USING ERRCODE = '42501';
    END IF;

    SELECT coalesce(jsonb_agg(jsonb_build_object(
               'consultationId', consultation.id,
               'patientId', consultation.patient_id,
               'doctorId', consultation.doctor_id,
               'appointmentId', consultation.appointment_id,
               'toothData', consultation.data::jsonb,
               'sessionNote', consultation.session_note,
               'version', consultation.version,
               'createdAt', consultation.created_at,
               'lastUpdated', consultation.last_updated
           ) ORDER BY consultation.last_updated DESC NULLS LAST,
                      consultation.created_at DESC NULLS LAST,
                      consultation.id DESC), '[]'::jsonb)
      INTO v_result
      FROM public.consultations AS consultation
     WHERE consultation.patient_id = p_patient_id;

    RETURN v_result;
END
$function$;

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

    SELECT coalesce(jsonb_agg(jsonb_build_object(
               'id', report.id,
               'patient_id', report.patient_id,
               'patient_name', coalesce(patient.name, 'Unknown'),
               'doctor_id', report.doctor_id,
               'tooth_id', report.tooth_id,
               'tooth_status', report.tooth_status,
               'symptoms', security.consultation_history_json_array(report.symptoms),
               'doctor_notes', report.doctor_notes,
               'ai_draft_report', report.ai_draft_report,
               'final_medical_report', report.final_medical_report,
               'humanized_report', report.humanized_report,
               'status', report.status,
               'created_at', report.created_at,
               'updated_at', report.updated_at,
               'consultationId', matched_consultation.id,
               'sessionNote', matched_consultation.session_note,
               'procedures', coalesce(procedures.items, '[]'::jsonb)
           ) ORDER BY report.created_at DESC NULLS LAST, report.id DESC), '[]'::jsonb)
      INTO v_result
      FROM public.clinical_reports AS report
      LEFT JOIN public.patients AS patient ON patient.id = report.patient_id
      LEFT JOIN LATERAL (
          SELECT consultation.id, consultation.session_note
            FROM public.consultations AS consultation
           WHERE consultation.patient_id = report.patient_id
             AND (
                 (
                     report.appointment_id IS NOT NULL
                     AND consultation.appointment_id = report.appointment_id
                     AND (
                         report.doctor_id IS NULL
                         OR consultation.doctor_id IS NULL
                         OR consultation.doctor_id = report.doctor_id
                     )
                 )
                 OR (
                     report.doctor_id IS NOT NULL
                     AND consultation.doctor_id = report.doctor_id
                 )
                 OR consultation.doctor_id IS NULL
             )
             AND (
                 consultation.appointment_id = report.appointment_id
                 OR report.created_at IS NULL
                 OR consultation.created_at <= report.created_at
             )
           ORDER BY
                 CASE
                     WHEN report.appointment_id IS NOT NULL
                          AND consultation.appointment_id = report.appointment_id THEN 0
                     WHEN report.doctor_id IS NOT NULL
                          AND consultation.doctor_id = report.doctor_id THEN 1
                     ELSE 2
                 END,
                 consultation.last_updated DESC NULLS LAST,
                 consultation.created_at DESC NULLS LAST,
                 consultation.id DESC
           LIMIT 1
      ) AS matched_consultation ON true
      LEFT JOIN LATERAL (
          SELECT coalesce(jsonb_agg(jsonb_build_object(
                     'id', selection.id,
                     'name', selection.procedure_name_snapshot,
                     'unitPrice', to_char(selection.unit_price_snapshot, 'FM999999999999990.00'),
                     'quantity', selection.quantity,
                     'lineTotal', to_char(selection.line_total, 'FM999999999999990.00')
                 ) ORDER BY selection.created_at, selection.id), '[]'::jsonb) AS items
            FROM public.consultation_procedures AS selection
           WHERE selection.consultation_id = matched_consultation.id
      ) AS procedures ON true
     WHERE v_caller_role = 'admin' OR report.doctor_id = v_caller_id;

    RETURN v_result;
END
$function$;

REVOKE ALL ON FUNCTION security.consultation_history_actor() FROM PUBLIC;
REVOKE ALL ON FUNCTION security.consultation_history_json_array(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_patient_consultation_history(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_doctor_consultation_history() FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.get_patient_consultation_history(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.list_doctor_consultation_history() FROM anon;

GRANT EXECUTE ON FUNCTION public.get_patient_consultation_history(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_doctor_consultation_history() TO authenticated;

COMMIT;
