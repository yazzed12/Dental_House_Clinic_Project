-- Read-only verification for Migration 013. Run manually only after approval.
DO $verify$
DECLARE
    v_definition text;
BEGIN
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.symptoms'::regclass) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: symptoms RLS is not enabled';
    END IF;

    IF has_table_privilege('PUBLIC', 'public.symptoms', 'SELECT,INSERT,UPDATE,DELETE')
       OR has_table_privilege('anon', 'public.symptoms', 'SELECT,INSERT,UPDATE,DELETE')
       OR has_table_privilege('authenticated', 'public.symptoms', 'SELECT,INSERT,UPDATE,DELETE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: browser roles retain direct symptoms privileges';
    END IF;

    SELECT pg_get_functiondef('public.list_active_symptoms()'::regprocedure)
      INTO v_definition;
    IF v_definition NOT LIKE '%app_user.supabase_user_id = auth.uid()%'
       OR v_definition NOT LIKE '%app_user.is_active = true%'
       OR v_definition NOT LIKE '%app_user.approved_at IS NOT NULL%'
       OR v_definition NOT LIKE '%app_user.role IN (''doctor'', ''admin'')%'
       OR v_definition NOT LIKE '%symptom.is_active <> 0%'
       OR v_definition NOT LIKE '%ORDER BY lower(btrim(symptom.name)), symptom.id::text%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: symptom-list authorization or projection differs';
    END IF;

    SELECT pg_get_functiondef('public.create_or_reactivate_symptom(text)'::regprocedure)
      INTO v_definition;
    IF v_definition NOT LIKE '%app_user.supabase_user_id = auth.uid()%'
       OR v_definition NOT LIKE '%pg_advisory_xact_lock%'
       OR v_definition NOT LIKE '%lower(btrim(symptom.name)) = v_normalized_name%'
       OR v_definition NOT LIKE '%SET is_active = 1%'
       OR v_definition NOT LIKE '%created_by,%'
       OR v_definition NOT LIKE '%v_caller_id,%'
       OR v_definition LIKE '%p_created_by%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: symptom-create containment or duplicate handling differs';
    END IF;

    IF has_function_privilege('PUBLIC', 'public.list_active_symptoms()', 'EXECUTE')
       OR has_function_privilege('anon', 'public.list_active_symptoms()', 'EXECUTE')
       OR has_function_privilege('PUBLIC', 'public.create_or_reactivate_symptom(text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.create_or_reactivate_symptom(text)', 'EXECUTE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: PUBLIC or anon can execute symptom RPCs';
    END IF;

    IF NOT has_function_privilege('authenticated', 'public.list_active_symptoms()', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.create_or_reactivate_symptom(text)', 'EXECUTE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: authenticated lacks symptom RPC execution';
    END IF;
END
$verify$;
