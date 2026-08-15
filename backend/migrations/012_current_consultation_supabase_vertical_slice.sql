-- C6 current-consultation Supabase vertical slice.
-- This migration intentionally does not migrate consultation history, reports,
-- procedures, or billing.

BEGIN;

DROP POLICY IF EXISTS "Allow all" ON public.consultations;
DROP POLICY IF EXISTS "Allow clinic staff to read consultations" ON public.consultations;
DROP POLICY IF EXISTS "Allow clinic staff to insert consultations" ON public.consultations;
DROP POLICY IF EXISTS "Allow clinic staff to update consultations" ON public.consultations;
DROP POLICY IF EXISTS "Allow clinic staff to manage consultations" ON public.consultations;
DROP POLICY IF EXISTS "Allow clinic staff full access" ON public.consultations;
DROP POLICY IF EXISTS "Allow initial data migration" ON public.consultations;

DROP POLICY IF EXISTS "Allow all" ON public.patient_dental_state;
DROP POLICY IF EXISTS "Allow clinic staff to read patient dental state" ON public.patient_dental_state;
DROP POLICY IF EXISTS "Allow clinic staff to manage patient dental state" ON public.patient_dental_state;
DROP POLICY IF EXISTS "Allow initial data migration" ON public.patient_dental_state;

REVOKE ALL ON TABLE public.consultations FROM PUBLIC;
REVOKE ALL ON TABLE public.consultations FROM anon;
REVOKE ALL ON TABLE public.consultations FROM authenticated;
ALTER TABLE public.consultations ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.patient_dental_state FROM PUBLIC;
REVOKE ALL ON TABLE public.patient_dental_state FROM anon;
REVOKE ALL ON TABLE public.patient_dental_state FROM authenticated;
ALTER TABLE public.patient_dental_state ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.get_or_initialize_consultation(
    p_patient_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_caller_id uuid;
    v_caller_role text;
    v_appointment public.appointments%ROWTYPE;
    v_consultation public.consultations%ROWTYPE;
    v_dental_state public.patient_dental_state%ROWTYPE;
    v_last_note public.consultations%ROWTYPE;
BEGIN
    SELECT app_user.id, app_user.role
      INTO v_caller_id, v_caller_role
      FROM public.users AS app_user
     WHERE app_user.supabase_user_id = auth.uid()
       AND app_user.is_active = true
       AND app_user.approved_at IS NOT NULL
       AND app_user.role IN ('doctor', 'admin')
     LIMIT 1;

    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'CONSULTATION_AUTHORIZATION_DENIED'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.patients AS patient WHERE patient.id = p_patient_id
    ) THEN
        RAISE EXCEPTION 'CONSULTATION_PATIENT_NOT_FOUND'
            USING ERRCODE = 'P2001';
    END IF;

    SELECT appointment.*
      INTO v_appointment
      FROM public.appointments AS appointment
     WHERE appointment.patient_id = p_patient_id
       AND (
           appointment.date = CURRENT_DATE
           OR appointment.appointment_date = CURRENT_DATE
       )
       AND appointment.status::text IN ('pending', 'confirmed')
       AND appointment.doctor_id IS NOT NULL
       AND (v_caller_role = 'admin' OR appointment.doctor_id = v_caller_id)
     ORDER BY
           CASE WHEN appointment.doctor_id = v_caller_id THEN 0 ELSE 1 END,
           appointment.date ASC NULLS LAST,
           appointment.appointment_date ASC NULLS LAST,
           appointment.appointment_time ASC NULLS LAST,
           appointment.time ASC NULLS LAST,
           appointment.id ASC
     LIMIT 1;

    IF v_appointment.id IS NULL THEN
        RAISE EXCEPTION 'CONSULTATION_NO_CURRENT_APPOINTMENT'
            USING ERRCODE = 'P2002';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM public.consultations AS candidate
         WHERE candidate.appointment_id = v_appointment.id
           AND candidate.patient_id IS DISTINCT FROM p_patient_id
    ) THEN
        RAISE EXCEPTION 'CONSULTATION_OWNERSHIP_MISMATCH'
            USING ERRCODE = 'P2003';
    END IF;

    SELECT consultation.*
      INTO v_consultation
      FROM public.consultations AS consultation
     WHERE consultation.appointment_id = v_appointment.id
       AND consultation.patient_id = p_patient_id
     ORDER BY consultation.last_updated DESC NULLS LAST,
              consultation.created_at DESC NULLS LAST,
              consultation.id DESC
     LIMIT 1;

    IF v_consultation.id IS NOT NULL
       AND v_consultation.doctor_id IS NOT NULL
       AND v_consultation.doctor_id IS DISTINCT FROM v_appointment.doctor_id THEN
        RAISE EXCEPTION 'CONSULTATION_OWNERSHIP_MISMATCH'
            USING ERRCODE = 'P2003';
    END IF;

    SELECT dental_state.*
      INTO v_dental_state
      FROM public.patient_dental_state AS dental_state
     WHERE dental_state.patient_id = p_patient_id;

    SELECT previous.*
      INTO v_last_note
      FROM public.consultations AS previous
     WHERE previous.patient_id = p_patient_id
       AND (v_consultation.id IS NULL OR previous.id <> v_consultation.id)
       AND previous.session_note IS NOT NULL
       AND length(btrim(previous.session_note)) > 0
     ORDER BY previous.created_at DESC NULLS LAST,
              previous.last_updated DESC NULLS LAST,
              previous.id DESC
     LIMIT 1;

    RETURN jsonb_build_object(
        'consultationId', v_consultation.id,
        'patientId', p_patient_id,
        'doctorId', coalesce(v_consultation.doctor_id, v_appointment.doctor_id),
        'appointmentId', v_appointment.id,
        'toothData', coalesce(
            CASE WHEN v_consultation.id IS NOT NULL THEN v_consultation.data::jsonb END,
            CASE WHEN v_dental_state.patient_id IS NOT NULL THEN v_dental_state.data::jsonb END,
            '{}'::jsonb
        ),
        'sessionNote', v_consultation.session_note,
        'version', coalesce(v_consultation.version, 0),
        'dentalStateVersion', coalesce(v_dental_state.version, 0),
        'createdAt', v_consultation.created_at,
        'lastUpdated', v_consultation.last_updated,
        'lastConsultationNote', CASE
            WHEN v_last_note.id IS NULL THEN NULL
            ELSE jsonb_build_object(
                'consultationId', v_last_note.id,
                'sessionNote', v_last_note.session_note,
                'date', coalesce(v_last_note.last_updated, v_last_note.created_at)
            )
        END
    );
END
$function$;

CREATE OR REPLACE FUNCTION public.save_current_consultation(
    p_patient_id uuid,
    p_tooth_data jsonb,
    p_version integer,
    p_dental_state_version integer,
    p_session_note text,
    p_session_note_supplied boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_caller_id uuid;
    v_caller_role text;
    v_appointment public.appointments%ROWTYPE;
    v_consultation public.consultations%ROWTYPE;
    v_dental_state public.patient_dental_state%ROWTYPE;
    v_last_note public.consultations%ROWTYPE;
    v_before_state text;
    v_current_dental_version integer := 0;
BEGIN
    SELECT app_user.id, app_user.role
      INTO v_caller_id, v_caller_role
      FROM public.users AS app_user
     WHERE app_user.supabase_user_id = auth.uid()
       AND app_user.is_active = true
       AND app_user.approved_at IS NOT NULL
       AND app_user.role IN ('doctor', 'admin')
     LIMIT 1;

    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'CONSULTATION_AUTHORIZATION_DENIED'
            USING ERRCODE = '42501';
    END IF;

    IF p_tooth_data IS NULL OR jsonb_typeof(p_tooth_data) <> 'object' THEN
        RAISE EXCEPTION 'CONSULTATION_TOOTH_DATA_MUST_BE_OBJECT'
            USING ERRCODE = '22023';
    END IF;

    IF p_version IS NULL OR p_version < 0
       OR p_dental_state_version IS NULL OR p_dental_state_version < 0 THEN
        RAISE EXCEPTION 'CONSULTATION_VERSION_INVALID'
            USING ERRCODE = '22023';
    END IF;

    PERFORM 1
      FROM public.patients AS patient
     WHERE patient.id = p_patient_id
     FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'CONSULTATION_PATIENT_NOT_FOUND'
            USING ERRCODE = 'P2001';
    END IF;

    SELECT appointment.*
      INTO v_appointment
      FROM public.appointments AS appointment
     WHERE appointment.patient_id = p_patient_id
       AND (
           appointment.date = CURRENT_DATE
           OR appointment.appointment_date = CURRENT_DATE
       )
       AND appointment.status::text IN ('pending', 'confirmed')
       AND appointment.doctor_id IS NOT NULL
       AND (v_caller_role = 'admin' OR appointment.doctor_id = v_caller_id)
     ORDER BY
           CASE WHEN appointment.doctor_id = v_caller_id THEN 0 ELSE 1 END,
           appointment.date ASC NULLS LAST,
           appointment.appointment_date ASC NULLS LAST,
           appointment.appointment_time ASC NULLS LAST,
           appointment.time ASC NULLS LAST,
           appointment.id ASC
     LIMIT 1
     FOR UPDATE;

    IF v_appointment.id IS NULL THEN
        RAISE EXCEPTION 'CONSULTATION_NO_CURRENT_APPOINTMENT'
            USING ERRCODE = 'P2002';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM public.consultations AS candidate
         WHERE candidate.appointment_id = v_appointment.id
           AND candidate.patient_id IS DISTINCT FROM p_patient_id
    ) THEN
        RAISE EXCEPTION 'CONSULTATION_OWNERSHIP_MISMATCH'
            USING ERRCODE = 'P2003';
    END IF;

    SELECT consultation.*
      INTO v_consultation
      FROM public.consultations AS consultation
     WHERE consultation.appointment_id = v_appointment.id
       AND consultation.patient_id = p_patient_id
     ORDER BY consultation.last_updated DESC NULLS LAST,
              consultation.created_at DESC NULLS LAST,
              consultation.id DESC
     LIMIT 1
     FOR UPDATE;

    IF v_consultation.id IS NOT NULL
       AND v_consultation.doctor_id IS NOT NULL
       AND v_consultation.doctor_id IS DISTINCT FROM v_appointment.doctor_id THEN
        RAISE EXCEPTION 'CONSULTATION_OWNERSHIP_MISMATCH'
            USING ERRCODE = 'P2003';
    END IF;

    SELECT dental_state.*
      INTO v_dental_state
      FROM public.patient_dental_state AS dental_state
     WHERE dental_state.patient_id = p_patient_id
     FOR UPDATE;
    IF v_dental_state.patient_id IS NOT NULL THEN
        v_current_dental_version := v_dental_state.version;
    END IF;

    IF p_dental_state_version <> v_current_dental_version THEN
        RAISE EXCEPTION 'CONSULTATION_DENTAL_STATE_VERSION_CONFLICT'
            USING ERRCODE = '40001';
    END IF;

    IF v_consultation.id IS NOT NULL THEN
        IF p_version <> v_consultation.version THEN
            RAISE EXCEPTION 'CONSULTATION_VERSION_CONFLICT'
                USING ERRCODE = '40001';
        END IF;
        v_before_state := v_consultation.data;
        UPDATE public.consultations AS consultation
           SET data = p_tooth_data::text,
               session_note = CASE
                   WHEN p_session_note_supplied THEN p_session_note
                   ELSE consultation.session_note
               END,
               doctor_id = coalesce(consultation.doctor_id, v_appointment.doctor_id),
               version = consultation.version + 1,
               last_updated = now()
         WHERE consultation.id = v_consultation.id
         RETURNING consultation.* INTO v_consultation;
    ELSE
        IF p_version <> 0 THEN
            RAISE EXCEPTION 'CONSULTATION_VERSION_CONFLICT'
                USING ERRCODE = '40001';
        END IF;
        INSERT INTO public.consultations (
            id, patient_id, doctor_id, appointment_id, data, session_note,
            version, created_at, last_updated
        ) VALUES (
            gen_random_uuid(), p_patient_id, v_appointment.doctor_id,
            v_appointment.id, p_tooth_data::text,
            CASE WHEN p_session_note_supplied THEN p_session_note ELSE NULL END,
            1, now(), now()
        )
        RETURNING * INTO v_consultation;
    END IF;

    IF v_dental_state.patient_id IS NULL THEN
        INSERT INTO public.patient_dental_state (
            patient_id, data, version, updated_at
        ) VALUES (
            p_patient_id, p_tooth_data::text, 1, now()
        )
        RETURNING * INTO v_dental_state;
    ELSIF v_dental_state.data::jsonb IS DISTINCT FROM p_tooth_data THEN
        UPDATE public.patient_dental_state AS dental_state
           SET data = p_tooth_data::text,
               version = dental_state.version + 1,
               updated_at = now()
         WHERE dental_state.patient_id = p_patient_id
         RETURNING dental_state.* INTO v_dental_state;
    END IF;

    INSERT INTO public.logs (
        id, message, doctor_id, patient_id, before_state, after_state, created_at
    ) VALUES (
        gen_random_uuid(),
        format('Consultation updated for patient %s', p_patient_id),
        v_caller_id,
        p_patient_id,
        v_before_state,
        p_tooth_data::text,
        now()
    );

    SELECT previous.*
      INTO v_last_note
      FROM public.consultations AS previous
     WHERE previous.patient_id = p_patient_id
       AND previous.id <> v_consultation.id
       AND previous.session_note IS NOT NULL
       AND length(btrim(previous.session_note)) > 0
     ORDER BY previous.created_at DESC NULLS LAST,
              previous.last_updated DESC NULLS LAST,
              previous.id DESC
     LIMIT 1;

    RETURN jsonb_build_object(
        'status', 'success',
        'version', v_consultation.version,
        'dentalStateVersion', v_dental_state.version,
        'consultationId', v_consultation.id,
        'appointmentId', v_consultation.appointment_id,
        'sessionNote', v_consultation.session_note,
        'lastConsultationNote', CASE
            WHEN v_last_note.id IS NULL THEN NULL
            ELSE jsonb_build_object(
                'consultationId', v_last_note.id,
                'sessionNote', v_last_note.session_note,
                'date', coalesce(v_last_note.last_updated, v_last_note.created_at)
            )
        END
    );
END
$function$;

REVOKE ALL ON FUNCTION public.get_or_initialize_consultation(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_or_initialize_consultation(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_or_initialize_consultation(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.save_current_consultation(uuid, jsonb, integer, integer, text, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.save_current_consultation(uuid, jsonb, integer, integer, text, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.save_current_consultation(uuid, jsonb, integer, integer, text, boolean) TO authenticated;

COMMIT;
