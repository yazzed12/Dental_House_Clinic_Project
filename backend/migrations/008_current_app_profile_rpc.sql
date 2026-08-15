-- Migration 008: Browser-safe current application profile RPC.
-- Local migration file only. Apply through the approved deployment process.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_current_app_profile()
RETURNS TABLE (
    id uuid,
    full_name text,
    role text,
    email text,
    phone text,
    specialization text,
    supabase_user_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT
        u.id,
        u.full_name::text,
        u.role::text,
        u.email::text,
        u.phone::text,
        u.specialization::text,
        u.supabase_user_id
      FROM public.users AS u
     WHERE u.supabase_user_id = auth.uid()
       AND u.is_active = true
       AND u.approved_at IS NOT NULL
     LIMIT 1
$function$;

REVOKE ALL ON FUNCTION public.get_current_app_profile() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_current_app_profile() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_current_app_profile() TO authenticated;

COMMIT;
