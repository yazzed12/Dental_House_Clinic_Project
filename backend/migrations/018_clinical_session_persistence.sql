-- Migration 018: consultation symptom snapshots and Supabase report persistence.
-- AI generation, humanization, and PDF generation are intentionally excluded.

BEGIN;

ALTER TABLE public.consultations
    ADD COLUMN symptoms_snapshot jsonb NULL;
ALTER TABLE public.consultations
    ADD CONSTRAINT consultations_symptoms_snapshot_array_ck
    CHECK (symptoms_snapshot IS NULL OR jsonb_typeof(symptoms_snapshot) = 'array');

ALTER TABLE public.clinical_reports
    ADD COLUMN consultation_id uuid NULL;
ALTER TABLE public.clinical_reports
    ADD CONSTRAINT clinical_reports_consultation_id_fk
    FOREIGN KEY (consultation_id) REFERENCES public.consultations(id);
CREATE INDEX clinical_reports_consultation_id_created_idx
    ON public.clinical_reports (consultation_id, created_at DESC, id DESC);

DROP POLICY IF EXISTS "Allow clinic staff full access"
ON public.clinical_reports;

DROP POLICY IF EXISTS "Allow initial data migration"
ON public.clinical_reports;

ALTER FUNCTION public.get_or_initialize_consultation(uuid)
    RENAME TO get_or_initialize_consultation_base;
ALTER FUNCTION public.get_or_initialize_consultation_base(uuid)
    SET SCHEMA security;
REVOKE ALL ON FUNCTION security.get_or_initialize_consultation_base(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION security.get_or_initialize_consultation_base(uuid) FROM anon;
REVOKE ALL ON FUNCTION security.get_or_initialize_consultation_base(uuid) FROM authenticated;

CREATE OR REPLACE FUNCTION public.get_or_initialize_consultation(p_patient_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_result jsonb;
    v_symptoms jsonb := '[]'::jsonb;
BEGIN
    v_result := security.get_or_initialize_consultation_base(p_patient_id);
    IF v_result ->> 'consultationId' IS NOT NULL THEN
        SELECT consultation.symptoms_snapshot
          INTO v_symptoms
          FROM public.consultations AS consultation
         WHERE consultation.id = (v_result ->> 'consultationId')::uuid;
    END IF;
    RETURN v_result || jsonb_build_object('symptoms', coalesce(v_symptoms, '[]'::jsonb));
END
$function$;

CREATE OR REPLACE FUNCTION public.save_current_consultation(
    p_patient_id uuid,
    p_tooth_data jsonb,
    p_version integer,
    p_dental_state_version integer,
    p_session_note text,
    p_session_note_supplied boolean,
    p_symptoms_snapshot jsonb,
    p_symptoms_supplied boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_result jsonb;
    v_consultation_id uuid;
    v_symptoms jsonb;
BEGIN
    IF p_symptoms_supplied AND (
        p_symptoms_snapshot IS NULL
        OR jsonb_typeof(p_symptoms_snapshot) <> 'array'
        OR EXISTS (
            SELECT 1 FROM jsonb_array_elements(p_symptoms_snapshot) AS symptom
             WHERE jsonb_typeof(symptom) <> 'string'
                OR btrim(symptom #>> '{}') = ''
                OR length(symptom #>> '{}') > 250
        )
        OR (SELECT count(*) FROM jsonb_array_elements(p_symptoms_snapshot)) > 100
        OR (SELECT count(*) FROM jsonb_array_elements(p_symptoms_snapshot)) <>
           (SELECT count(DISTINCT lower(btrim(symptom #>> '{}')))
              FROM jsonb_array_elements(p_symptoms_snapshot) AS symptom)
    ) THEN
        RAISE EXCEPTION 'CONSULTATION_SYMPTOMS_INVALID' USING ERRCODE = '22023';
    END IF;

    -- The deployed consultation function performs the authoritative appointment
    -- selection, ownership checks, row locks, version checks, dental-state write,
    -- session-note write, version increment, and audit insert in this transaction.
    v_result := public.save_current_consultation(
        p_patient_id, p_tooth_data, p_version, p_dental_state_version,
        p_session_note, p_session_note_supplied
    );
    v_consultation_id := (v_result ->> 'consultationId')::uuid;

    IF p_symptoms_supplied THEN
        UPDATE public.consultations AS consultation
           SET symptoms_snapshot = p_symptoms_snapshot
         WHERE consultation.id = v_consultation_id;
    END IF;
    SELECT consultation.symptoms_snapshot
      INTO v_symptoms
      FROM public.consultations AS consultation
     WHERE consultation.id = v_consultation_id;

    RETURN v_result || jsonb_build_object('symptoms', coalesce(v_symptoms, '[]'::jsonb));
END
$function$;

CREATE OR REPLACE FUNCTION security.clinical_report_actor()
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

CREATE OR REPLACE FUNCTION public.save_clinical_report(
    p_patient_id uuid,
    p_consultation_id uuid,
    p_appointment_id uuid,
    p_tooth_id text,
    p_tooth_status text,
    p_symptoms jsonb,
    p_doctor_notes text,
    p_ai_draft_report text,
    p_final_medical_report text,
    p_humanized_report text,
    p_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_actor_id uuid;
    v_actor_role text;
    v_consultation public.consultations%ROWTYPE;
    v_report public.clinical_reports%ROWTYPE;
BEGIN
    SELECT actor.id, actor.role INTO v_actor_id, v_actor_role
      FROM security.clinical_report_actor() AS actor;
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'REPORT_AUTHORIZATION_DENIED' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.patients AS patient WHERE patient.id = p_patient_id) THEN
        RAISE EXCEPTION 'REPORT_PATIENT_NOT_FOUND' USING ERRCODE = 'P2201';
    END IF;
    SELECT consultation.* INTO v_consultation
      FROM public.consultations AS consultation
     WHERE consultation.id = p_consultation_id
     FOR UPDATE;
    IF v_consultation.id IS NULL THEN
        RAISE EXCEPTION 'REPORT_CONSULTATION_NOT_FOUND' USING ERRCODE = 'P2202';
    END IF;
    IF v_consultation.patient_id IS DISTINCT FROM p_patient_id
       OR v_consultation.appointment_id IS DISTINCT FROM p_appointment_id THEN
        RAISE EXCEPTION 'REPORT_LINKAGE_MISMATCH' USING ERRCODE = 'P2204';
    END IF;
    IF v_consultation.doctor_id IS NULL
       OR (v_actor_role = 'doctor' AND v_consultation.doctor_id <> v_actor_id) THEN
        RAISE EXCEPTION 'REPORT_AUTHORIZATION_DENIED' USING ERRCODE = '42501';
    END IF;
    IF p_final_medical_report IS NULL OR btrim(p_final_medical_report) = ''
       OR p_status NOT IN ('draft', 'approved', 'finalized')
       OR p_symptoms IS NULL OR jsonb_typeof(p_symptoms) <> 'array'
       OR p_symptoms IS DISTINCT FROM v_consultation.symptoms_snapshot THEN
        RAISE EXCEPTION 'REPORT_PAYLOAD_INVALID' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.clinical_reports (
        id, patient_id, doctor_id, appointment_id, consultation_id,
        tooth_id, tooth_status, symptoms, doctor_notes, ai_draft_report,
        final_medical_report, humanized_report, status, created_at, updated_at
    ) VALUES (
        gen_random_uuid(), p_patient_id, v_consultation.doctor_id,
        v_consultation.appointment_id, v_consultation.id,
        p_tooth_id, p_tooth_status, p_symptoms::text, coalesce(p_doctor_notes, ''),
        coalesce(p_ai_draft_report, ''), p_final_medical_report,
        coalesce(p_humanized_report, ''), p_status, now(), now()
    ) RETURNING * INTO v_report;

    INSERT INTO public.logs (id, message, doctor_id, patient_id, created_at)
    VALUES (gen_random_uuid(),
            format('Clinical report saved for patient %s', p_patient_id),
            v_actor_id, p_patient_id, now());

    RETURN jsonb_build_object(
        'id', v_report.id, 'patient_id', v_report.patient_id,
        'consultation_id', v_report.consultation_id,
        'appointment_id', v_report.appointment_id,
        'status', v_report.status, 'tooth_id', v_report.tooth_id,
        'created_at', v_report.created_at
    );
END
$function$;

CREATE OR REPLACE FUNCTION public.update_clinical_report(p_report_id uuid, p_updates jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_actor_id uuid;
    v_actor_role text;
    v_report public.clinical_reports%ROWTYPE;
    v_allowed text[] := ARRAY[
        'final_medical_report', 'humanized_report', 'status', 'doctor_notes',
        'tooth_id', 'tooth_status', 'symptoms'
    ];
    v_key text;
    v_symptoms jsonb;
BEGIN
    SELECT actor.id, actor.role INTO v_actor_id, v_actor_role
      FROM security.clinical_report_actor() AS actor;
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'REPORT_AUTHORIZATION_DENIED' USING ERRCODE = '42501';
    END IF;
    SELECT report.* INTO v_report
      FROM public.clinical_reports AS report
     WHERE report.id = p_report_id
     FOR UPDATE;
    IF v_report.id IS NULL THEN
        RAISE EXCEPTION 'REPORT_NOT_FOUND' USING ERRCODE = 'P2203';
    END IF;
    IF v_report.doctor_id IS NULL
       OR (v_actor_role = 'doctor' AND v_report.doctor_id <> v_actor_id) THEN
        RAISE EXCEPTION 'REPORT_AUTHORIZATION_DENIED' USING ERRCODE = '42501';
    END IF;
    IF p_updates IS NULL OR jsonb_typeof(p_updates) <> 'object' THEN
        RAISE EXCEPTION 'REPORT_PAYLOAD_INVALID' USING ERRCODE = '22023';
    END IF;
    FOR v_key IN SELECT jsonb_object_keys(p_updates) LOOP
        IF NOT (v_key = ANY(v_allowed)) THEN
            RAISE EXCEPTION 'REPORT_UPDATE_FIELD_UNSUPPORTED' USING ERRCODE = '22023';
        END IF;
    END LOOP;
    IF p_updates ? 'status' AND p_updates ->> 'status' NOT IN ('draft', 'approved', 'finalized') THEN
        RAISE EXCEPTION 'REPORT_STATUS_INVALID' USING ERRCODE = '22023';
    END IF;
    IF p_updates ? 'final_medical_report'
       AND btrim(coalesce(p_updates ->> 'final_medical_report', '')) = '' THEN
        RAISE EXCEPTION 'REPORT_FINAL_TEXT_REQUIRED' USING ERRCODE = '22023';
    END IF;
    IF p_updates ? 'symptoms' THEN
        v_symptoms := p_updates -> 'symptoms';
        IF v_symptoms IS NULL OR jsonb_typeof(v_symptoms) <> 'array' THEN
            RAISE EXCEPTION 'REPORT_SYMPTOMS_INVALID' USING ERRCODE = '22023';
        END IF;
    END IF;

    UPDATE public.clinical_reports AS report
       SET final_medical_report = CASE WHEN p_updates ? 'final_medical_report' THEN p_updates ->> 'final_medical_report' ELSE report.final_medical_report END,
           humanized_report = CASE WHEN p_updates ? 'humanized_report' THEN p_updates ->> 'humanized_report' ELSE report.humanized_report END,
           status = CASE WHEN p_updates ? 'status' THEN p_updates ->> 'status' ELSE report.status END,
           doctor_notes = CASE WHEN p_updates ? 'doctor_notes' THEN p_updates ->> 'doctor_notes' ELSE report.doctor_notes END,
           tooth_id = CASE WHEN p_updates ? 'tooth_id' THEN p_updates ->> 'tooth_id' ELSE report.tooth_id END,
           tooth_status = CASE WHEN p_updates ? 'tooth_status' THEN p_updates ->> 'tooth_status' ELSE report.tooth_status END,
           symptoms = CASE WHEN p_updates ? 'symptoms' THEN (p_updates -> 'symptoms')::text ELSE report.symptoms END,
           updated_at = now()
     WHERE report.id = p_report_id
     RETURNING * INTO v_report;

    RETURN jsonb_build_object('id', v_report.id, 'status', v_report.status,
                              'updated_at', v_report.updated_at);
END
$function$;

CREATE OR REPLACE FUNCTION public.get_patient_clinical_reports(p_patient_id uuid)
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
      FROM security.clinical_report_actor() AS actor;
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'REPORT_AUTHORIZATION_DENIED' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.patients AS patient WHERE patient.id = p_patient_id) THEN
        RAISE EXCEPTION 'REPORT_PATIENT_NOT_FOUND' USING ERRCODE = 'P2201';
    END IF;
    IF v_actor_role = 'doctor' AND NOT EXISTS (
        SELECT 1 FROM public.appointments AS appointment
         WHERE appointment.patient_id = p_patient_id AND appointment.doctor_id = v_actor_id
        UNION ALL
        SELECT 1 FROM public.consultations AS consultation
         WHERE consultation.patient_id = p_patient_id AND consultation.doctor_id = v_actor_id
    ) THEN
        RAISE EXCEPTION 'REPORT_AUTHORIZATION_DENIED' USING ERRCODE = '42501';
    END IF;

    SELECT coalesce(jsonb_agg(jsonb_build_object(
               'id', report.id, 'patient_id', report.patient_id,
               'doctor_id', report.doctor_id, 'consultation_id', report.consultation_id,
               'appointment_id', report.appointment_id,
               'tooth_id', report.tooth_id, 'tooth_status', report.tooth_status,
               'symptoms', security.consultation_history_json_array(report.symptoms),
               'doctor_notes', report.doctor_notes,
               'ai_draft_report', report.ai_draft_report,
               'final_medical_report', report.final_medical_report,
               'humanized_report', report.humanized_report,
               'status', report.status, 'created_at', report.created_at,
               'updated_at', report.updated_at,
               'doctor', coalesce(doctor.full_name, doctor.username, 'Unknown'),
               'pdf_url', CASE WHEN report.pdf_path IS NULL THEN NULL
                               ELSE '/api/reports/' || report.id::text || '/download' END
           ) ORDER BY report.created_at DESC NULLS LAST, report.id DESC), '[]'::jsonb)
      INTO v_result
      FROM public.clinical_reports AS report
      LEFT JOIN public.users AS doctor ON doctor.id = report.doctor_id
     WHERE report.patient_id = p_patient_id;
    RETURN v_result;
END
$function$;

-- Replace Migration 017's projection so consultation-session symptoms are
-- authoritative and the new direct consultation_id report link ranks first.
CREATE OR REPLACE FUNCTION public.list_doctor_consultation_history()
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
            OR consultation.doctor_id = v_actor_id
            OR (consultation.doctor_id IS NULL AND EXISTS (
                SELECT 1 FROM public.appointments AS appointment
                 WHERE appointment.patient_id = consultation.patient_id
                   AND appointment.doctor_id = v_actor_id
                UNION ALL
                SELECT 1 FROM public.consultations AS owned
                 WHERE owned.patient_id = consultation.patient_id
                   AND owned.doctor_id = v_actor_id
            ))
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
                   'symptoms', CASE
                       WHEN consultation.symptoms_snapshot IS NOT NULL
                           THEN consultation.symptoms_snapshot
                       ELSE security.consultation_history_json_array(consultation.report_symptoms)
                   END,
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
           AND (v_actor_role = 'admin' OR report.doctor_id = v_actor_id
                OR (report.doctor_id IS NULL AND EXISTS (
                    SELECT 1 FROM public.appointments AS appointment
                     WHERE appointment.patient_id = report.patient_id
                       AND appointment.doctor_id = v_actor_id
                    UNION ALL
                    SELECT 1 FROM public.consultations AS owned
                     WHERE owned.patient_id = report.patient_id AND owned.doctor_id = v_actor_id
                )))
    )
    SELECT coalesce(jsonb_agg(history.payload ORDER BY
               history.sort_updated DESC NULLS LAST,
               history.sort_created DESC NULLS LAST,
               history.sort_kind, history.stable_id DESC), '[]'::jsonb)
      INTO v_result FROM history;
    RETURN v_result;
END
$function$;

REVOKE ALL ON TABLE public.clinical_reports FROM PUBLIC, anon, authenticated;
ALTER TABLE public.clinical_reports ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON FUNCTION security.clinical_report_actor() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_or_initialize_consultation(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_or_initialize_consultation(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_or_initialize_consultation(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.save_current_consultation(uuid, jsonb, integer, integer, text, boolean, jsonb, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.save_current_consultation(uuid, jsonb, integer, integer, text, boolean, jsonb, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.save_current_consultation(uuid, jsonb, integer, integer, text, boolean, jsonb, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.save_current_consultation(uuid, jsonb, integer, integer, text, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.save_current_consultation(uuid, jsonb, integer, integer, text, boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.save_current_consultation(uuid, jsonb, integer, integer, text, boolean) FROM authenticated;
REVOKE ALL ON FUNCTION public.save_clinical_report(uuid, uuid, uuid, text, text, jsonb, text, text, text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.save_clinical_report(uuid, uuid, uuid, text, text, jsonb, text, text, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.save_clinical_report(uuid, uuid, uuid, text, text, jsonb, text, text, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.update_clinical_report(uuid, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_clinical_report(uuid, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_clinical_report(uuid, jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.get_patient_clinical_reports(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_patient_clinical_reports(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_patient_clinical_reports(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.list_doctor_consultation_history() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_doctor_consultation_history() FROM anon;
GRANT EXECUTE ON FUNCTION public.list_doctor_consultation_history() TO authenticated;

COMMIT;
