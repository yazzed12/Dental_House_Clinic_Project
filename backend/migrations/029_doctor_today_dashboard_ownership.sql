-- Migration 029: contain the existing appointment projection by authenticated role.
-- The frontend retains the existing date/status definition of Today's Consultations.
BEGIN;

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
DECLARE
    v_actor_id uuid;
    v_actor_role text;
BEGIN
    v_actor_id := security.current_app_user_id();
    v_actor_role := security.current_app_role();
    IF v_actor_id IS NULL OR v_actor_role NOT IN ('doctor', 'receptionist', 'admin') THEN
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
     WHERE v_actor_role IN ('receptionist', 'admin')
        OR (
            v_actor_role = 'doctor'
            AND appointment.doctor_id = v_actor_id
            AND NOT EXISTS (
                SELECT 1
                  FROM public.consultations AS consultation
                 WHERE consultation.appointment_id = appointment.id
                   AND consultation.doctor_id IS DISTINCT FROM v_actor_id
            )
        )
     ORDER BY appointment.date, appointment.appointment_time NULLS LAST,
              appointment.time, appointment.id;
END
$function$;

REVOKE ALL ON FUNCTION public.get_appointments() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_appointments() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_appointments() TO authenticated;

COMMIT;
