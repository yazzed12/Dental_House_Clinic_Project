-- Migration 009: Browser-safe eligible Doctor selector RPC.
-- Local migration file only. Apply through the approved deployment process.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_eligible_doctors()
RETURNS TABLE (
    id uuid,
    full_name text,
    specialization text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM public.users AS caller
         WHERE caller.supabase_user_id = auth.uid()
           AND caller.is_active = true
           AND caller.approved_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Application access denied'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        doctor.id,
        doctor.full_name::text,
        doctor.specialization::text
      FROM public.users AS doctor
     WHERE doctor.role = 'doctor'
       AND doctor.is_active = true
       AND doctor.approved_at IS NOT NULL
       AND doctor.supabase_user_id IS NOT NULL
     ORDER BY doctor.full_name, doctor.id;
END
$function$;

REVOKE ALL ON FUNCTION public.get_eligible_doctors() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_eligible_doctors() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_eligible_doctors() TO authenticated;

COMMIT;
