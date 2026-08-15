-- Migration 007: Patients RLS Policies and safe_delete_patient RPC
-- Phase C6.1C Patients vertical slice.

BEGIN;

-- 1. Table-level Privileges: Grant DML (SELECT, INSERT, UPDATE) to authenticated ONLY
GRANT SELECT, INSERT, UPDATE ON TABLE public.patients TO authenticated;

-- 2. Enable Row Level Security on public.patients
ALTER TABLE public.patients ENABLE ROW LEVEL SECURITY;

-- 3. SELECT Policy (Active approved staff can view non-archived & archived patients)
DROP POLICY IF EXISTS patient_select_policy ON public.patients;
CREATE POLICY patient_select_policy ON public.patients
    FOR SELECT TO authenticated
    USING (security.is_active_approved_user());

-- 4. INSERT Policy (Active approved staff can insert new patients)
DROP POLICY IF EXISTS patient_insert_policy ON public.patients;
CREATE POLICY patient_insert_policy ON public.patients
    FOR INSERT TO authenticated
    WITH CHECK (security.is_active_approved_user());

-- 5. UPDATE Policy (Active approved staff can update patient details)
DROP POLICY IF EXISTS patient_update_policy ON public.patients;
CREATE POLICY patient_update_policy ON public.patients
    FOR UPDATE TO authenticated
    USING (security.is_active_approved_user())
    WITH CHECK (security.is_active_approved_user());

-- 6. Ensure NO direct DELETE policy exists for client roles
DROP POLICY IF EXISTS patient_delete_policy ON public.patients;

-- 7. RPC: safe_delete_patient(p_patient_id uuid)
CREATE OR REPLACE FUNCTION public.safe_delete_patient(p_patient_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_calling_user_id uuid;
    v_patient_name text;
    v_has_history boolean := false;
BEGIN
    -- Authorization: Doctors or Admins ONLY
    v_calling_user_id := security.current_app_user_id();
    IF v_calling_user_id IS NULL OR NOT (security.is_doctor() OR security.is_admin()) THEN
        RAISE EXCEPTION 'Insufficient permissions' USING ERRCODE = '42501';
    END IF;

    -- Lock target row to prevent concurrent modification races
    SELECT name INTO v_patient_name
      FROM public.patients
     WHERE id = p_patient_id
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Patient not found' USING ERRCODE = 'P0002';
    END IF;

    -- Check Across Verified Current Production History & Audit Tables (6 tables)
    -- Prevents silent ON DELETE CASCADE on clinical tables and ON DELETE SET NULL on audit logs.
    SELECT EXISTS (
        SELECT 1 FROM public.appointments WHERE patient_id = p_patient_id
        UNION ALL
        SELECT 1 FROM public.records WHERE patient_id = p_patient_id
        UNION ALL
        SELECT 1 FROM public.consultations WHERE patient_id = p_patient_id
        UNION ALL
        SELECT 1 FROM public.clinical_reports WHERE patient_id = p_patient_id
        UNION ALL
        SELECT 1 FROM public.patient_dental_state WHERE patient_id = p_patient_id
        UNION ALL
        SELECT 1 FROM public.logs WHERE patient_id = p_patient_id
    ) INTO v_has_history;

    -- Branch Execution: Soft-Archive vs Physical Delete
    IF v_has_history THEN
        UPDATE public.patients SET status = 'Archived' WHERE id = p_patient_id;
        INSERT INTO public.logs (id, message, doctor_id, patient_id, created_at)
        VALUES (
            gen_random_uuid(),
            format('Patient %s archived safely due to existing clinical history or audit records.', v_patient_name),
            v_calling_user_id,
            p_patient_id,
            now()
        );
        RETURN jsonb_build_object(
            'status', 'success',
            'action', 'archived',
            'message', 'Patient archived safely to preserve clinical and audit history.'
        );
    ELSE
        DELETE FROM public.patients WHERE id = p_patient_id;
        INSERT INTO public.logs (id, message, doctor_id, patient_id, created_at)
        VALUES (
            gen_random_uuid(),
            format('Patient %s deleted completely.', v_patient_name),
            v_calling_user_id,
            NULL,
            now()
        );
        RETURN jsonb_build_object(
            'status', 'success',
            'action', 'deleted',
            'message', 'Patient deleted successfully from system.'
        );
    END IF;
END;
$function$;

-- 8. Privilege Hardening for RPC: Revoke EXECUTE from PUBLIC and anon, grant ONLY to authenticated
REVOKE ALL ON FUNCTION public.safe_delete_patient(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.safe_delete_patient(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.safe_delete_patient(uuid) TO authenticated;

COMMIT;
