-- Migration 030: Supabase recipient-contained in-app notification foundation.
-- Ambiguous NULL-owned legacy rows remain preserved and inert. Frontend cutover is out of scope.
BEGIN;

DO $precondition$
BEGIN
    IF to_regclass('public.notifications') IS NULL
       OR to_regclass('public.users') IS NULL
       OR to_regclass('public.appointments') IS NULL
       OR to_regprocedure('security.current_app_user_id()') IS NULL
       OR to_regprocedure('public.mark_appointment_arrived(uuid)') IS NULL THEN
        RAISE EXCEPTION 'NOTIFICATIONS_FOUNDATION_MISSING';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='notifications'
                  AND column_name IN ('recipient_user_id','appointment_id','read_at'))
       OR to_regprocedure('security.notification_actor()') IS NOT NULL
       OR to_regprocedure('public.list_my_notifications(integer,timestamp with time zone,uuid)') IS NOT NULL
       OR to_regprocedure('public.get_my_unread_notification_count()') IS NOT NULL
       OR to_regprocedure('public.mark_my_notification_read(uuid)') IS NOT NULL
       OR to_regprocedure('public.mark_all_my_notifications_read()') IS NOT NULL THEN
        RAISE EXCEPTION 'NOTIFICATIONS_FOUNDATION_TARGET_CONFLICT';
    END IF;
    IF EXISTS (SELECT 1 FROM public.notifications WHERE id IS NULL OR id::text !~*
       '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') THEN
        RAISE EXCEPTION 'NOTIFICATIONS_ID_UUID_CONFLICT';
    END IF;
    IF EXISTS (SELECT 1 FROM public.notifications notification LEFT JOIN public.users app_user
                ON app_user.id::text=notification.user_id::text
               WHERE notification.user_id IS NOT NULL AND app_user.id IS NULL) THEN
        RAISE EXCEPTION 'NOTIFICATIONS_USER_LINK_CONFLICT';
    END IF;
    IF EXISTS (SELECT 1 FROM public.notifications
                WHERE title IS NULL OR body IS NULL OR type IS NULL OR created_at IS NULL) THEN
        RAISE EXCEPTION 'NOTIFICATIONS_REQUIRED_CONTENT_CONFLICT';
    END IF;
END
$precondition$;

-- Normalize only compatible legacy types required by the hardened UUID/timestamptz contract.
ALTER TABLE public.notifications ALTER COLUMN id TYPE uuid USING id::text::uuid;
ALTER TABLE public.notifications ALTER COLUMN title TYPE text USING title::text;
ALTER TABLE public.notifications ALTER COLUMN body TYPE text USING body::text;
ALTER TABLE public.notifications ALTER COLUMN type TYPE text USING type::text;
ALTER TABLE public.notifications ALTER COLUMN created_at TYPE timestamptz
  USING CASE WHEN pg_typeof(created_at)::text='timestamp without time zone'
             THEN created_at AT TIME ZONE 'UTC' ELSE created_at::timestamptz END;
ALTER TABLE public.notifications ALTER COLUMN title SET NOT NULL;
ALTER TABLE public.notifications ALTER COLUMN body SET NOT NULL;
ALTER TABLE public.notifications ALTER COLUMN type SET NOT NULL;
ALTER TABLE public.notifications ALTER COLUMN created_at SET NOT NULL;
ALTER TABLE public.notifications ALTER COLUMN created_at SET DEFAULT clock_timestamp();
ALTER TABLE public.notifications ALTER COLUMN id SET DEFAULT gen_random_uuid();

ALTER TABLE public.notifications
  ADD COLUMN recipient_user_id uuid NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  ADD COLUMN appointment_id uuid NULL REFERENCES public.appointments(id) ON DELETE RESTRICT,
  ADD COLUMN read_at timestamptz NULL;

-- Deterministic legacy ownership is retained; NULL ownership is deliberately not guessed.
UPDATE public.notifications notification
   SET recipient_user_id=notification.user_id::text::uuid,
       read_at=CASE WHEN notification."read"::text IN ('1','true','t')
                    THEN notification.created_at ELSE NULL END
 WHERE notification.user_id IS NOT NULL;

CREATE INDEX notifications_recipient_created_idx
  ON public.notifications(recipient_user_id,created_at DESC,id DESC)
  WHERE recipient_user_id IS NOT NULL;
CREATE INDEX notifications_recipient_unread_idx
  ON public.notifications(recipient_user_id,created_at DESC,id DESC)
  WHERE recipient_user_id IS NOT NULL AND read_at IS NULL;
CREATE UNIQUE INDEX notifications_arrival_once_idx
  ON public.notifications(recipient_user_id,appointment_id,type)
  WHERE recipient_user_id IS NOT NULL AND appointment_id IS NOT NULL AND type='appointment_arrived';

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.notifications FROM PUBLIC,anon,authenticated;

CREATE FUNCTION security.notification_actor()
RETURNS TABLE(id uuid,role text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
  SELECT app_user.id,app_user.role::text
    FROM public.users app_user
   WHERE app_user.supabase_user_id=auth.uid()
     AND app_user.is_active=true
     AND app_user.approved_at IS NOT NULL
   LIMIT 1
$function$;

CREATE FUNCTION public.list_my_notifications(
  p_limit integer DEFAULT 50,
  p_before_created_at timestamptz DEFAULT NULL,
  p_before_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_limit integer; v_result jsonb;
BEGIN
  SELECT actor.id INTO v_actor_id FROM security.notification_actor() actor;
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'NOTIFICATIONS_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  IF (p_before_created_at IS NULL)<>(p_before_id IS NULL) THEN
    RAISE EXCEPTION 'NOTIFICATIONS_CURSOR_INVALID' USING ERRCODE='22023';
  END IF;
  v_limit:=least(greatest(coalesce(p_limit,50),1),100);
  SELECT coalesce(jsonb_agg(row.payload ORDER BY row.created_at DESC,row.id DESC),'[]'::jsonb) INTO v_result
    FROM (
      SELECT notification.created_at,notification.id,jsonb_build_object(
        'id',notification.id,'type',notification.type,'title',notification.title,
        'body',notification.body,'appointmentId',notification.appointment_id,
        'createdAt',notification.created_at,'readAt',notification.read_at,
        'read',notification.read_at IS NOT NULL) payload
        FROM public.notifications notification
       WHERE notification.recipient_user_id=v_actor_id
         AND (p_before_created_at IS NULL OR (notification.created_at,notification.id)<(p_before_created_at,p_before_id))
       ORDER BY notification.created_at DESC,notification.id DESC
       LIMIT v_limit
    ) row;
  RETURN v_result;
END
$function$;

CREATE FUNCTION public.get_my_unread_notification_count()
RETURNS bigint
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_count bigint;
BEGIN
  SELECT actor.id INTO v_actor_id FROM security.notification_actor() actor;
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'NOTIFICATIONS_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  SELECT count(*) INTO v_count FROM public.notifications notification
   WHERE notification.recipient_user_id=v_actor_id AND notification.read_at IS NULL;
  RETURN v_count;
END
$function$;

CREATE FUNCTION public.mark_my_notification_read(p_notification_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_read_at timestamptz;
BEGIN
  SELECT actor.id INTO v_actor_id FROM security.notification_actor() actor;
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'NOTIFICATIONS_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  UPDATE public.notifications notification SET read_at=coalesce(notification.read_at,clock_timestamp())
   WHERE notification.id=p_notification_id AND notification.recipient_user_id=v_actor_id
   RETURNING notification.read_at INTO v_read_at;
  IF v_read_at IS NULL THEN RAISE EXCEPTION 'NOTIFICATION_NOT_FOUND' USING ERRCODE='P4040'; END IF;
  RETURN jsonb_build_object('id',p_notification_id,'readAt',v_read_at,'read',true);
END
$function$;

CREATE FUNCTION public.mark_all_my_notifications_read()
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_count bigint;
BEGIN
  SELECT actor.id INTO v_actor_id FROM security.notification_actor() actor;
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'NOTIFICATIONS_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  UPDATE public.notifications notification SET read_at=clock_timestamp()
   WHERE notification.recipient_user_id=v_actor_id AND notification.read_at IS NULL;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  RETURN v_count;
END
$function$;

-- Appointment arrival remains one authoritative transaction and one assigned-Doctor event.
CREATE OR REPLACE FUNCTION public.mark_appointment_arrived(p_appointment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_actor_id uuid; v_actor_role text; v_patient_name text; v_appointment_time text; v_doctor_id uuid;
BEGIN
  v_actor_id:=security.current_app_user_id();
  v_actor_role:=security.current_app_role();
  IF v_actor_id IS NULL OR v_actor_role NOT IN ('doctor','receptionist','admin') THEN
    RAISE EXCEPTION 'Insufficient permissions' USING ERRCODE='42501';
  END IF;
  SELECT patient.name::text,appointment.time::text,appointment.doctor_id
    INTO v_patient_name,v_appointment_time,v_doctor_id
    FROM public.appointments appointment JOIN public.patients patient ON patient.id=appointment.patient_id
   WHERE appointment.id=p_appointment_id FOR UPDATE OF appointment;
  IF NOT FOUND THEN RAISE EXCEPTION 'Appointment not found' USING ERRCODE='P0002'; END IF;
  IF v_doctor_id IS NULL THEN RAISE EXCEPTION 'Appointment Doctor is required' USING ERRCODE='22023'; END IF;
  IF v_actor_role='doctor' AND v_doctor_id<>v_actor_id THEN
    RAISE EXCEPTION 'Insufficient permissions' USING ERRCODE='42501';
  END IF;
  UPDATE public.appointments SET status='pending' WHERE id=p_appointment_id;
  INSERT INTO public.notifications(
    id,recipient_user_id,appointment_id,type,title,body,created_at,read_at,"read")
  VALUES(gen_random_uuid(),v_doctor_id,p_appointment_id,'appointment_arrived','Patient Arrived',
    format('%s has arrived for their %s appointment.',v_patient_name,v_appointment_time),clock_timestamp(),NULL,0)
  ON CONFLICT (recipient_user_id,appointment_id,type)
    WHERE recipient_user_id IS NOT NULL AND appointment_id IS NOT NULL AND type='appointment_arrived'
  DO NOTHING;
  RETURN security.appointment_projection(p_appointment_id);
END
$function$;

REVOKE ALL ON FUNCTION security.notification_actor() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.list_my_notifications(integer,timestamptz,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_unread_notification_count() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_my_notification_read(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_all_my_notifications_read() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_my_notifications(integer,timestamptz,uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_my_unread_notification_count() FROM anon;
REVOKE EXECUTE ON FUNCTION public.mark_my_notification_read(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.mark_all_my_notifications_read() FROM anon;
GRANT EXECUTE ON FUNCTION public.list_my_notifications(integer,timestamptz,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_unread_notification_count() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_my_notification_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_all_my_notifications_read() TO authenticated;

COMMIT;
