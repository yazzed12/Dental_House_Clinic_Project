-- Migration 033 preflight. Read-only; run manually before Migration 033.
DO $preflight$
BEGIN
  IF to_regclass('public.users') IS NULL
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='deletion_status')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='deleted_at') THEN
    RAISE EXCEPTION 'CONFLICT: Migration 031 account deletion-state columns are missing';
  END IF;
  IF to_regprocedure('security.admin_user_actor()') IS NULL
     OR to_regprocedure('public.list_admin_users(text,text,boolean)') IS NULL
     OR to_regprocedure('public.get_admin_user(uuid)') IS NULL
     OR to_regprocedure('public.update_admin_user(uuid,text,text,text,text,boolean)') IS NULL THEN
    RAISE EXCEPTION 'CONFLICT: Admin user-management foundation is missing';
  END IF;
END
$preflight$;

WITH definitions AS (
  SELECT
    lower(pg_get_functiondef('public.list_admin_users(text,text,boolean)'::regprocedure)) AS list_definition,
    lower(pg_get_functiondef('public.get_admin_user(uuid)'::regprocedure)) AS detail_definition,
    lower(pg_get_functiondef('public.update_admin_user(uuid,text,text,text,text,boolean)'::regprocedure)) AS update_definition
), checks AS (
  SELECT 10 AS ordinal, 'users.deletion_columns' AS check_name, 'INFO' AS status,
    coalesce(jsonb_agg(jsonb_build_object('column',column_name,'type',data_type,'nullable',is_nullable) ORDER BY column_name),'[]'::jsonb)::text AS details
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='users' AND column_name IN ('deletion_status','deleted_at')
  UNION ALL SELECT 20,'admin.current_list_definition','INFO',list_definition FROM definitions
  UNION ALL SELECT 30,'admin.current_detail_definition','INFO',detail_definition FROM definitions
  UNION ALL SELECT 40,'admin.current_update_definition','INFO',update_definition FROM definitions
  UNION ALL SELECT 50,'admin.current_filters','INFO',jsonb_build_object(
    'listHasRoleFilter',list_definition LIKE '%p_role%',
    'listHasActiveFilter',list_definition LIKE '%p_is_active%',
    'listHasSearchFilter',list_definition LIKE '%p_search%',
    'listProjectsDeletionStatus',list_definition LIKE '%deletionstatus%',
    'detailProjectsDeletionStatus',detail_definition LIKE '%deletionstatus%'
  )::text FROM definitions
  UNION ALL SELECT 60,'users.deletion_state_counts','INFO',
    coalesce(jsonb_object_agg(deletion_status,row_count ORDER BY deletion_status),'{}'::jsonb)::text
  FROM (SELECT deletion_status,count(*) AS row_count FROM public.users GROUP BY deletion_status) AS counts
  UNION ALL SELECT 70,'users.pending_rows','INFO',jsonb_build_object('count',count(*))::text
  FROM public.users WHERE deletion_status='pending_auth_delete'
  UNION ALL SELECT 80,'users.deleted_rows','INFO',jsonb_build_object('count',count(*))::text
  FROM public.users WHERE deletion_status='deleted'
  UNION ALL SELECT 90,'admin.rpc_acls','INFO',coalesce(jsonb_agg(jsonb_build_object(
    'function',procedure.oid::regprocedure::text,'grantee',acl.grantee::regrole::text,'privilege',acl.privilege_type
  ) ORDER BY procedure.oid::regprocedure::text,acl.grantee),'[]'::jsonb)::text
  FROM pg_proc AS procedure
  CROSS JOIN LATERAL aclexplode(coalesce(procedure.proacl,acldefault('f',procedure.proowner))) AS acl
  WHERE procedure.oid IN (
    'public.list_admin_users(text,text,boolean)'::regprocedure,
    'public.get_admin_user(uuid)'::regprocedure,
    'public.update_admin_user(uuid,text,text,text,text,boolean)'::regprocedure
  )
  UNION ALL SELECT 100,'frontend.expected_projection','INFO',
    'Expected JSON names: deletionStatus; deletedAt is optional and safe'
  UNION ALL SELECT 110,'migration_033.existing_conflict',
    CASE WHEN list_definition LIKE '%deletionstatus%' OR detail_definition LIKE '%deletionstatus%'
      THEN 'CONFLICT' ELSE 'OK' END,
    CASE WHEN list_definition LIKE '%deletionstatus%' OR detail_definition LIKE '%deletionstatus%'
      THEN 'CONFLICT: Admin projections already contain deletionStatus; inspect whether Migration 033 was previously applied'
      ELSE 'Migration 033 projection delta is not already present' END
  FROM definitions
), summary AS (
  SELECT 999 AS ordinal,'summary' AS check_name,
    CASE WHEN bool_or(status='CONFLICT') THEN 'CONFLICT' ELSE 'CLEAN' END AS status,
    CASE WHEN bool_or(status='CONFLICT')
      THEN 'CONFLICT: Migration 033 Admin deleted-account projection does not match current schema; inspect the CONFLICT row above'
      ELSE 'CLEAN: Migration 033 Admin deleted-account projection matches current schema' END AS details
  FROM checks
)
SELECT check_name,status,details FROM (SELECT * FROM checks UNION ALL SELECT * FROM summary) AS report ORDER BY ordinal;
