-- S2 DRAFT ONLY. MOVE INTO THE NUMBERED MIGRATION SET ONLY AFTER APPROVAL.
-- Prerequisites: public.users identity-link columns and public.patient_care_team.
-- This file creates helpers only; it does not enable RLS or create table policies.
BEGIN;

CREATE OR REPLACE FUNCTION public.current_app_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
    SELECT u.id
      FROM public.users AS u
     WHERE u.supabase_user_id = auth.uid()
       AND u.is_active = true
       AND u.approved_at IS NOT NULL
     LIMIT 1
$function$;

CREATE OR REPLACE FUNCTION public.current_app_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
    SELECT u.role
      FROM public.users AS u
     WHERE u.id = public.current_app_user_id()
$function$;

CREATE OR REPLACE FUNCTION public.is_active_approved_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
    SELECT public.current_app_user_id() IS NOT NULL
$function$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
    SELECT public.current_app_role() = 'admin'
$function$;

CREATE OR REPLACE FUNCTION public.is_doctor()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
    SELECT public.current_app_role() = 'doctor'
$function$;

CREATE OR REPLACE FUNCTION public.is_receptionist()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
    SELECT public.current_app_role() = 'receptionist'
$function$;

CREATE OR REPLACE FUNCTION public.has_active_patient_relationship(p_patient_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
    SELECT public.is_admin()
        OR (
            public.is_doctor()
            AND EXISTS (
                SELECT 1
                  FROM public.patient_care_team AS pct
                 WHERE pct.patient_id = p_patient_id
                   AND pct.doctor_id = public.current_app_user_id()
                   AND pct.status IN ('scheduled', 'active')
                   AND pct.starts_at <= now()
                   AND pct.ended_at IS NULL
            )
        )
$function$;

CREATE OR REPLACE FUNCTION public.had_patient_relationship_at(
    p_patient_id uuid,
    p_event_at timestamptz
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
    SELECT public.is_admin()
        OR (
            public.is_doctor()
            AND p_event_at IS NOT NULL
            AND EXISTS (
                SELECT 1
                  FROM public.patient_care_team AS pct
                 WHERE pct.patient_id = p_patient_id
                   AND pct.doctor_id = public.current_app_user_id()
                   AND pct.status IN ('active', 'ended')
                   AND pct.established_at IS NOT NULL
                   AND p_event_at >= pct.starts_at
                   AND (pct.ended_at IS NULL OR p_event_at < pct.ended_at)
            )
        )
$function$;

CREATE OR REPLACE FUNCTION public.can_read_clinical_event(
    p_patient_id uuid,
    p_event_doctor_id uuid,
    p_event_at timestamptz
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
    SELECT public.is_admin()
        OR public.has_active_patient_relationship(p_patient_id)
        OR (
            public.is_doctor()
            AND p_event_doctor_id = public.current_app_user_id()
            AND public.had_patient_relationship_at(p_patient_id, p_event_at)
        )
$function$;

REVOKE ALL ON FUNCTION public.current_app_user_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.current_app_role() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_active_approved_user() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_doctor() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_receptionist() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.has_active_patient_relationship(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.had_patient_relationship_at(uuid, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_read_clinical_event(uuid, uuid, timestamptz) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.current_app_user_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_app_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_active_approved_user() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_doctor() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_receptionist() TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_active_patient_relationship(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.had_patient_relationship_at(uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_read_clinical_event(uuid, uuid, timestamptz) TO authenticated;

COMMIT;
