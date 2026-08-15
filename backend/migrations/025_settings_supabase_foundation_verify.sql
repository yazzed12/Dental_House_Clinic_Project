-- READ-ONLY verifier for Migration 025: Simplified Supabase Settings.
DO $verify$
DECLARE v_definition text; v_signature regprocedure;
BEGIN
  IF to_regclass('public.clinic_settings') IS NULL OR (SELECT count(*) FROM public.clinic_settings)<>1 THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: existing clinic_settings data missing or singleton changed';
  END IF;
  IF to_regclass('public.users') IS NULL OR NOT EXISTS (SELECT 1 FROM public.users) THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: existing users data missing';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.clinic_settings'::regclass)
     OR has_table_privilege('anon','public.clinic_settings','SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated','public.clinic_settings','SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: clinic_settings direct browser containment differs';
  END IF;

  SELECT regexp_replace(lower(pg_get_functiondef('security.settings_actor()'::regprocedure)),'[[:space:]]+',' ','g') INTO v_definition;
  IF position('supabase_user_id=auth.uid()' IN replace(v_definition,' ',''))=0
     OR position('is_active=true' IN replace(v_definition,' ',''))=0
     OR position('approved_at is not null' IN v_definition)=0
     OR position('''doctor''' IN v_definition)=0 OR position('''admin''' IN v_definition)=0
     OR position('''receptionist''' IN v_definition)=0 OR position('''patient''' IN v_definition)>0 THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: Settings actor identity/roles differ';
  END IF;

  SELECT regexp_replace(lower(pg_get_functiondef('public.get_clinic_settings()'::regprocedure)),'[[:space:]]+',' ','g') INTO v_definition;
  IF position('security.settings_actor()' IN v_definition)=0 OR position('public.clinic_settings' IN v_definition)=0
     OR position('''name''' IN v_definition)=0 OR position('''email''' IN v_definition)=0
     OR position('''phone''' IN v_definition)=0 OR position('''address''' IN v_definition)=0 THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: clinic read contract differs';
  END IF;

  SELECT regexp_replace(lower(pg_get_functiondef('public.update_clinic_settings(text,text,text,text)'::regprocedure)),'[[:space:]]+',' ','g') INTO v_definition;
  IF position('v_actor_rolenotin(''doctor'',''admin'')' IN replace(v_definition,' ',''))=0
     OR position('name=btrim(p_name)' IN replace(v_definition,' ',''))=0
     OR position('email=nullif(btrim(p_email),'''')' IN replace(v_definition,' ',''))=0
     OR position('phone=nullif(btrim(p_phone),'''')' IN replace(v_definition,' ',''))=0
     OR position('address=nullif(btrim(p_address),'''')' IN replace(v_definition,' ',''))=0
     OR position('working_hours' IN v_definition)>0 OR position('appointment_duration' IN v_definition)>0
     OR position('services' IN v_definition)>0 OR position('notification_settings' IN v_definition)>0
     OR position('delete from' IN v_definition)>0 OR position('insert into' IN v_definition)>0 THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: clinic safe-update scope differs';
  END IF;

  SELECT regexp_replace(lower(pg_get_functiondef('public.update_current_app_profile(text,text,text)'::regprocedure)),'[[:space:]]+',' ','g') INTO v_definition;
  IF position('app_user.id=v_actor_id' IN replace(v_definition,' ',''))=0
     OR position('app_user.supabase_user_id=auth.uid()' IN replace(v_definition,' ',''))=0
     OR position('v_actor_role<>''doctor''' IN replace(v_definition,' ',''))=0
     OR position('p_user' IN v_definition)>0 OR position('p_role' IN v_definition)>0 THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: self-profile update containment differs';
  END IF;

  FOREACH v_signature IN ARRAY ARRAY[
    'public.get_clinic_settings()'::regprocedure,
    'public.update_clinic_settings(text,text,text,text)'::regprocedure,
    'public.update_current_app_profile(text,text,text)'::regprocedure
  ] LOOP
    IF NOT (SELECT proc.prosecdef FROM pg_proc AS proc WHERE proc.oid=v_signature::oid)
       OR NOT ('search_path=pg_catalog, pg_temp'=ANY(coalesce((SELECT proc.proconfig FROM pg_proc AS proc WHERE proc.oid=v_signature::oid),ARRAY[]::text[])))
       OR has_function_privilege('anon',v_signature,'EXECUTE')
       OR NOT has_function_privilege('authenticated',v_signature,'EXECUTE')
       OR EXISTS (SELECT 1 FROM pg_proc AS proc CROSS JOIN LATERAL
          aclexplode(coalesce(proc.proacl,acldefault('f',proc.proowner))) AS acl
          WHERE proc.oid=v_signature::oid AND acl.grantee=0 AND acl.privilege_type='EXECUTE') THEN
      RAISE EXCEPTION 'VERIFICATION FAILED: Settings RPC security differs for %',v_signature;
    END IF;
  END LOOP;

  IF to_regprocedure('public.get_current_app_profile()') IS NULL THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: existing profile hydration RPC missing';
  END IF;
  SELECT lower(pg_get_functiondef('public.finalize_clinical_report(uuid,jsonb,text,text)'::regprocedure)) INTO v_definition;
  IF position('public.clinic_settings' IN v_definition)=0 OR position('v_clinic.name' IN v_definition)=0
     OR position('v_clinic.email' IN v_definition)=0 OR position('v_clinic.phone' IN v_definition)=0
     OR position('v_clinic.address' IN v_definition)=0
     OR position('get_clinic_settings' IN v_definition)>0 OR position('update_clinic_settings' IN v_definition)>0 THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: finalize_clinical_report compatibility changed';
  END IF;
END
$verify$;

SELECT 'VERIFICATION SUCCESSFUL: Simplified Supabase Settings foundation is contained and report-compatible' AS result;
