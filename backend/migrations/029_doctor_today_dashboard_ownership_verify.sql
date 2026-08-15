-- Migration 029 verifier: read-only Doctor dashboard ownership and compatibility assertions.
DO $verify$
DECLARE
    v_definition text;
    v_identity text;
    v_history text;
    v_signature regprocedure := to_regprocedure('public.get_appointments()');
BEGIN
    IF v_signature IS NULL THEN RAISE EXCEPTION 'VERIFICATION FAILED: get_appointments() is missing'; END IF;
    SELECT lower(pg_get_functiondef(v_signature)) INTO v_definition;
    SELECT lower(pg_get_functiondef('security.current_app_user_id()'::regprocedure)) INTO v_identity;

    IF v_identity NOT LIKE '%supabase_user_id = auth.uid()%'
       OR v_identity NOT LIKE '%is_active = true%'
       OR v_identity NOT LIKE '%approved_at is not null%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Doctor identity is not derived from active approved auth.uid() linkage';
    END IF;
    IF v_definition NOT LIKE '%v_actor_role = ''doctor''%'
       OR v_definition NOT LIKE '%appointment.doctor_id = v_actor_id%'
       OR v_definition LIKE '%appointment.doctor_id is null%'
       OR v_definition LIKE '%appointment.patient_id =%v_actor_id%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Doctor appointment ownership is incomplete';
    END IF;
    IF v_definition NOT LIKE '%consultation.appointment_id = appointment.id%'
       OR v_definition NOT LIKE '%consultation.doctor_id is distinct from v_actor_id%'
       OR v_definition NOT LIKE '%not exists%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: appointment/consultation mismatch containment is incomplete';
    END IF;
    IF v_definition LIKE '%current_date%' OR v_definition LIKE '%now()%' OR v_definition LIKE '%timezone(%'
       OR v_definition NOT LIKE '%order by appointment.date%appointment.appointment_time nulls last%appointment.time%appointment.id%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: existing date semantics or ordering changed';
    END IF;
    IF v_definition NOT LIKE '%v_actor_role in (''receptionist'', ''admin'')%'
       OR v_definition NOT LIKE '%v_actor_role not in (''doctor'', ''receptionist'', ''admin'')%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: existing operational role behavior changed or unsupported roles are admitted';
    END IF;
    IF replace(pg_get_function_result(v_signature), '"', '') <>
       'TABLE(id uuid, patient_id uuid, patient text, doctor_id uuid, doctor text, date date, time text, type text, status text, condition text, notes text)' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: appointment response contract changed';
    END IF;
    IF EXISTS (SELECT 1 FROM aclexplode(coalesce((SELECT proacl FROM pg_proc WHERE oid=v_signature::oid),
                                                  acldefault('f',(SELECT proowner FROM pg_proc WHERE oid=v_signature::oid)))) entry
               WHERE entry.grantee=0 AND entry.privilege_type='EXECUTE')
       OR has_function_privilege('anon',v_signature,'EXECUTE')
       OR NOT has_function_privilege('authenticated',v_signature,'EXECUTE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: get_appointments() ACL is invalid';
    END IF;

    SELECT lower(pg_get_functiondef('security.list_doctor_consultation_history_base()'::regprocedure)) INTO v_history;
    IF v_history NOT LIKE '%v_actor_role = ''doctor'' and consultation.doctor_id = v_actor_id%'
       OR v_history NOT LIKE '%v_actor_role = ''doctor'' and report.doctor_id = v_actor_id%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Migration 028 Consultation History containment changed';
    END IF;
END
$verify$;

SELECT 'VERIFICATION SUCCESSFUL: Doctor Today''s Consultations are ownership-contained' AS result;
