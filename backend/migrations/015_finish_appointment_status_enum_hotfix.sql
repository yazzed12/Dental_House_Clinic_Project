-- Migration 015: forward hotfix for enum-safe appointment completion.
-- Migration 010 may already be deployed; replace only the affected RPC and
-- reassert its function-level privilege boundary.

BEGIN;

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

    UPDATE public.appointments
       SET status = 'completed'
     WHERE id = v_appointment_id;

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

REVOKE ALL ON FUNCTION public.finish_appointment_by_patient(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.finish_appointment_by_patient(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.finish_appointment_by_patient(uuid, uuid) TO authenticated;

COMMIT;
