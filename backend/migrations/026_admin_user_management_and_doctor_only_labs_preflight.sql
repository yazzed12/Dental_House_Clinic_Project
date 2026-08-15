-- Migration 026 preflight. READ ONLY. Returns one consolidated result set.
WITH checks AS (
  SELECT 10 AS n,'users.columns'::text AS check_name,'INFO'::text AS status,
    coalesce((SELECT jsonb_agg(jsonb_build_object('name',column_name,'type',udt_schema||'.'||udt_name,'nullable',is_nullable) ORDER BY ordinal_position)::text
      FROM information_schema.columns WHERE table_schema='public' AND table_name='users'),'[]') AS details
  UNION ALL SELECT 20,'users.staff_counts','INFO',jsonb_build_object(
    'admin',count(*) FILTER(WHERE role::text='admin'),'doctor',count(*) FILTER(WHERE role::text='doctor'),
    'receptionist',count(*) FILTER(WHERE role::text='receptionist'),'other',count(*) FILTER(WHERE role::text NOT IN('admin','doctor','receptionist')),
    'unlinked_staff',count(*) FILTER(WHERE role::text IN('admin','doctor','receptionist') AND supabase_user_id IS NULL))::text FROM public.users
  UNION ALL SELECT 30,'users.identity_constraints','INFO',coalesce((SELECT jsonb_agg(jsonb_build_object('name',c.conname,'definition',pg_get_constraintdef(c.oid,true)) ORDER BY c.conname)::text FROM pg_constraint c WHERE c.conrelid='public.users'::regclass),'[]')
  UNION ALL SELECT 40,'users.identity_indexes','INFO',coalesce((SELECT jsonb_agg(pg_get_indexdef(i.indexrelid) ORDER BY i.indexrelid)::text FROM pg_index i WHERE i.indrelid='public.users'::regclass),'[]')
  UNION ALL SELECT 45,'users.normalized_clinic_email_duplicates',CASE WHEN count(*)=0 THEN 'CLEAN' ELSE 'CONFLICT' END,coalesce(jsonb_agg(email_key),'[]'::jsonb)::text FROM (SELECT lower(btrim(email::text)) email_key FROM public.users WHERE email IS NOT NULL GROUP BY lower(btrim(email::text)) HAVING count(*)>1) duplicates
  UNION ALL SELECT 50,'existing.admin_account',CASE WHEN count(*)=1 THEN 'CLEAN' ELSE 'CONFLICT' END,
    jsonb_build_object('matches',count(*),'ids',coalesce(jsonb_agg(id),'[]'::jsonb),'linked',count(*) FILTER(WHERE supabase_user_id IS NOT NULL))::text
    FROM public.users WHERE lower(email::text)='admin@admin.com' AND btrim(full_name::text)='Yazzed Elameir' AND role::text='admin'
  UNION ALL SELECT 60,'lab_actor.definition',CASE WHEN to_regprocedure('security.lab_actor()') IS NULL THEN 'CONFLICT' ELSE 'INFO' END,coalesce(pg_get_functiondef(to_regprocedure('security.lab_actor()')),'missing')
  UNION ALL SELECT 70,'lab.rpc_dependencies','INFO',coalesce((SELECT jsonb_agg(p.oid::regprocedure::text ORDER BY p.oid::regprocedure::text)::text FROM pg_depend d JOIN pg_proc p ON p.oid=d.objid WHERE d.refobjid=to_regprocedure('security.lab_actor()')),'[]')
  UNION ALL SELECT 80,'target.conflicts',CASE WHEN count(*)=0 THEN 'CLEAN' ELSE 'CONFLICT' END,coalesce(jsonb_agg(signature),'[]'::jsonb)::text FROM (VALUES
    ('security.admin_user_actor()'),('public.list_admin_users(text,text,boolean)'),('public.get_admin_user(uuid)'),
    ('public.update_admin_user(uuid,text,text,text,text,boolean)'),('public.create_admin_managed_staff(uuid,text,text,text,text,text,text)')
  ) target(signature) WHERE to_regprocedure(signature) IS NOT NULL
  UNION ALL SELECT 90,'auth.link_integrity','INFO',jsonb_build_object('broken_links',count(*))::text FROM public.users u LEFT JOIN auth.users a ON a.id=u.supabase_user_id WHERE u.supabase_user_id IS NOT NULL AND a.id IS NULL
), result AS (
  SELECT * FROM checks UNION ALL SELECT 999,'preflight.summary',CASE WHEN EXISTS(SELECT 1 FROM checks WHERE status='CONFLICT') THEN 'CONFLICT' ELSE 'CLEAN' END,
    CASE WHEN EXISTS(SELECT 1 FROM checks WHERE status='CONFLICT') THEN 'CONFLICT: Migration 026 assumptions require review' ELSE 'CLEAN: Migration 026 Admin/User/Lab assumptions match current schema' END
)
SELECT check_name,status,details FROM result ORDER BY n,check_name;
