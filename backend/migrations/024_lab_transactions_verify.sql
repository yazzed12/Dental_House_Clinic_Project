-- READ-ONLY verifier for Migration 024: Lab Transactions.
DO $verify$
DECLARE v_definition text; v_signature regprocedure;
BEGIN
    IF to_regclass('public.lab_payments') IS NULL THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: lab_payments missing';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
        AND table_name='lab_payments' AND column_name='amount' AND data_type='numeric'
        AND numeric_precision=15 AND numeric_scale=2) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: lab_payments numeric money differs';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.lab_payments'::regclass
        AND conname='lab_payments_amount_positive_ck' AND pg_get_constraintdef(oid) LIKE '%amount >%0%') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: positive payment constraint missing';
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.lab_payments'::regclass)
       OR has_table_privilege('anon','public.lab_payments','SELECT,INSERT,UPDATE,DELETE')
       OR has_table_privilege('authenticated','public.lab_payments','SELECT,INSERT,UPDATE,DELETE') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: lab_payments table containment differs';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.lab_payments'::regclass
        AND tgname='lab_payments_immutable' AND NOT tgisinternal) THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: append-only payment history missing';
    END IF;

    SELECT regexp_replace(lower(pg_get_functiondef(
      'public.list_lab_transactions(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure)),
      '[[:space:]]+',' ','g') INTO v_definition;
    IF position('public.consultation_lab_items' IN v_definition)=0
       OR position('public.consultations' IN v_definition)=0
       OR position('item.lab_id=p_lab_id' IN v_definition)=0
       OR position('consultation.created_at>=p_date_from' IN v_definition)=0
       OR position('consultation.created_at<p_date_to' IN v_definition)=0
       OR position('item.lab_name_snapshot' IN v_definition)=0
       OR position('item.product_name_snapshot' IN v_definition)=0
       OR position('item.unit_price_snapshot' IN v_definition)=0
       OR position('item.total_amount' IN v_definition)=0
       OR position('''consultationid''' IN v_definition)=0
       OR position('public.lab_products' IN v_definition)>0
       OR position('current_price' IN v_definition)>0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: snapshot transaction projection differs';
    END IF;

    SELECT regexp_replace(lower(pg_get_functiondef(
      'public.get_lab_transaction_summary(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure)),
      '[[:space:]]+',' ','g') INTO v_definition;
    IF position('sum(item.total_amount)' IN v_definition)=0
       OR position('payment.lab_id=p_lab_id' IN v_definition)=0
       OR position('payment.paid_at>=p_date_from' IN v_definition)=0
       OR position('payment.paid_at<p_date_to' IN v_definition)=0
       OR position('distinct on (payment.payment_id)' IN v_definition)=0
       OR position('v_purchases-v_paid' IN v_definition)=0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Lab summary arithmetic differs';
    END IF;

    SELECT lower(pg_get_functiondef(
      'public.create_lab_payment(uuid,numeric,timestamp with time zone,text)'::regprocedure)) INTO v_definition;
    IF position('security.lab_actor()' IN v_definition)=0
       OR position('is_active' IN v_definition)=0
       OR position('p_created_by' IN v_definition)>0
       OR position('v_actor_id' IN v_definition)=0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: payment ownership/archive guard differs';
    END IF;
    SELECT lower(pg_get_functiondef(
      'public.correct_lab_payment(uuid,integer,numeric,timestamp with time zone,text,text)'::regprocedure)) INTO v_definition;
    IF position('revision_number+1' IN regexp_replace(v_definition,'[[:space:]]+','','g'))=0
       OR position('for update' IN v_definition)=0
       OR position('delete from public.lab_payments' IN v_definition)>0
       OR position('update public.lab_payments' IN v_definition)>0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: payment correction is not append-only';
    END IF;

    FOREACH v_signature IN ARRAY ARRAY[
      'public.list_lab_transactions(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure,
      'public.get_lab_transaction_summary(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure,
      'public.list_lab_payments(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure,
      'public.create_lab_payment(uuid,numeric,timestamp with time zone,text)'::regprocedure,
      'public.correct_lab_payment(uuid,integer,numeric,timestamp with time zone,text,text)'::regprocedure
    ] LOOP
      IF NOT (SELECT proc.prosecdef FROM pg_proc AS proc WHERE proc.oid=v_signature::oid)
         OR NOT ('search_path=pg_catalog, pg_temp'=ANY(coalesce((SELECT proc.proconfig FROM pg_proc AS proc
             WHERE proc.oid=v_signature::oid),ARRAY[]::text[])))
         OR has_function_privilege('anon',v_signature,'EXECUTE')
         OR NOT has_function_privilege('authenticated',v_signature,'EXECUTE')
         OR EXISTS (SELECT 1 FROM pg_proc AS proc CROSS JOIN LATERAL
              aclexplode(coalesce(proc.proacl,acldefault('f',proc.proowner))) AS acl_entry
              WHERE proc.oid=v_signature::oid AND acl_entry.grantee=0 AND acl_entry.privilege_type='EXECUTE') THEN
          RAISE EXCEPTION 'VERIFICATION FAILED: RPC privilege/security differs for %',v_signature;
      END IF;
    END LOOP;

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
        AND table_name='clinical_reports' AND lower(column_name) LIKE '%lab%') THEN
      RAISE EXCEPTION 'VERIFICATION FAILED: Lab Transactions entered clinical_reports';
    END IF;
    FOR v_signature IN SELECT proc.oid::regprocedure FROM pg_proc AS proc
      JOIN pg_namespace AS namespace ON namespace.oid=proc.pronamespace
      WHERE namespace.nspname IN ('public','security')
        AND (proc.proname LIKE '%clinical_report%' OR proc.proname LIKE '%report%')
    LOOP
      SELECT lower(pg_get_functiondef(v_signature)) INTO v_definition;
      IF position('lab_payments' IN v_definition)>0 OR position('list_lab_transactions' IN v_definition)>0
         OR position('get_lab_transaction_summary' IN v_definition)>0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Medical Report function consumes Lab Transactions: %',v_signature;
      END IF;
    END LOOP;
END
$verify$;

SELECT 'VERIFICATION SUCCESSFUL: Lab Transactions foundation is contained and medically isolated' AS result;
