-- Migration 006: Minimal Auth & RLS Identity Helper Foundation
-- Creates dedicated non-exposed 'security' schema and hardened SECURITY DEFINER
-- identity helper functions linking auth.uid() to public.users for RLS policies.

BEGIN;

-- 1. Create dedicated, trusted non-exposed schema for security helpers
CREATE SCHEMA IF NOT EXISTS security;

-- Hardener schema privileges: revoke public access, grant USAGE (not CREATE) to authenticated
REVOKE ALL ON SCHEMA security FROM PUBLIC;
REVOKE ALL ON SCHEMA security FROM anon;
GRANT USAGE ON SCHEMA security TO authenticated;
REVOKE CREATE ON SCHEMA security FROM authenticated;

-- 2. Internal Root Identity Helper: Maps auth.uid() to active, approved public.users.id
CREATE OR REPLACE FUNCTION security.current_app_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT u.id
      FROM public.users AS u
     WHERE u.supabase_user_id = auth.uid()
       AND u.is_active = true
       AND u.approved_at IS NOT NULL
     LIMIT 1
$function$;

-- 3. Internal Role Resolution Helper: Resolves public.users.role for active, approved user
CREATE OR REPLACE FUNCTION security.current_app_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT u.role
      FROM public.users AS u
     WHERE u.id = security.current_app_user_id()
$function$;

-- 4. Public RLS Entrypoint Predicate: Checks if calling user is active and approved
CREATE OR REPLACE FUNCTION security.is_active_approved_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT security.current_app_user_id() IS NOT NULL
$function$;

-- 5. Internal Role Check Helper: Checks if active, approved user has doctor role
CREATE OR REPLACE FUNCTION security.is_doctor()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT security.current_app_role() = 'doctor'
$function$;

-- 6. Internal Role Check Helper: Checks if active, approved user has admin role
CREATE OR REPLACE FUNCTION security.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT security.current_app_role() = 'admin'
$function$;

-- 7. Privilege Hardening: Revoke default PUBLIC access on all security functions
REVOKE ALL ON FUNCTION security.current_app_user_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION security.current_app_role() FROM PUBLIC;
REVOKE ALL ON FUNCTION security.is_active_approved_user() FROM PUBLIC;
REVOKE ALL ON FUNCTION security.is_doctor() FROM PUBLIC;
REVOKE ALL ON FUNCTION security.is_admin() FROM PUBLIC;

-- 8. Minimum Privilege Grant: Grant EXECUTE to authenticated ONLY on security.is_active_approved_user() predicate.
-- Helper functions reside in the unexposed 'security' schema (hidden from PostgREST RPC endpoints).
-- Internal helpers remain non-callable directly by authenticated, but run securely via SECURITY DEFINER owner context.
GRANT EXECUTE ON FUNCTION security.is_active_approved_user() TO authenticated;

COMMIT;
