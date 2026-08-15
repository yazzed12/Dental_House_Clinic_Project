-- Migration 031: destructive Admin operations foundation. No Auth Admin API calls occur here.
BEGIN;

DO $precondition$
BEGIN
  IF to_regprocedure('security.admin_user_actor()') IS NULL THEN RAISE EXCEPTION 'ADMIN_IDENTITY_FOUNDATION_MISSING'; END IF;
  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users'
            AND column_name IN('deleted_at','deletion_status'))
     OR to_regprocedure('public.format_clinic_data()') IS NOT NULL
     OR to_regprocedure('public.prepare_admin_account_deletion(uuid,uuid)') IS NOT NULL
     OR to_regprocedure('public.finalize_admin_account_deletion(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'ADMIN_DESTRUCTIVE_OPERATIONS_TARGET_CONFLICT';
  END IF;
END
$precondition$;

ALTER TABLE public.users
  ADD COLUMN deletion_status text NOT NULL DEFAULT 'active',
  ADD COLUMN deleted_at timestamptz NULL,
  ADD CONSTRAINT users_deletion_state_ck CHECK (
    (deletion_status='active' AND deleted_at IS NULL)
    OR (deletion_status='pending_auth_delete' AND deleted_at IS NULL)
    OR (deletion_status='deleted' AND deleted_at IS NOT NULL)
  );

CREATE FUNCTION public.format_clinic_data()
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
    public.patients;
  RETURN jsonb_build_object('formatted',true);
END
$function$;

-- Trusted Edge Function input: caller Auth UUID already verified from its bearer token.
-- The browser never receives this RPC and later sends only the target application user ID.
CREATE FUNCTION public.prepare_admin_account_deletion(
  p_target_user_id uuid,
  p_actor_supabase_user_id uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_actor public.users%ROWTYPE; v_target public.users%ROWTYPE; v_admin_count bigint;
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('smart-clinic:destructive-operations',0));
  SELECT * INTO v_actor FROM public.users u
   WHERE u.supabase_user_id=p_actor_supabase_user_id AND u.role::text='admin'
     AND u.is_active=true AND u.approved_at IS NOT NULL AND u.deletion_status='active'
   FOR UPDATE;
  IF v_actor.id IS NULL THEN RAISE EXCEPTION 'ADMIN_ACCOUNT_DELETE_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_target FROM public.users u WHERE u.id=p_target_user_id FOR UPDATE;
  IF v_target.id IS NULL THEN RAISE EXCEPTION 'ADMIN_ACCOUNT_DELETE_TARGET_NOT_FOUND' USING ERRCODE='P4031'; END IF;
  IF v_target.id=v_actor.id THEN RAISE EXCEPTION 'ADMIN_ACCOUNT_DELETE_SELF_DENIED' USING ERRCODE='42501'; END IF;
  IF v_target.deletion_status='deleted' THEN
    RETURN jsonb_build_object('targetUserId',v_target.id,'status','deleted','authUserId',NULL);
  END IF;
  IF v_target.deletion_status='pending_auth_delete' THEN
    RETURN jsonb_build_object('targetUserId',v_target.id,'status','pending_auth_delete','authUserId',v_target.supabase_user_id);
  END IF;
  IF v_target.role::text='admin' AND v_target.is_active=true AND v_target.approved_at IS NOT NULL THEN
    SELECT count(*) INTO v_admin_count FROM public.users u
     WHERE u.role::text='admin' AND u.is_active=true AND u.approved_at IS NOT NULL AND u.deletion_status='active';
    IF v_admin_count<=1 THEN RAISE EXCEPTION 'ADMIN_ACCOUNT_DELETE_LAST_ADMIN_DENIED' USING ERRCODE='42501'; END IF;
  END IF;
  UPDATE public.users u SET is_active=false,approved_at=NULL,deletion_status='pending_auth_delete'
   WHERE u.id=v_target.id RETURNING * INTO v_target;
  RETURN jsonb_build_object('targetUserId',v_target.id,'status','pending_auth_delete','authUserId',v_target.supabase_user_id);
END
$function$;

CREATE FUNCTION public.finalize_admin_account_deletion(p_target_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_target public.users%ROWTYPE; v_deleted_at timestamptz;
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('smart-clinic:destructive-operations',0));
  SELECT * INTO v_target FROM public.users u WHERE u.id=p_target_user_id FOR UPDATE;
  IF v_target.id IS NULL THEN RAISE EXCEPTION 'ADMIN_ACCOUNT_DELETE_TARGET_NOT_FOUND' USING ERRCODE='P4031'; END IF;
  IF v_target.deletion_status='active' THEN RAISE EXCEPTION 'ADMIN_ACCOUNT_DELETE_NOT_PREPARED' USING ERRCODE='55000'; END IF;
  IF v_target.deletion_status='deleted' THEN
    RETURN jsonb_build_object('targetUserId',v_target.id,'status','deleted','deletedAt',v_target.deleted_at);
  END IF;
  DELETE FROM public.notifications n
   WHERE n.recipient_user_id=v_target.id OR n.user_id::text=v_target.id::text;
  v_deleted_at:=clock_timestamp();
  UPDATE public.users u SET
    supabase_user_id=NULL,personal_email=NULL,approved_at=NULL,is_active=false,phone=NULL,
    email=('deleted+'||u.id::text||'@deleted.invalid'),
    username=('deleted:'||u.id::text),hashed_password='ACCOUNT_DELETED',
    deletion_status='deleted',deleted_at=v_deleted_at
  WHERE u.id=v_target.id;
  RETURN jsonb_build_object('targetUserId',v_target.id,'status','deleted','deletedAt',v_deleted_at);
END
$function$;

REVOKE ALL ON FUNCTION public.format_clinic_data() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.format_clinic_data() FROM anon;
GRANT EXECUTE ON FUNCTION public.format_clinic_data() TO authenticated;

REVOKE ALL ON FUNCTION public.prepare_admin_account_deletion(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.finalize_admin_account_deletion(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_admin_account_deletion(uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.finalize_admin_account_deletion(uuid) TO service_role;

COMMIT;
