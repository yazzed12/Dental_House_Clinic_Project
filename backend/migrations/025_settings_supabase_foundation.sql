-- Migration 025: Simplified Supabase Settings foundation.
-- Existing clinic/users rows and hidden clinic fields are never rewritten by this migration.
BEGIN;

DO $precondition$
BEGIN
  IF to_regclass('public.clinic_settings') IS NULL OR to_regclass('public.users') IS NULL
     OR to_regprocedure('public.get_current_app_profile()') IS NULL
     OR to_regprocedure('public.finalize_clinical_report(uuid,jsonb,text,text)') IS NULL THEN
    RAISE EXCEPTION 'SETTINGS_REQUIRED_FOUNDATION_MISSING';
  END IF;
  IF (SELECT count(*) FROM public.clinic_settings)<>1 THEN
    RAISE EXCEPTION 'SETTINGS_CLINIC_SINGLETON_CONFLICT';
  END IF;
  IF to_regprocedure('public.get_clinic_settings()') IS NOT NULL
     OR to_regprocedure('public.update_clinic_settings(text,text,text,text)') IS NOT NULL
     OR to_regprocedure('public.update_current_app_profile(text,text,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'SETTINGS_RPC_CONFLICT';
  END IF;
END
$precondition$;

ALTER TABLE public.clinic_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.clinic_settings FROM PUBLIC,anon,authenticated;

CREATE FUNCTION security.settings_actor()
RETURNS TABLE(id uuid,role text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
  SELECT app_user.id,app_user.role::text FROM public.users AS app_user
   WHERE app_user.supabase_user_id=auth.uid()
     AND app_user.is_active=true AND app_user.approved_at IS NOT NULL
     AND app_user.role IN ('doctor','admin','receptionist')
   LIMIT 1
$function$;

CREATE FUNCTION public.get_clinic_settings()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_result jsonb;
BEGIN
  SELECT actor.id INTO v_actor_id FROM security.settings_actor() AS actor;
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'SETTINGS_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  SELECT jsonb_build_object('id',settings.id,'name',settings.name,'email',settings.email,
    'phone',settings.phone,'address',settings.address) INTO v_result
    FROM public.clinic_settings AS settings ORDER BY settings.id LIMIT 1;
  IF v_result IS NULL THEN RAISE EXCEPTION 'SETTINGS_CLINIC_NOT_FOUND' USING ERRCODE='P4030'; END IF;
  RETURN v_result;
END
$function$;

CREATE FUNCTION public.update_clinic_settings(p_name text,p_email text,p_phone text,p_address text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text; v_id public.clinic_settings.id%TYPE;
BEGIN
  SELECT actor.id,actor.role INTO v_actor_id,v_actor_role FROM security.settings_actor() AS actor;
  IF v_actor_id IS NULL OR v_actor_role NOT IN ('doctor','admin') THEN
    RAISE EXCEPTION 'SETTINGS_AUTHORIZATION_DENIED' USING ERRCODE='42501';
  END IF;
  IF p_name IS NULL OR btrim(p_name)='' OR char_length(btrim(p_name))>200
     OR (p_email IS NOT NULL AND char_length(btrim(p_email))>320)
     OR (p_phone IS NOT NULL AND char_length(btrim(p_phone))>50)
     OR (p_address IS NOT NULL AND char_length(btrim(p_address))>1000) THEN
    RAISE EXCEPTION 'SETTINGS_CLINIC_INVALID' USING ERRCODE='22023';
  END IF;
  SELECT settings.id INTO v_id FROM public.clinic_settings AS settings ORDER BY settings.id LIMIT 1 FOR UPDATE;
  IF v_id IS NULL THEN RAISE EXCEPTION 'SETTINGS_CLINIC_NOT_FOUND' USING ERRCODE='P4030'; END IF;
  UPDATE public.clinic_settings AS settings SET
    name=btrim(p_name),email=nullif(btrim(p_email),''),phone=nullif(btrim(p_phone),''),address=nullif(btrim(p_address),'')
    WHERE settings.id=v_id;
  RETURN public.get_clinic_settings();
END
$function$;

CREATE FUNCTION public.update_current_app_profile(p_full_name text,p_phone text,p_specialization text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text; v_user public.users%ROWTYPE;
BEGIN
  SELECT actor.id,actor.role INTO v_actor_id,v_actor_role FROM security.settings_actor() AS actor;
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'SETTINGS_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  IF p_full_name IS NULL OR btrim(p_full_name)='' OR char_length(btrim(p_full_name))>200
     OR (p_phone IS NOT NULL AND char_length(btrim(p_phone))>50)
     OR (p_specialization IS NOT NULL AND char_length(btrim(p_specialization))>200) THEN
    RAISE EXCEPTION 'SETTINGS_PROFILE_INVALID' USING ERRCODE='22023';
  END IF;
  IF v_actor_role<>'doctor' AND p_specialization IS NOT NULL THEN
    RAISE EXCEPTION 'SETTINGS_SPECIALIZATION_NOT_ALLOWED' USING ERRCODE='42501';
  END IF;
  UPDATE public.users AS app_user SET full_name=btrim(p_full_name),phone=nullif(btrim(p_phone),''),
    specialization=CASE WHEN v_actor_role='doctor' THEN nullif(btrim(p_specialization),'') ELSE app_user.specialization END
    WHERE app_user.id=v_actor_id AND app_user.supabase_user_id=auth.uid()
    RETURNING app_user.* INTO v_user;
  IF v_user.id IS NULL THEN RAISE EXCEPTION 'SETTINGS_PROFILE_NOT_FOUND' USING ERRCODE='P4031'; END IF;
  RETURN jsonb_build_object('id',v_user.id,'full_name',v_user.full_name,'email',v_user.email,
    'phone',v_user.phone,'specialization',v_user.specialization,'role',v_user.role::text);
END
$function$;

REVOKE ALL ON FUNCTION security.settings_actor() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.get_clinic_settings() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_clinic_settings(text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_current_app_profile(text,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_clinic_settings() FROM anon;
REVOKE EXECUTE ON FUNCTION public.update_clinic_settings(text,text,text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.update_current_app_profile(text,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_clinic_settings() TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_clinic_settings(text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_current_app_profile(text,text,text) TO authenticated;

COMMIT;
