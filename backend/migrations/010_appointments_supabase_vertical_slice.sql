-- Migration 010: Supabase-native Appointments vertical slice.
-- Local migration file only. Apply through the approved deployment process.

BEGIN;

-- Contain browser access. Appointment reads and writes are exposed only through
-- the narrow SECURITY DEFINER RPCs below.
DROP POLICY IF EXISTS "Allow all" ON public.appointments;
DROP POLICY IF EXISTS "Allow clinic staff to read appointments" ON public.appointments;
DROP POLICY IF EXISTS "Allow clinic staff to insert appointments" ON public.appointments;
DROP POLICY IF EXISTS "Allow clinic staff to update appointments" ON public.appointments;
DROP POLICY IF EXISTS "Allow clinic staff to delete appointments" ON public.appointments;
DROP POLICY IF EXISTS "Allow clinic staff to manage appointments" ON public.appointments;
DROP POLICY IF EXISTS "Allow initial data migration" ON public.appointments;

REVOKE ALL ON TABLE public.appointments FROM PUBLIC;
REVOKE ALL ON TABLE public.appointments FROM anon;
REVOKE ALL ON TABLE public.appointments FROM authenticated;
ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;

-- These columns are already represented by the authoritative application model.
-- IF NOT EXISTS keeps the migration compatible with older Supabase snapshots.
ALTER TABLE public.appointments
    ADD COLUMN IF NOT EXISTS appointment_date date,
    ADD COLUMN IF NOT EXISTS appointment_time time,
    ADD COLUMN IF NOT EXISTS notes text;

CREATE OR REPLACE FUNCTION security.normalize_appointment_type(p_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT CASE
        WHEN p_type IS NULL OR btrim(p_type) = '' THEN 'consultation'
        WHEN lower(p_type) LIKE '%check%' OR lower(p_type) LIKE '%norm%' THEN 'normal'
        WHEN lower(p_type) LIKE '%urg%' OR lower(p_type) LIKE '%emerg%' THEN 'urgent'
        WHEN lower(p_type) LIKE '%follow%' THEN 'follow_up'
        WHEN lower(p_type) LIKE '%consult%' THEN 'consultation'
        WHEN lower(replace(replace(btrim(p_type), '-', '_'), ' ', '_'))
             IN ('normal', 'urgent', 'follow_up', 'consultation')
            THEN lower(replace(replace(btrim(p_type), '-', '_'), ' ', '_'))
        ELSE 'consultation'
    END
$function$;

CREATE OR REPLACE FUNCTION security.normalize_appointment_status(p_status text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_status text := lower(btrim(p_status));
BEGIN
    IF v_status IS NULL
       OR v_status NOT IN ('pending', 'confirmed', 'completed', 'cancelled', 'no_show') THEN
        RAISE EXCEPTION 'Unsupported appointment status' USING ERRCODE = '22023';
    END IF;
    RETURN v_status;
END
$function$;

CREATE OR REPLACE FUNCTION security.appointment_projection(p_appointment_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT jsonb_build_object(
        'id', appointment.id,
        'patient_id', appointment.patient_id,
        'patient', patient.name,
        'doctor_id', appointment.doctor_id,
        'doctor', doctor.full_name,
        'date', appointment.date,
        'time', appointment.time,
        'type', appointment.type,
        'status', appointment.status,
        'condition', coalesce(appointment.condition, 'Routine Checkup'),
        'notes', coalesce(appointment.notes, '')
    )
      FROM public.appointments AS appointment
      JOIN public.patients AS patient ON patient.id = appointment.patient_id
      LEFT JOIN public.users AS doctor ON doctor.id = appointment.doctor_id
     WHERE appointment.id = p_appointment_id
$function$;

REVOKE ALL ON FUNCTION security.normalize_appointment_type(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION security.normalize_appointment_status(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION security.appointment_projection(uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.get_appointments()
RETURNS TABLE (
    id uuid,
    patient_id uuid,
    patient text,
    doctor_id uuid,
    doctor text,
    "date" date,
    "time" text,
    "type" text,
    "status" text,
    "condition" text,
    notes text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM public.users AS caller
         WHERE caller.supabase_user_id = auth.uid()
           AND caller.is_active = true
           AND caller.approved_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Application access denied' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        appointment.id,
        appointment.patient_id,
        patient.name::text,
        appointment.doctor_id,
        doctor.full_name::text,
        appointment.date,
        appointment.time::text,
        appointment.type::text,
        appointment.status::text,
        coalesce(appointment.condition, 'Routine Checkup')::text,
        coalesce(appointment.notes, '')::text
      FROM public.appointments AS appointment
      JOIN public.patients AS patient ON patient.id = appointment.patient_id
      LEFT JOIN public.users AS doctor ON doctor.id = appointment.doctor_id
     ORDER BY appointment.date, appointment.appointment_time NULLS LAST,
              appointment.time, appointment.id;
END
$function$;

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

CREATE OR REPLACE FUNCTION public.mark_appointment_arrived(p_appointment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_caller_id uuid;
    v_caller_role text;
    v_patient_name text;
    v_appointment_time text;
BEGIN
    v_caller_id := security.current_app_user_id();
    v_caller_role := security.current_app_role();
    IF v_caller_id IS NULL OR v_caller_role NOT IN ('doctor', 'receptionist', 'admin') THEN
        RAISE EXCEPTION 'Insufficient permissions' USING ERRCODE = '42501';
    END IF;

    SELECT patient.name::text, appointment.time::text
      INTO v_patient_name, v_appointment_time
      FROM public.appointments AS appointment
      JOIN public.patients AS patient ON patient.id = appointment.patient_id
     WHERE appointment.id = p_appointment_id
       FOR UPDATE OF appointment;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Appointment not found' USING ERRCODE = 'P0002';
    END IF;

    -- Production appointment_status has no arrived value. Preserve the legacy
    -- domain behavior: arrival is an action/notification and persists pending.
    UPDATE public.appointments
       SET status = 'pending'
     WHERE id = p_appointment_id;

    INSERT INTO public.notifications (id, title, body, type, "read", created_at)
    VALUES (
        gen_random_uuid(),
        'Patient Arrived',
        format('%s has arrived for their %s appointment.', v_patient_name, v_appointment_time),
        'success',
        0,
        now()
    );

    RETURN security.appointment_projection(p_appointment_id);
END
$function$;

CREATE OR REPLACE FUNCTION public.finish_appointment_by_patient(
    p_patient_id uuid,
    p_appointment_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_caller_id uuid;
    v_caller_role text;
    v_appointment_id uuid;
BEGIN
    v_caller_id := security.current_app_user_id();
    v_caller_role := security.current_app_role();
    IF v_caller_id IS NULL OR v_caller_role NOT IN ('doctor', 'admin') THEN
        RAISE EXCEPTION 'Insufficient permissions' USING ERRCODE = '42501';
    END IF;

    SELECT appointment.id INTO v_appointment_id
      FROM public.appointments AS appointment
     WHERE appointment.patient_id = p_patient_id
       AND (p_appointment_id IS NULL OR appointment.id = p_appointment_id)
       AND appointment.date = current_date
       AND appointment.status::text IN ('pending', 'confirmed')
       AND appointment.doctor_id IS NOT NULL
       AND (
           v_caller_role = 'admin'
           OR appointment.doctor_id = v_caller_id
       )
     ORDER BY appointment.appointment_time NULLS LAST, appointment.time, appointment.id
     LIMIT 1
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No active appointment found for this patient today' USING ERRCODE = 'P0002';
    END IF;

    UPDATE public.appointments SET status = 'completed' WHERE id = v_appointment_id;
    INSERT INTO public.logs (id, message, doctor_id, patient_id, created_at)
    VALUES (
        gen_random_uuid(),
        format('Clinical session finished for patient %s', p_patient_id),
        v_caller_id,
        p_patient_id,
        now()
    );

    RETURN jsonb_build_object('status', 'success', 'appointment_id', v_appointment_id);
END
$function$;

CREATE OR REPLACE FUNCTION public.delete_appointment(p_appointment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_caller_id uuid;
    v_caller_role text;
BEGIN
    v_caller_id := security.current_app_user_id();
    v_caller_role := security.current_app_role();
    IF v_caller_id IS NULL OR v_caller_role NOT IN ('doctor', 'receptionist', 'admin') THEN
        RAISE EXCEPTION 'Insufficient permissions' USING ERRCODE = '42501';
    END IF;

    PERFORM 1 FROM public.appointments WHERE id = p_appointment_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Appointment not found' USING ERRCODE = 'P0002';
    END IF;
    IF EXISTS (SELECT 1 FROM public.consultations WHERE appointment_id = p_appointment_id)
       OR EXISTS (SELECT 1 FROM public.clinical_reports WHERE appointment_id = p_appointment_id) THEN
        RAISE EXCEPTION 'Appointment has clinical history and cannot be deleted' USING ERRCODE = '23503';
    END IF;

    DELETE FROM public.appointments WHERE id = p_appointment_id;
    RETURN jsonb_build_object('status', 'success');
END
$function$;

REVOKE ALL ON FUNCTION public.get_appointments() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_appointment(uuid, uuid, date, text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_appointment(uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_appointment_status(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_appointment_arrived(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.finish_appointment_by_patient(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_appointment(uuid) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.get_appointments() FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_appointment(uuid, uuid, date, text, text, text, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.update_appointment(uuid, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.update_appointment_status(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.mark_appointment_arrived(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.finish_appointment_by_patient(uuid, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.delete_appointment(uuid) FROM anon;

GRANT EXECUTE ON FUNCTION public.get_appointments() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_appointment(uuid, uuid, date, text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_appointment(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_appointment_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_appointment_arrived(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finish_appointment_by_patient(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_appointment(uuid) TO authenticated;

COMMIT;
