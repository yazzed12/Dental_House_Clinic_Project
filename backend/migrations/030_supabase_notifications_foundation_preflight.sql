-- Migration 030 preflight: read-only inventory for recipient-contained notifications.
-- Run manually before Migration 030. This file does not mutate schema or data.
DO $preflight$
BEGIN
    IF to_regclass('public.notifications') IS NULL
       OR to_regclass('public.users') IS NULL
       OR to_regclass('public.appointments') IS NULL THEN
        RAISE EXCEPTION 'CONFLICT: required notifications/users/appointments relation is missing';
    END IF;
    IF to_regprocedure('security.current_app_user_id()') IS NULL
       OR to_regprocedure('public.mark_appointment_arrived(uuid)') IS NULL THEN
        RAISE EXCEPTION 'CONFLICT: required identity or arrival function is missing';
    END IF;
    IF EXISTS (
        SELECT 1 FROM (VALUES ('id'),('title'),('body'),('type'),('read'),('created_at'),('user_id')) expected(column_name)
         WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns actual
                            WHERE actual.table_schema='public' AND actual.table_name='notifications'
                              AND actual.column_name=expected.column_name)
    ) THEN RAISE EXCEPTION 'CONFLICT: legacy notifications columns are incomplete'; END IF;
END
$preflight$;

WITH relation_state AS (
    SELECT class.oid,class.relrowsecurity,class.relforcerowsecurity,
           pg_get_userbyid(class.relowner) owner
      FROM pg_class class WHERE class.oid='public.notifications'::regclass
), columns AS (
    SELECT column_name,data_type,udt_name,is_nullable,column_default
      FROM information_schema.columns
     WHERE table_schema='public' AND table_name='notifications'
), checks AS (
    SELECT 10 ordinal,'schema.notifications' check_name,'INFO' status,
           coalesce(jsonb_agg(to_jsonb(columns) ORDER BY column_name),'[]'::jsonb)::text details FROM columns
    UNION ALL
    SELECT 20,'schema.compatibility',CASE WHEN
           (SELECT data_type IN ('uuid','text','character varying') FROM columns WHERE column_name='id')
       AND (SELECT data_type IN ('uuid','text','character varying') FROM columns WHERE column_name='user_id')
       AND NOT EXISTS (SELECT 1 FROM public.notifications WHERE id IS NULL OR id::text !~*
           '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
       AND NOT EXISTS (SELECT 1 FROM public.notifications WHERE user_id IS NOT NULL AND user_id::text !~*
           '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
       AND NOT EXISTS (SELECT 1 FROM public.notifications WHERE title IS NULL OR body IS NULL OR type IS NULL OR created_at IS NULL)
       THEN 'OK' ELSE 'CONFLICT' END,
       'IDs must be UUID/castable UUID; title/body/type/created_at must be populated'
    UNION ALL
    SELECT 30,'data.rows','INFO',jsonb_build_object(
           'total',count(*),'legacyUserIdPresent',count(*) FILTER(WHERE user_id IS NOT NULL),
           'nullUserId',count(*) FILTER(WHERE user_id IS NULL),
           'readLegacy',count(*) FILTER(WHERE "read"::text IN ('1','true','t')),
           'unreadLegacy',count(*) FILTER(WHERE coalesce("read"::text,'0') NOT IN ('1','true','t')))::text
      FROM public.notifications
    UNION ALL
    SELECT 40,'data.rows_per_deterministic_recipient','INFO',coalesce(jsonb_agg(
           jsonb_build_object('userId',rows.user_id,'count',rows.row_count) ORDER BY rows.user_id),'[]'::jsonb)::text
      FROM (SELECT user_id::text user_id,count(*) row_count FROM public.notifications
             WHERE user_id IS NOT NULL GROUP BY user_id) rows
    UNION ALL
    SELECT 50,'data.invalid_user_links',CASE WHEN count(*)=0 THEN 'OK' ELSE 'CONFLICT' END,
           jsonb_build_object('count',count(*))::text
      FROM public.notifications notification LEFT JOIN public.users app_user
        ON app_user.id::text=notification.user_id::text
     WHERE notification.user_id IS NOT NULL AND app_user.id IS NULL
    UNION ALL
    SELECT 60,'security.rls','INFO',jsonb_build_object('enabled',relrowsecurity,'forced',relforcerowsecurity,'owner',owner)::text
      FROM relation_state
    UNION ALL
    SELECT 70,'security.table_acl','INFO',coalesce(jsonb_agg(jsonb_build_object(
           'grantee',coalesce(role.rolname,'PUBLIC'),'privilege',entry.privilege_type)
           ORDER BY coalesce(role.rolname,'PUBLIC'),entry.privilege_type),'[]'::jsonb)::text
      FROM relation_state state
      CROSS JOIN LATERAL aclexplode(coalesce((SELECT relacl FROM pg_class WHERE oid=state.oid),
                                               acldefault('r',(SELECT relowner FROM pg_class WHERE oid=state.oid)))) entry
      LEFT JOIN pg_roles role ON role.oid=entry.grantee
    UNION ALL
    SELECT 80,'schema.indexes','INFO',coalesce(jsonb_agg(indexdef ORDER BY indexname),'[]'::jsonb)::text
      FROM pg_indexes WHERE schemaname='public' AND tablename='notifications'
    UNION ALL
    SELECT 90,'schema.triggers','INFO',coalesce(jsonb_agg(pg_get_triggerdef(trigger.oid) ORDER BY trigger.tgname),'[]'::jsonb)::text
      FROM pg_trigger trigger WHERE trigger.tgrelid='public.notifications'::regclass AND NOT trigger.tgisinternal
    UNION ALL
    SELECT 100,'schema.function_references','INFO',coalesce(jsonb_agg(proc.oid::regprocedure::text ORDER BY proc.oid::regprocedure::text),'[]'::jsonb)::text
      FROM pg_proc proc WHERE proc.prokind='f' AND lower(pg_get_functiondef(proc.oid)) LIKE '%public.notifications%'
    UNION ALL
    SELECT 110,'arrival.current_definition','INFO',pg_get_functiondef('public.mark_appointment_arrived(uuid)'::regprocedure)
    UNION ALL
    SELECT 120,'arrival.current_global_producer',CASE WHEN lower(pg_get_functiondef(
           'public.mark_appointment_arrived(uuid)'::regprocedure)) LIKE '%recipient_user_id%'
           THEN 'OK' ELSE 'EXPECTED_DELTA' END,
           'Current producer has no explicit recipient and no per-appointment idempotency key'
    UNION ALL
    SELECT 130,'arrival.duplicate_candidates','INFO',jsonb_build_object('legacyPatientArrivedRows',count(*))::text
      FROM public.notifications WHERE lower(title)='patient arrived'
    UNION ALL
    SELECT 140,'identity.helper','OK',pg_get_functiondef('security.current_app_user_id()'::regprocedure)
    UNION ALL
    SELECT 150,'target.conflicts',CASE WHEN count(*)=0 THEN 'OK' ELSE 'CONFLICT' END,
           coalesce(jsonb_agg(signature),'[]'::jsonb)::text
      FROM (SELECT signature FROM (VALUES
          ('security.notification_actor()'),
          ('public.list_my_notifications(integer,timestamp with time zone,uuid)'),
          ('public.get_my_unread_notification_count()'),
          ('public.mark_my_notification_read(uuid)'),
          ('public.mark_all_my_notifications_read()')) wanted(signature)
          WHERE to_regprocedure(signature) IS NOT NULL
          UNION ALL
          SELECT 'target notification columns already exist' WHERE EXISTS(
              SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='notifications'
                AND column_name IN ('recipient_user_id','appointment_id','read_at'))
          UNION ALL
          SELECT 'target notification indexes already exist' WHERE to_regclass('public.notifications_recipient_created_idx') IS NOT NULL
             OR to_regclass('public.notifications_recipient_unread_idx') IS NOT NULL
             OR to_regclass('public.notifications_arrival_once_idx') IS NOT NULL) conflicts
), summary AS (
    SELECT 999 ordinal,'summary' check_name,
           CASE WHEN bool_or(status='CONFLICT') THEN 'CONFLICT' ELSE 'CLEAN' END status,
           CASE WHEN bool_or(status='CONFLICT')
                THEN 'CONFLICT: Migration 030 Notifications assumptions do not match current schema'
                ELSE 'CLEAN: Migration 030 Notifications assumptions match current schema' END details
      FROM checks
)
SELECT check_name,status,details FROM (SELECT * FROM checks UNION ALL SELECT * FROM summary) output ORDER BY ordinal;
