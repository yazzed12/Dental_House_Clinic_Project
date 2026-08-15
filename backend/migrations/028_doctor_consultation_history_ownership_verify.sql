-- Migration 028 verifier: read-only ownership, projection, ACL, and isolation assertions.
DO $verify$
DECLARE
    v_actor text;
    v_base text;
    v_wrapper text;
    v_public regprocedure := to_regprocedure('public.list_doctor_consultation_history()');
BEGIN
    IF v_public IS NULL OR to_regprocedure('security.list_doctor_consultation_history_base()') IS NULL THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: required history functions are missing';
    END IF;
    SELECT lower(pg_get_functiondef('security.consultation_history_actor()'::regprocedure)) INTO v_actor;
    SELECT lower(pg_get_functiondef('security.list_doctor_consultation_history_base()'::regprocedure)) INTO v_base;
    SELECT lower(pg_get_functiondef(v_public)) INTO v_wrapper;

    IF v_actor NOT LIKE '%supabase_user_id = auth.uid()%'
       OR v_actor NOT LIKE '%is_active = true%'
       OR v_actor NOT LIKE '%approved_at is not null%'
       OR v_actor NOT LIKE '%role in (''doctor'', ''admin'')%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Doctor identity is not derived and gated correctly';
    END IF;
    IF v_base NOT LIKE '%v_actor_role = ''doctor'' and consultation.doctor_id = v_actor_id%'
       OR v_base NOT LIKE '%v_actor_role = ''doctor'' and report.doctor_id = v_actor_id%'
       OR v_base LIKE '%consultation.doctor_id is null and exists%'
       OR v_base LIKE '%report.doctor_id is null and exists%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: same-patient Doctor ownership containment is incomplete';
    END IF;
    IF v_base NOT LIKE '%v_actor_role = ''admin''%'
       OR v_base NOT LIKE '%security.consultation_history_json_array%'
       OR v_base NOT LIKE '%public.consultation_procedures%'
       OR v_base NOT LIKE '%history.sort_updated desc nulls last%'
       OR v_base NOT LIKE '%history.sort_created desc nulls last%'
       OR v_base NOT LIKE '%history.sort_kind%'
       OR v_base NOT LIKE '%history.stable_id desc%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Admin branch, fields, procedures, or ordering changed';
    END IF;
    IF v_wrapper NOT LIKE '%security.list_doctor_consultation_history_base()%'
       OR v_wrapper NOT LIKE '%''clinicalfindings''%'
       OR v_wrapper NOT LIKE '%''reportsnapshot''%'
       OR v_wrapper NOT LIKE '%''snapshotversion''%'
       OR v_wrapper NOT LIKE '%''reviewedat''%'
       OR v_wrapper NOT LIKE '%''finalizedat''%'
       OR v_wrapper NOT LIKE '%''labnote''%'
       OR v_wrapper NOT LIKE '%''labitems''%'
       OR v_wrapper NOT LIKE '%order by item.ordinality%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Migration 023 history fields or ordering changed';
    END IF;
    IF v_wrapper LIKE '%public.labs %' OR v_wrapper LIKE '%public.lab_products %'
       OR v_wrapper LIKE '%current_price%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: mutable Lab catalog entered history';
    END IF;
    IF EXISTS (SELECT 1 FROM aclexplode(coalesce((SELECT proacl FROM pg_proc WHERE oid=v_public::oid),
                                                  acldefault('f',(SELECT proowner FROM pg_proc WHERE oid=v_public::oid)))) entry
               WHERE entry.grantee=0 AND entry.privilege_type='EXECUTE')
       OR has_function_privilege('anon',v_public,'EXECUTE')
       OR NOT has_function_privilege('authenticated',v_public,'EXECUTE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: history function ACL is invalid';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='clinical_reports'
                  AND lower(column_name) LIKE '%lab%') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Medical Report schema isolation changed';
    END IF;
END
$verify$;

SELECT 'VERIFICATION SUCCESSFUL: Doctor Consultation History is ownership-contained' AS result;
