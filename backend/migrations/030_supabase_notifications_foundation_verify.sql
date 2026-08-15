-- Migration 030 verifier: recipient containment and browser mutation boundary.
DO $verify$
DECLARE v_definition text;
BEGIN
  IF to_regclass('public.notifications') IS NULL THEN RAISE EXCEPTION 'notifications missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='notifications' AND column_name='recipient_user_id' AND udt_name='uuid')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='notifications' AND column_name='appointment_id' AND udt_name='uuid')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='notifications' AND column_name='read_at' AND udt_name='timestamptz') THEN
    RAISE EXCEPTION 'notification contract columns missing';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.notifications'::regclass) THEN RAISE EXCEPTION 'notifications RLS disabled'; END IF;
  IF has_table_privilege('anon','public.notifications','SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated','public.notifications','SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'browser has direct notification table privilege';
  END IF;
  IF EXISTS (SELECT 1 FROM public.notifications n LEFT JOIN public.users u ON u.id=n.recipient_user_id
              WHERE n.recipient_user_id IS NOT NULL AND u.id IS NULL) THEN RAISE EXCEPTION 'invalid recipient link'; END IF;
  IF EXISTS (SELECT 1 FROM public.notifications WHERE type='appointment_arrived' AND appointment_id IS NOT NULL
              GROUP BY recipient_user_id,appointment_id,type HAVING count(*)>1) THEN RAISE EXCEPTION 'duplicate appointment arrival notification'; END IF;
  IF to_regprocedure('security.notification_actor()') IS NULL
     OR to_regprocedure('public.list_my_notifications(integer,timestamp with time zone,uuid)') IS NULL
     OR to_regprocedure('public.get_my_unread_notification_count()') IS NULL
     OR to_regprocedure('public.mark_my_notification_read(uuid)') IS NULL
     OR to_regprocedure('public.mark_all_my_notifications_read()') IS NULL THEN RAISE EXCEPTION 'notification RPC missing'; END IF;
  IF has_function_privilege('anon','public.list_my_notifications(integer,timestamp with time zone,uuid)','EXECUTE')
     OR has_function_privilege('anon','public.mark_my_notification_read(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.list_my_notifications(integer,timestamp with time zone,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'notification RPC ACL mismatch';
  END IF;
  SELECT lower(pg_get_functiondef('security.notification_actor()'::regprocedure)) INTO v_definition;
  IF v_definition NOT LIKE '%supabase_user_id=auth.uid()%'
     OR v_definition NOT LIKE '%is_active=true%'
     OR v_definition NOT LIKE '%approved_at is not null%' THEN RAISE EXCEPTION 'actor identity is not fail closed'; END IF;
  SELECT lower(pg_get_functiondef('public.list_my_notifications(integer,timestamp with time zone,uuid)'::regprocedure)) INTO v_definition;
  IF v_definition NOT LIKE '%recipient_user_id=v_actor_id%' OR v_definition LIKE '%p_recipient%' THEN RAISE EXCEPTION 'list ownership mismatch'; END IF;
  SELECT lower(pg_get_functiondef('public.mark_my_notification_read(uuid)'::regprocedure)) INTO v_definition;
  IF v_definition NOT LIKE '%notification.id=p_notification_id%' OR v_definition NOT LIKE '%recipient_user_id=v_actor_id%' THEN RAISE EXCEPTION 'single-read ownership mismatch'; END IF;
  SELECT lower(pg_get_functiondef('public.mark_appointment_arrived(uuid)'::regprocedure)) INTO v_definition;
  IF v_definition NOT LIKE '%v_doctor_id%' OR v_definition NOT LIKE '%on conflict (recipient_user_id,appointment_id,type)%'
     OR v_definition LIKE '%recipient_user_id is null%' AND v_definition NOT LIKE '%where recipient_user_id is not null%' THEN
    RAISE EXCEPTION 'arrival producer is not assigned-Doctor/idempotent';
  END IF;
END
$verify$;

SELECT 'VERIFICATION SUCCESSFUL: Supabase Notifications are recipient-contained' AS result;
