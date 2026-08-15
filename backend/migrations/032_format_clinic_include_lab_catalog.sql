-- Migration 032: include the Lab catalog in the existing clinic data reset.
-- This replaces only format_clinic_data(); it does not alter schema or account deletion.
BEGIN;

CREATE OR REPLACE FUNCTION public.format_clinic_data()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_actor_id uuid;
BEGIN
  v_actor_id:=security.admin_user_actor();
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'FORMAT_CLINIC_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('smart-clinic:destructive-operations',0));
  TRUNCATE TABLE
    public.notifications,
    public.financial_payment_allocations,
    public.financial_charge_adjustments,
    public.financial_payment_records,
    public.consultation_procedures,
    public.lab_payments,
    public.consultation_lab_items,
    public.clinical_reports,
    public.patient_dental_state,
    public.records,
    public.logs,
    public.consultations,
    public.appointments,
    public.patients,
    public.lab_products,
    public.labs;
  RETURN jsonb_build_object('formatted',true);
END
$function$;

REVOKE ALL ON FUNCTION public.format_clinic_data() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.format_clinic_data() FROM anon;
GRANT EXECUTE ON FUNCTION public.format_clinic_data() TO authenticated;

COMMIT;
