-- READ-ONLY preflight for Migration 027.
WITH checks(sort_order,check_name,status,details) AS (
  SELECT 10,'migration_026.functions',CASE WHEN count(*)=4 THEN 'PASS' ELSE 'CONFLICT' END,
    jsonb_build_object('found',count(*))::text
  FROM unnest(ARRAY[
    'public.list_admin_users(text,text,boolean)',
    'public.get_admin_user(uuid)',
    'public.update_admin_user(uuid,text,text,text,text,boolean)',
    'public.create_admin_managed_staff(uuid,text,text,text,text,text,text)'
  ]) signature WHERE to_regprocedure(signature) IS NOT NULL
  UNION ALL
  SELECT 20,'public.users.role_coverage','INFO',
    coalesce(jsonb_object_agg(role_name,row_count),'{}'::jsonb)::text
  FROM (SELECT coalesce(role::text,'<NULL>') role_name,count(*) row_count FROM public.users GROUP BY role::text) roles
  UNION ALL
  SELECT 30,'users.normalized_clinic_email_unique',CASE WHEN EXISTS(
    SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='users'
      AND indexname='uq_users_normalized_clinic_email' AND indexdef ILIKE 'CREATE UNIQUE INDEX%'
  ) THEN 'PASS' ELSE 'CONFLICT' END,'Required normalized unique index on public.users.email'
  UNION ALL
  SELECT 40,'users.normalized_personal_email_unique',CASE WHEN EXISTS(
    SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='users'
      AND indexname='uq_users_normalized_personal_email' AND indexdef ILIKE 'CREATE UNIQUE INDEX%'
  ) THEN 'PASS' ELSE 'CONFLICT' END,'Required normalized unique index on public.users.personal_email'
  UNION ALL
  SELECT 50,'users.supabase_user_id_unique',CASE WHEN EXISTS(
    SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='users'
      AND indexname='uq_users_supabase_user_id' AND indexdef ILIKE 'CREATE UNIQUE INDEX%'
  ) THEN 'PASS' ELSE 'CONFLICT' END,'Required unique linkage index on public.users.supabase_user_id'
  UNION ALL
  SELECT 60,'users.normalized_conflicts',CASE WHEN clinic_duplicates=0 AND personal_duplicates=0 AND link_duplicates=0 THEN 'PASS' ELSE 'CONFLICT' END,
    jsonb_build_object('clinic_email_duplicates',clinic_duplicates,'personal_email_duplicates',personal_duplicates,'supabase_user_id_duplicates',link_duplicates)::text
  FROM (SELECT
    (SELECT count(*) FROM (SELECT lower(btrim(email::text)) FROM public.users WHERE email IS NOT NULL GROUP BY 1 HAVING count(*)>1) d) clinic_duplicates,
    (SELECT count(*) FROM (SELECT lower(btrim(personal_email)) FROM public.users WHERE personal_email IS NOT NULL GROUP BY 1 HAVING count(*)>1) d) personal_duplicates,
    (SELECT count(*) FROM (SELECT supabase_user_id FROM public.users WHERE supabase_user_id IS NOT NULL GROUP BY 1 HAVING count(*)>1) d) link_duplicates
  ) duplicate_counts
  UNION ALL
  SELECT 70,'admin_actor.definition',CASE WHEN replace(lower(pg_get_functiondef('security.admin_user_actor()'::regprocedure)),' ','')
    LIKE '%supabase_user_id=auth.uid()%role::text=''admin''%is_active=true%approved_atisnotnull%' THEN 'PASS' ELSE 'CONFLICT' END,
    'Caller must resolve through auth.uid() to an active, approved Admin'
  UNION ALL
  SELECT 80,'lab_actor.doctor_only',CASE WHEN replace(lower(pg_get_functiondef('security.lab_actor()'::regprocedure)),' ','')
    LIKE '%role::text=''doctor''%' AND replace(lower(pg_get_functiondef('security.lab_actor()'::regprocedure)),' ','') NOT LIKE '%role::text=''admin''%' THEN 'PASS' ELSE 'CONFLICT' END,
    'Lab actor must remain Doctor-only'
  UNION ALL
  SELECT 90,'staff_creation.roles',CASE WHEN replace(lower(pg_get_functiondef(
    'public.create_admin_managed_staff(uuid,text,text,text,text,text,text)'::regprocedure)),' ','')
    LIKE '%notin(''doctor'',''receptionist'')%' THEN 'PASS' ELSE 'CONFLICT' END,
    'Creation must remain limited to Doctor and Receptionist'
  UNION ALL
  SELECT 100,'admin_rpc.acls',CASE WHEN bool_and(authenticated_can_execute AND NOT anon_can_execute AND NOT public_can_execute)
    THEN 'PASS' ELSE 'CONFLICT' END,jsonb_agg(jsonb_build_object('signature',signature,'authenticated',authenticated_can_execute,'anon',anon_can_execute,'public',public_can_execute))::text
  FROM (
    SELECT signature,
      has_function_privilege('authenticated',signature,'EXECUTE') authenticated_can_execute,
      has_function_privilege('anon',signature,'EXECUTE') anon_can_execute,
      EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
        WHERE p.oid=signature::regprocedure AND acl.grantee=0 AND acl.privilege_type='EXECUTE') public_can_execute
    FROM unnest(ARRAY['public.list_admin_users(text,text,boolean)','public.get_admin_user(uuid)','public.update_admin_user(uuid,text,text,text,text,boolean)']) signature
  ) acl_state
  UNION ALL
  SELECT 110,'auth.linkage_integrity',CASE WHEN count(*)=0 THEN 'PASS' ELSE 'CONFLICT' END,
    jsonb_build_object('broken_links',count(*))::text
  FROM public.users u LEFT JOIN auth.users a ON a.id=u.supabase_user_id
  WHERE u.supabase_user_id IS NOT NULL AND a.id IS NULL
), summary AS (
  SELECT coalesce(bool_and(status<>'CONFLICT'),false) clean FROM checks
)
SELECT check_name,status,details FROM (
SELECT sort_order,check_name,status,details FROM checks
UNION ALL
SELECT 999,'migration_027.readiness',CASE WHEN clean THEN 'CLEAN' ELSE 'CONFLICT' END,
  CASE WHEN clean THEN 'CLEAN: Migration 027 Admin User Management assumptions match current schema'
       ELSE 'CONFLICT: Resolve failed checks before applying Migration 027' END
FROM summary
) consolidated
ORDER BY sort_order;
