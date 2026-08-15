-- Migration 026: Supabase Admin user management + Doctor-only Lab authorization.
BEGIN;

DO $precondition$
BEGIN
  IF to_regclass('public.users') IS NULL OR to_regprocedure('security.lab_actor()') IS NULL THEN
    RAISE EXCEPTION 'ADMIN_USER_MANAGEMENT_FOUNDATION_MISSING';
  END IF;
  IF to_regprocedure('public.list_admin_users(text,text,boolean)') IS NOT NULL
     OR to_regprocedure('public.get_admin_user(uuid)') IS NOT NULL
     OR to_regprocedure('public.update_admin_user(uuid,text,text,text,text,boolean)') IS NOT NULL
     OR to_regprocedure('public.create_admin_managed_staff(uuid,text,text,text,text,text,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'ADMIN_USER_MANAGEMENT_TARGET_CONFLICT';
  END IF;
END
$precondition$;

CREATE FUNCTION security.admin_user_actor()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
  SELECT app_user.id FROM public.users AS app_user
   WHERE app_user.supabase_user_id=auth.uid() AND app_user.role::text='admin'
     AND app_user.is_active=true AND app_user.approved_at IS NOT NULL LIMIT 1
$function$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_normalized_clinic_email
  ON public.users(lower(btrim(email::text))) WHERE email IS NOT NULL;

CREATE FUNCTION public.list_admin_users(p_search text DEFAULT NULL,p_role text DEFAULT NULL,p_is_active boolean DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_actor uuid; v_result jsonb;
BEGIN
  v_actor:=security.admin_user_actor();
  IF v_actor IS NULL THEN RAISE EXCEPTION 'ADMIN_USERS_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  IF p_role IS NOT NULL AND btrim(p_role)<>'' AND lower(btrim(p_role)) NOT IN('admin','doctor','receptionist') THEN RAISE EXCEPTION 'ADMIN_USERS_ROLE_INVALID' USING ERRCODE='22023'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',u.id,'fullName',u.full_name,'clinicEmail',u.email,'role',u.role::text,'phone',u.phone,
    'specialization',u.specialization,'isActive',u.is_active,'approvedAt',u.approved_at,
    'isLinked',u.supabase_user_id IS NOT NULL) ORDER BY lower(coalesce(u.full_name,u.email::text)),u.id),'[]'::jsonb)
  INTO v_result FROM public.users u
  WHERE u.role::text IN('admin','doctor','receptionist')
    AND (p_role IS NULL OR btrim(p_role)='' OR u.role::text=lower(btrim(p_role)))
    AND (p_is_active IS NULL OR u.is_active=p_is_active)
    AND (p_search IS NULL OR btrim(p_search)='' OR lower(coalesce(u.full_name,'')||' '||coalesce(u.email::text,'')) LIKE '%'||lower(btrim(p_search))||'%');
  RETURN v_result;
END
$function$;

CREATE FUNCTION public.get_admin_user(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_actor uuid; v_result jsonb;
BEGIN
  v_actor:=security.admin_user_actor();
  IF v_actor IS NULL THEN RAISE EXCEPTION 'ADMIN_USERS_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  SELECT jsonb_build_object('id',u.id,'fullName',u.full_name,'clinicEmail',u.email,'role',u.role::text,
    'phone',u.phone,'specialization',u.specialization,'isActive',u.is_active,'approvedAt',u.approved_at,
    'isLinked',u.supabase_user_id IS NOT NULL) INTO v_result
  FROM public.users u WHERE u.id=p_user_id AND u.role::text IN('admin','doctor','receptionist');
  IF v_result IS NULL THEN RAISE EXCEPTION 'ADMIN_USER_NOT_FOUND' USING ERRCODE='P4031'; END IF;
  RETURN v_result;
END
$function$;

CREATE FUNCTION public.update_admin_user(p_user_id uuid,p_full_name text,p_clinic_email text,p_phone text,p_specialization text,p_is_active boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_actor uuid; v_target public.users%ROWTYPE;
BEGIN
  v_actor:=security.admin_user_actor();
  IF v_actor IS NULL THEN RAISE EXCEPTION 'ADMIN_USERS_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_target FROM public.users u WHERE u.id=p_user_id AND u.role::text IN('admin','doctor','receptionist') FOR UPDATE;
  IF v_target.id IS NULL THEN RAISE EXCEPTION 'ADMIN_USER_NOT_FOUND' USING ERRCODE='P4031'; END IF;
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
    specialization=CASE WHEN v_target.role::text='doctor' THEN nullif(btrim(p_specialization),'') ELSE NULL END,
    is_active=p_is_active WHERE u.id=v_target.id;
  RETURN public.get_admin_user(v_target.id);
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'ADMIN_USER_CLINIC_EMAIL_DUPLICATE' USING ERRCODE='23505';
END
$function$;

-- Internal service-role-only insertion called by admin-create-user after Auth creation.
CREATE FUNCTION public.create_admin_managed_staff(p_supabase_user_id uuid,p_full_name text,p_clinic_email text,p_personal_email text,p_role text,p_phone text,p_specialization text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_id uuid:=gen_random_uuid(); v_typed_role public.users.role%TYPE; v_result jsonb;
BEGIN
  IF p_supabase_user_id IS NULL OR p_full_name IS NULL OR btrim(p_full_name)='' OR char_length(btrim(p_full_name))>200
    OR p_clinic_email IS NULL OR position('@' IN btrim(p_clinic_email))<2 OR char_length(btrim(p_clinic_email))>320
    OR p_personal_email IS NULL OR position('@' IN btrim(p_personal_email))<2 OR char_length(btrim(p_personal_email))>320
    OR lower(btrim(p_role)) NOT IN('doctor','receptionist') OR (p_phone IS NOT NULL AND char_length(btrim(p_phone))>50)
    OR (lower(btrim(p_role))='doctor' AND nullif(btrim(p_specialization),'') IS NULL)
    OR (p_specialization IS NOT NULL AND char_length(btrim(p_specialization))>200) THEN
    RAISE EXCEPTION 'ADMIN_CREATE_USER_INPUT_INVALID' USING ERRCODE='22023';
  END IF;
  v_typed_role:=(jsonb_populate_record(NULL::public.users,jsonb_build_object('role',lower(btrim(p_role))))).role;
  INSERT INTO public.users(id,username,hashed_password,full_name,email,role,is_active,phone,specialization,supabase_user_id,personal_email,approved_at)
  VALUES(v_id,lower(btrim(p_clinic_email)),'SUPABASE_AUTH_ONLY',btrim(p_full_name),lower(btrim(p_clinic_email)),v_typed_role,true,
    nullif(btrim(p_phone),''),CASE WHEN lower(btrim(p_role))='doctor' THEN btrim(p_specialization) ELSE NULL END,
    p_supabase_user_id,lower(btrim(p_personal_email)),clock_timestamp());
  SELECT jsonb_build_object('id',u.id,'fullName',u.full_name,'clinicEmail',u.email,'role',u.role::text,'phone',u.phone,
    'specialization',u.specialization,'isActive',u.is_active,'approvedAt',u.approved_at,'isLinked',u.supabase_user_id IS NOT NULL)
    INTO v_result FROM public.users u WHERE u.id=v_id;
  RETURN v_result;
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'ADMIN_CREATE_USER_IDENTITY_DUPLICATE' USING ERRCODE='23505';
END
$function$;

-- Product correction: every existing Lab RPC resolves through this Doctor-only helper.
CREATE OR REPLACE FUNCTION security.lab_actor()
RETURNS TABLE(id uuid,role text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
  SELECT app_user.id,app_user.role::text FROM public.users app_user
   WHERE app_user.supabase_user_id=auth.uid() AND app_user.is_active=true
     AND app_user.approved_at IS NOT NULL AND app_user.role::text='doctor' LIMIT 1
$function$;

REVOKE ALL ON FUNCTION security.admin_user_actor() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.create_admin_managed_staff(uuid,text,text,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_admin_managed_staff(uuid,text,text,text,text,text,text) TO service_role;
REVOKE ALL ON FUNCTION public.list_admin_users(text,text,boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_admin_user(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_admin_user(uuid,text,text,text,text,boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_admin_users(text,text,boolean),public.get_admin_user(uuid),public.update_admin_user(uuid,text,text,text,text,boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_admin_users(text,text,boolean),public.get_admin_user(uuid),public.update_admin_user(uuid,text,text,text,text,boolean) TO authenticated;
REVOKE ALL ON FUNCTION security.lab_actor() FROM PUBLIC,anon,authenticated;

COMMIT;
