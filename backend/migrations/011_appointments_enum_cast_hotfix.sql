-- Migration 011: Explicit enum casts for already-deployed Appointment RPCs.
-- Forward hotfix only. Migration 010 is also corrected for clean installations.

BEGIN;

CREATE OR REPLACE FUNCTION public.create_appointment(
    p_patient_id uuid,
    p_doctor_id uuid,
    p_date date,
    p_time text,
    p_type text DEFAULT 'Consultation',
    p_condition text DEFAULT 'Routine Checkup',
    p_status text DEFAULT 'pending',
    p_notes text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_caller_id uuid;
    v_caller_role text;
    v_appointment_id uuid := gen_random_uuid();
    v_parsed_time time;
BEGIN
    v_caller_id := security.current_app_user_id();
    v_caller_role := security.current_app_role();
    IF v_caller_id IS NULL OR v_caller_role NOT IN ('doctor', 'receptionist', 'admin') THEN
        RAISE EXCEPTION 'Insufficient permissions' USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.patients AS patient WHERE patient.id = p_patient_id) THEN
        RAISE EXCEPTION 'Patient not found' USING ERRCODE = 'P0002';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM public.users AS doctor
         WHERE doctor.id = p_doctor_id
           AND doctor.role = 'doctor'
           AND doctor.is_active = true
           AND doctor.approved_at IS NOT NULL
           AND doctor.supabase_user_id IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Eligible Doctor not found' USING ERRCODE = 'P0002';
    END IF;

    IF p_date IS NULL THEN
        RAISE EXCEPTION 'Appointment date is required' USING ERRCODE = '22007';
    END IF;
    IF p_time IS NULL OR btrim(p_time) !~
       '^(?:[01][0-9]|2[0-3]):[0-5][0-9](?::[0-5][0-9])?$|^(?:0?[1-9]|1[0-2]):[0-5][0-9][[:space:]]*(?:AM|PM|am|pm)$' THEN
        RAISE EXCEPTION 'Invalid appointment time' USING ERRCODE = '22007';
    END IF;

    v_parsed_time := CASE
        WHEN upper(p_time) LIKE '%AM' OR upper(p_time) LIKE '%PM'
            THEN to_timestamp(upper(btrim(p_time)), 'HH12:MI AM')::time
        ELSE p_time::time
    END;

    INSERT INTO public.appointments (
        id, patient_id, doctor_id, date, time, appointment_date,
        appointment_time, type, status, condition, notes
    ) VALUES (
        v_appointment_id,
        p_patient_id,
        p_doctor_id,
        p_date,
        btrim(p_time),
        p_date,
        v_parsed_time,
        security.normalize_appointment_type(p_type)::public.appointment_type,
        security.normalize_appointment_status(p_status)::public.appointment_status,
        coalesce(nullif(btrim(p_condition), ''), 'Routine Checkup'),
        coalesce(p_notes, '')
    );

    RETURN security.appointment_projection(v_appointment_id);
END
$function$;

CREATE OR REPLACE FUNCTION public.update_appointment(
    p_appointment_id uuid,
    p_updates jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_caller_id uuid;
    v_caller_role text;
    v_caller_username text;
    v_patient_id uuid;
    v_date date;
    v_time text;
    v_parsed_time time;
BEGIN
    v_caller_id := security.current_app_user_id();
    v_caller_role := security.current_app_role();
    IF v_caller_id IS NULL OR v_caller_role NOT IN ('doctor', 'receptionist', 'admin') THEN
        RAISE EXCEPTION 'Insufficient permissions' USING ERRCODE = '42501';
    END IF;
    IF p_updates IS NULL OR jsonb_typeof(p_updates) <> 'object' THEN
        RAISE EXCEPTION 'Appointment updates must be an object' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_object_keys(p_updates) AS key
         WHERE key NOT IN ('date', 'time', 'type', 'status', 'condition', 'notes')
    ) THEN
        RAISE EXCEPTION 'Unsupported appointment update field' USING ERRCODE = '22023';
    END IF;

    SELECT appointment.patient_id
      INTO v_patient_id
      FROM public.appointments AS appointment
     WHERE appointment.id = p_appointment_id
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Appointment not found' USING ERRCODE = 'P0002';
    END IF;

    IF p_updates ? 'date' THEN
        BEGIN
            v_date := (p_updates ->> 'date')::date;
        EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
            RAISE EXCEPTION 'Invalid appointment date' USING ERRCODE = '22007';
        END;
        IF v_date IS NULL THEN
            RAISE EXCEPTION 'Appointment date is required' USING ERRCODE = '22007';
        END IF;
    END IF;

    IF p_updates ? 'time' THEN
        v_time := p_updates ->> 'time';
        IF v_time IS NULL OR btrim(v_time) !~
           '^(?:[01][0-9]|2[0-3]):[0-5][0-9](?::[0-5][0-9])?$|^(?:0?[1-9]|1[0-2]):[0-5][0-9][[:space:]]*(?:AM|PM|am|pm)$' THEN
            RAISE EXCEPTION 'Invalid appointment time' USING ERRCODE = '22007';
        END IF;
        v_parsed_time := CASE
            WHEN upper(v_time) LIKE '%AM' OR upper(v_time) LIKE '%PM'
                THEN to_timestamp(upper(btrim(v_time)), 'HH12:MI AM')::time
            ELSE v_time::time
        END;
    END IF;

    UPDATE public.appointments AS appointment
       SET date = CASE WHEN p_updates ? 'date' THEN v_date ELSE appointment.date END,
           appointment_date = CASE WHEN p_updates ? 'date' THEN v_date ELSE appointment.appointment_date END,
           time = CASE WHEN p_updates ? 'time' THEN btrim(v_time) ELSE appointment.time END,
           appointment_time = CASE WHEN p_updates ? 'time' THEN v_parsed_time ELSE appointment.appointment_time END,
           type = CASE
               WHEN p_updates ? 'type'
                   THEN security.normalize_appointment_type(p_updates ->> 'type')::public.appointment_type
               ELSE appointment.type
           END,
           status = CASE
               WHEN p_updates ? 'status'
                   THEN security.normalize_appointment_status(p_updates ->> 'status')::public.appointment_status
               ELSE appointment.status
           END,
           condition = CASE WHEN p_updates ? 'condition' THEN coalesce(nullif(btrim(p_updates ->> 'condition'), ''), 'Routine Checkup') ELSE appointment.condition END,
           notes = CASE WHEN p_updates ? 'notes' THEN coalesce(p_updates ->> 'notes', '') ELSE appointment.notes END
     WHERE appointment.id = p_appointment_id;

    SELECT caller.username::text INTO v_caller_username
      FROM public.users AS caller WHERE caller.id = v_caller_id;
    INSERT INTO public.logs (id, message, doctor_id, patient_id, created_at)
    VALUES (
        gen_random_uuid(),
        format('Appointment %s updated by %s', p_appointment_id, coalesce(v_caller_username, v_caller_id::text)),
        v_caller_id,
        v_patient_id,
        now()
    );

    RETURN security.appointment_projection(p_appointment_id);
END
$function$;

CREATE OR REPLACE FUNCTION public.update_appointment_status(
    p_appointment_id uuid,
    p_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_caller_id uuid;
    v_caller_role text;
    v_new_status text;
BEGIN
    v_caller_id := security.current_app_user_id();
    v_caller_role := security.current_app_role();
    IF v_caller_id IS NULL OR v_caller_role NOT IN ('doctor', 'receptionist', 'admin') THEN
        RAISE EXCEPTION 'Insufficient permissions' USING ERRCODE = '42501';
    END IF;

    PERFORM 1
      FROM public.appointments AS appointment
     WHERE appointment.id = p_appointment_id
       FOR UPDATE OF appointment;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Appointment not found' USING ERRCODE = 'P0002';
    END IF;

    v_new_status := security.normalize_appointment_status(p_status);
    UPDATE public.appointments
       SET status = v_new_status::public.appointment_status
     WHERE id = p_appointment_id;

    RETURN security.appointment_projection(p_appointment_id);
END
$function$;

REVOKE ALL ON FUNCTION public.create_appointment(uuid, uuid, date, text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_appointment(uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_appointment_status(uuid, text) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.create_appointment(uuid, uuid, date, text, text, text, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.update_appointment(uuid, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.update_appointment_status(uuid, text) FROM anon;

GRANT EXECUTE ON FUNCTION public.create_appointment(uuid, uuid, date, text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_appointment(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_appointment_status(uuid, text) TO authenticated;

COMMIT;
