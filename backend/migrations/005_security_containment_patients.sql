-- Migration 005: Targeted Security Containment for public.patients ONLY
-- Immediately isolates public.patients from anonymous and unverified access
-- while preserving full unconstrained access for FastAPI (running as table owner / postgres role).

BEGIN;

-- 1. Drop exactly the 5 verified insecure or unverified policies on public.patients
DROP POLICY IF EXISTS "Allow all" ON public.patients;
DROP POLICY IF EXISTS "Allow clinic staff to insert patients" ON public.patients;
DROP POLICY IF EXISTS "Allow clinic staff to read patients" ON public.patients;
DROP POLICY IF EXISTS "Allow clinic staff to update patients" ON public.patients;
DROP POLICY IF EXISTS "Allow initial data migration" ON public.patients;

-- 2. Revoke table-level privileges on public.patients ONLY from client roles
REVOKE ALL ON TABLE public.patients FROM PUBLIC;
REVOKE ALL ON TABLE public.patients FROM anon;
REVOKE ALL ON TABLE public.patients FROM authenticated;

-- 3. Ensure Row Level Security remains active on public.patients
ALTER TABLE public.patients ENABLE ROW LEVEL SECURITY;

COMMIT;
