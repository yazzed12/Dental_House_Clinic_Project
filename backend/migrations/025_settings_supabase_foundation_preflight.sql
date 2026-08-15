-- READ-ONLY preflight for Migration 025: Simplified Supabase Settings.
-- One consolidated result set for Supabase SQL Editor. No mutations.

WITH target_functions(signature) AS (
    VALUES
      ('security.settings_actor()'),
      ('public.get_clinic_settings()'),
      ('public.update_clinic_settings(text,text,text,text)'),
      ('public.update_current_app_profile(text,text,text)')
), checks AS (
    SELECT 10 AS ordering,'clinic_settings.relation'::text AS check_name,
      CASE WHEN to_regclass('public.clinic_settings') IS NULL THEN 'CONFLICT' ELSE 'CLEAN' END AS status,
      coalesce(to_regclass('public.clinic_settings')::text,'missing') AS details

    UNION ALL
    SELECT 20,'clinic_settings.columns','INFO',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'name',column_name,'type',data_type,'udt',udt_schema||'.'||udt_name,
      'nullable',is_nullable,'default',column_default) ORDER BY ordinal_position)::text
      FROM information_schema.columns WHERE table_schema='public' AND table_name='clinic_settings'),'[]')

    UNION ALL
    SELECT 30,'clinic_settings.required_columns',
      CASE WHEN (SELECT count(*) FROM information_schema.columns WHERE table_schema='public'
        AND table_name='clinic_settings' AND column_name IN ('id','name','email','phone','address',
        'working_hours','appointment_duration','services','notification_settings'))=9 THEN 'CLEAN' ELSE 'CONFLICT' END,
      'Required existing visible and hidden fields: id,name,email,phone,address,working_hours,appointment_duration,services,notification_settings'

    UNION ALL
    SELECT 40,'clinic_settings.row_model',CASE WHEN count(*)=1 THEN 'CLEAN' ELSE 'CONFLICT' END,
      jsonb_build_object('row_count',count(*),'ids',coalesce(jsonb_agg(id ORDER BY id),'[]'::jsonb))::text
      FROM public.clinic_settings

    UNION ALL
    SELECT 50,'clinic_settings.security','INFO',jsonb_build_object(
      'owner',pg_get_userbyid(relation.relowner),'rls_enabled',relation.relrowsecurity,
      'rls_forced',relation.relforcerowsecurity,'acl',relation.relacl,
      'authenticated_select',has_table_privilege('authenticated',relation.oid,'SELECT'),
      'authenticated_update',has_table_privilege('authenticated',relation.oid,'UPDATE'),
      'anon_access',has_table_privilege('anon',relation.oid,'SELECT,INSERT,UPDATE,DELETE'),
      'public_access',EXISTS (SELECT 1 FROM aclexplode(coalesce(relation.relacl,acldefault('r',relation.relowner))) AS acl
        WHERE acl.grantee=0 AND acl.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE'))
      )::text FROM pg_class AS relation WHERE relation.oid=to_regclass('public.clinic_settings')

    UNION ALL
    SELECT 60,'clinic_settings.constraints','INFO',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'name',constraint_record.conname,'type',constraint_record.contype,
      'definition',pg_get_constraintdef(constraint_record.oid,true)) ORDER BY constraint_record.conname)::text
      FROM pg_constraint AS constraint_record WHERE constraint_record.conrelid=to_regclass('public.clinic_settings')),'[]')

    UNION ALL
SELECT 70,'clinic_settings.function_references','INFO',coalesce((
  SELECT jsonb_agg(
    proc.oid::regprocedure::text
    ORDER BY proc.oid::regprocedure::text
  )::text
  FROM pg_proc AS proc
  JOIN pg_namespace AS namespace
    ON namespace.oid = proc.pronamespace
  WHERE namespace.nspname IN ('public','security')
    AND proc.prokind IN ('f','p')
    AND lower(pg_get_functiondef(proc.oid)) LIKE '%public.clinic_settings%'
),'[]')
    UNION ALL
    SELECT 80,'users.profile_columns',
      CASE WHEN (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='users'
        AND column_name IN ('id','full_name','email','phone','specialization','role','is_active','approved_at','supabase_user_id'))=9
        THEN 'CLEAN' ELSE 'CONFLICT' END,
      coalesce((SELECT jsonb_agg(jsonb_build_object('name',column_name,'type',udt_schema||'.'||udt_name,
        'nullable',is_nullable) ORDER BY ordinal_position)::text FROM information_schema.columns
        WHERE table_schema='public' AND table_name='users'
          AND column_name IN ('id','full_name','email','phone','specialization','role','is_active','approved_at','supabase_user_id')),'[]')

    UNION ALL
    SELECT 90,'users.identity_mapping','INFO',jsonb_build_object(
      'user_count',(SELECT count(*) FROM public.users),
      'linked_count',(SELECT count(*) FROM public.users WHERE supabase_user_id IS NOT NULL),
      'active_approved_linked',(SELECT count(*) FROM public.users WHERE supabase_user_id IS NOT NULL
         AND is_active=true AND approved_at IS NOT NULL))::text

    UNION ALL
    SELECT 100,'existing.get_current_app_profile',
      CASE WHEN to_regprocedure('public.get_current_app_profile()') IS NULL THEN 'CONFLICT' ELSE 'CLEAN' END,
      coalesce(to_regprocedure('public.get_current_app_profile()')::text,'missing')

    UNION ALL
    SELECT 110,'existing.finalize_clinical_report',
      CASE WHEN to_regprocedure('public.finalize_clinical_report(uuid,jsonb,text,text)') IS NULL THEN 'CONFLICT' ELSE 'CLEAN' END,
      coalesce(pg_get_functiondef(to_regprocedure('public.finalize_clinical_report(uuid,jsonb,text,text)')),'missing')

    UNION ALL
    SELECT 120,'target.function.'||target.signature,
      CASE WHEN to_regprocedure(target.signature) IS NULL THEN 'CLEAN' ELSE 'CONFLICT' END,
      coalesce(to_regprocedure(target.signature)::text,'not present')
      FROM target_functions AS target

    UNION ALL
    SELECT 130,'legacy_ui.schema_alignment','INFO',
      'Visible target fields: profile full_name/phone/specialization/login email; clinic name/email/phone/address. Hidden clinic fields are preserved.'

    UNION ALL
    SELECT 140,'authorization.helpers','INFO',coalesce((SELECT jsonb_agg(proc.oid::regprocedure::text ORDER BY proc.oid::regprocedure::text)::text
      FROM pg_proc AS proc JOIN pg_namespace AS namespace ON namespace.oid=proc.pronamespace
      WHERE namespace.nspname='security' AND (proc.proname LIKE '%actor%' OR proc.proname LIKE '%active%')),'[]')
), final_checks AS (
  SELECT * FROM checks
  UNION ALL
  SELECT 999,'preflight.summary',
    CASE WHEN EXISTS (SELECT 1 FROM checks WHERE status='CONFLICT') THEN 'CONFLICT' ELSE 'CLEAN' END,
    CASE WHEN EXISTS (SELECT 1 FROM checks WHERE status='CONFLICT')
      THEN 'CONFLICT: Migration 025 Settings assumptions do not match current schema'
      ELSE 'CLEAN: Migration 025 Settings assumptions match current schema' END
)
SELECT check_name,status,details FROM final_checks ORDER BY ordering,check_name;
