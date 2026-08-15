-- Read-only verification for Migration 015. Do not run as part of this local task.

DO $$
DECLARE
    v_definition text;
    v_status_values text[];
BEGIN
    SELECT pg_get_functiondef(p.oid)
      INTO v_definition
      FROM pg_proc AS p
      JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'finish_appointment_by_patient'
       AND p.proargtypes = '2950 2950'::oidvector;

    IF v_definition IS NULL THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: finish_appointment_by_patient(uuid, uuid) is missing';
    END IF;
    IF v_definition NOT LIKE '%appointment.status::text IN (''pending'', ''confirmed'')%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: active appointment predicate is missing';
    END IF;
    IF v_definition NOT LIKE '%appointment.doctor_id IS NOT NULL%'
       OR v_definition NOT LIKE '%v_caller_role = ''admin''%'
       OR v_definition NOT LIKE '%appointment.doctor_id = v_caller_id%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: finish ownership containment is missing';
    END IF;
    IF lower(v_definition) LIKE '%lower(appointment.status)%'
       OR lower(v_definition) LIKE '%''finished''%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: enum-unsafe legacy finish status logic remains';
    END IF;
    IF v_definition NOT LIKE '%SET status = ''completed''%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: completed status write is missing';
    END IF;
    IF v_definition NOT LIKE '%appointment.date = current_date%'
       OR v_definition NOT LIKE '%FOR UPDATE%'
       OR v_definition NOT LIKE '%INSERT INTO public.logs%'
       OR v_definition NOT LIKE '%v_caller_role NOT IN (''doctor'', ''admin'')%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: finish lifecycle containment changed';
    END IF;

    SELECT array_agg(enum_value ORDER BY enum_order)
      INTO v_status_values
      FROM (
          SELECT enum.enumlabel::text AS enum_value,
                 enum.enumsortorder AS enum_order
            FROM pg_type AS type
            JOIN pg_namespace AS namespace ON namespace.oid = type.typnamespace
            JOIN pg_enum AS enum ON enum.enumtypid = type.oid
           WHERE namespace.nspname = 'public'
             AND type.typname = 'appointment_status'
      ) AS status_contract;
    IF v_status_values IS DISTINCT FROM
       ARRAY['pending', 'confirmed', 'completed', 'cancelled', 'no_show']::text[] THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: appointment_status enum contract changed';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.routine_privileges
         WHERE routine_schema = 'public'
           AND routine_name = 'finish_appointment_by_patient'
           AND grantee IN ('PUBLIC', 'anon')
           AND privilege_type = 'EXECUTE'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.routine_privileges
         WHERE routine_schema = 'public'
           AND routine_name = 'finish_appointment_by_patient'
           AND grantee = 'authenticated'
           AND privilege_type = 'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: finish RPC privileges are invalid';
    END IF;

    RAISE NOTICE 'VERIFICATION SUCCESSFUL: finish appointment enum hotfix is installed.';
END $$;
