-- Migration 033: durable Admin projection and editing rules for account tombstones.
BEGIN;

CREATE OR REPLACE FUNCTION public.list_admin_users(p_search text DEFAULT NULL,p_role text DEFAULT NULL,p_is_active boolean DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_actor uuid; v_result jsonb;
BEGIN
  v_actor:=security.admin_user_actor();
  IF v_actor IS NULL THEN RAISE EXCEPTION 'ADMIN_USERS_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  IF p_role IS NOT NULL AND btrim(p_role)<>'' AND NOT EXISTS(
    SELECT 1 FROM public.users existing_user WHERE existing_user.role::text=lower(btrim(p_role))
  ) THEN RAISE EXCEPTION 'ADMIN_USERS_ROLE_INVALID' USING ERRCODE='22023'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',u.id,'fullName',u.full_name,'clinicEmail',u.email,'role',u.role::text,'phone',u.phone,
    'specialization',u.specialization,'isActive',u.is_active,'approvedAt',u.approved_at,
    'isLinked',u.supabase_user_id IS NOT NULL,'deletionStatus',u.deletion_status,'deletedAt',u.deleted_at
  ) ORDER BY lower(coalesce(u.full_name,u.email::text)),u.id),'[]'::jsonb)
  INTO v_result FROM public.users u
  WHERE u.deletion_status<>'deleted'
    AND (p_role IS NULL OR btrim(p_role)='' OR u.role::text=lower(btrim(p_role)))
    AND (p_is_active IS NULL OR u.is_active=p_is_active)
    AND (p_search IS NULL OR btrim(p_search)='' OR lower(coalesce(u.full_name,'')||' '||coalesce(u.email::text,'')) LIKE '%'||lower(btrim(p_search))||'%');
  RETURN v_result;
END
$function$;

CREATE OR REPLACE FUNCTION public.get_admin_user(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_actor uuid; v_result jsonb;
BEGIN
  v_actor:=security.admin_user_actor();
  IF v_actor IS NULL THEN RAISE EXCEPTION 'ADMIN_USERS_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  SELECT jsonb_build_object('id',u.id,'fullName',u.full_name,'clinicEmail',u.email,'role',u.role::text,
    'phone',u.phone,'specialization',u.specialization,'isActive',u.is_active,'approvedAt',u.approved_at,
    'isLinked',u.supabase_user_id IS NOT NULL,'deletionStatus',u.deletion_status,'deletedAt',u.deleted_at)
  INTO v_result FROM public.users u WHERE u.id=p_user_id AND u.deletion_status<>'deleted';
  IF v_result IS NULL THEN RAISE EXCEPTION 'ADMIN_USER_NOT_FOUND' USING ERRCODE='P4031'; END IF;
  RETURN v_result;
END
$function$;

CREATE OR REPLACE FUNCTION public.update_admin_user(p_user_id uuid,p_full_name text,p_clinic_email text,p_phone text,p_specialization text,p_is_active boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_actor uuid; v_target public.users%ROWTYPE;
BEGIN
  v_actor:=security.admin_user_actor();
  IF v_actor IS NULL THEN RAISE EXCEPTION 'ADMIN_USERS_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_target FROM public.users u WHERE u.id=p_user_id FOR UPDATE;
  IF v_target.id IS NULL THEN RAISE EXCEPTION 'ADMIN_USER_NOT_FOUND' USING ERRCODE='P4031'; END IF;
  IF v_target.deletion_status<>'active' THEN RAISE EXCEPTION 'ADMIN_USER_DELETION_STATE_LOCKED' USING ERRCODE='55000'; END IF;
  IF p_full_name IS NULL OR btrim(p_full_name)='' OR char_length(btrim(p_full_name))>200
     OR p_clinic_email IS NULL OR btrim(p_clinic_email)='' OR char_length(btrim(p_clinic_email))>320
     OR position('@' IN btrim(p_clinic_email))<2 OR (p_phone IS NOT NULL AND char_length(btrim(p_phone))>50)
     OR p_is_active IS NULL OR (p_specialization IS NOT NULL AND char_length(btrim(p_specialization))>200) THEN
    RAISE EXCEPTION 'ADMIN_USER_INPUT_INVALID' USING ERRCODE='22023';
  END IF;
  IF v_target.role::text='admin' AND p_is_active IS DISTINCT FROM v_target.is_active THEN
    RAISE EXCEPTION 'ADMIN_ACCOUNT_STATUS_IMMUTABLE' USING ERRCODE='42501';
  END IF;
  IF v_target.role::text='doctor' AND nullif(btrim(p_specialization),'') IS NULL THEN
    RAISE EXCEPTION 'ADMIN_USER_SPECIALIZATION_REQUIRED' USING ERRCODE='22023';
  END IF;
  UPDATE public.users u SET full_name=btrim(p_full_name),email=lower(btrim(p_clinic_email)),phone=nullif(btrim(p_phone),''),
    specialization=CASE WHEN v_target.role::text='doctor' THEN nullif(btrim(p_specialization),'') ELSE v_target.specialization END,
    is_active=p_is_active WHERE u.id=v_target.id;
  RETURN public.get_admin_user(v_target.id);
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'ADMIN_USER_CLINIC_EMAIL_DUPLICATE' USING ERRCODE='23505';
END
$function$;

REVOKE ALL ON FUNCTION public.list_admin_users(text,text,boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_admin_user(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_admin_user(uuid,text,text,text,text,boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_admin_users(text,text,boolean),public.get_admin_user(uuid),public.update_admin_user(uuid,text,text,text,text,boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_admin_users(text,text,boolean),public.get_admin_user(uuid),public.update_admin_user(uuid,text,text,text,text,boolean) TO authenticated;

COMMIT;
