-- Migration 024: Lab Transactions foundation.
-- Purchases remain authoritative in consultation_lab_items; only Lab payment revisions are new.
BEGIN;

DO $precondition$
BEGIN
    IF to_regclass('public.labs') IS NULL
       OR to_regclass('public.consultation_lab_items') IS NULL
       OR to_regclass('public.consultations') IS NULL
       OR to_regprocedure('security.lab_actor()') IS NULL THEN
        RAISE EXCEPTION 'LAB_TRANSACTIONS_REQUIRED_FOUNDATION_MISSING';
    END IF;
    IF to_regclass('public.lab_payments') IS NOT NULL
       OR to_regprocedure('public.list_lab_transactions(uuid,timestamp with time zone,timestamp with time zone)') IS NOT NULL
       OR to_regprocedure('public.get_lab_transaction_summary(uuid,timestamp with time zone,timestamp with time zone)') IS NOT NULL
       OR to_regprocedure('public.list_lab_payments(uuid,timestamp with time zone,timestamp with time zone)') IS NOT NULL
       OR to_regprocedure('public.create_lab_payment(uuid,numeric,timestamp with time zone,text)') IS NOT NULL
       OR to_regprocedure('public.correct_lab_payment(uuid,integer,numeric,timestamp with time zone,text,text)') IS NOT NULL THEN
        RAISE EXCEPTION 'LAB_TRANSACTIONS_CONFLICTING_SCHEMA';
    END IF;
END
$precondition$;

-- Append-only revisions mirror the existing patient-financial audit convention.
CREATE TABLE public.lab_payments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id uuid NOT NULL,
    lab_id uuid NOT NULL,
    revision_number integer NOT NULL,
    amount numeric(15,2) NOT NULL,
    paid_at timestamptz NOT NULL,
    note text NULL,
    correction_reason text NULL,
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT lab_payments_lab_fk FOREIGN KEY (lab_id) REFERENCES public.labs(id) ON DELETE RESTRICT,
    CONSTRAINT lab_payments_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE RESTRICT,
    CONSTRAINT lab_payments_amount_positive_ck CHECK (amount>0),
    CONSTRAINT lab_payments_revision_positive_ck CHECK (revision_number>=1),
    CONSTRAINT lab_payments_note_length_ck CHECK (note IS NULL OR char_length(note)<=2000),
    CONSTRAINT lab_payments_reason_ck CHECK (
        (revision_number=1 AND correction_reason IS NULL)
        OR (revision_number>1 AND btrim(coalesce(correction_reason,''))<>'' AND char_length(correction_reason)<=1000)
    ),
    CONSTRAINT lab_payments_payment_revision_uq UNIQUE (payment_id,revision_number)
);

CREATE INDEX lab_payments_lab_paid_idx ON public.lab_payments (lab_id,paid_at DESC,payment_id,revision_number DESC);
CREATE INDEX lab_payments_created_by_idx ON public.lab_payments (created_by);
ALTER TABLE public.lab_payments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.lab_payments FROM PUBLIC,anon,authenticated;

CREATE FUNCTION security.reject_lab_payment_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $function$
BEGIN
    RAISE EXCEPTION 'LAB_PAYMENT_HISTORY_IMMUTABLE' USING ERRCODE='55000';
END
$function$;

CREATE TRIGGER lab_payments_immutable
BEFORE UPDATE OR DELETE ON public.lab_payments
FOR EACH ROW EXECUTE FUNCTION security.reject_lab_payment_mutation();

CREATE OR REPLACE FUNCTION public.list_lab_transactions(
    p_lab_id uuid,p_date_from timestamptz,p_date_to timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_result jsonb;
BEGIN
    SELECT actor.id INTO v_actor_id FROM security.lab_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'LAB_TRANSACTION_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
    IF p_lab_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.labs WHERE id=p_lab_id) THEN
        RAISE EXCEPTION 'LAB_TRANSACTION_LAB_NOT_FOUND' USING ERRCODE='P4020';
    END IF;
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>=p_date_to THEN
        RAISE EXCEPTION 'LAB_TRANSACTION_DATE_RANGE_INVALID' USING ERRCODE='22023';
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object(
        'consultationId',transaction.consultation_id,'appointmentId',transaction.appointment_id,
        'transactionDate',transaction.transaction_date,'labId',p_lab_id,
        'labName',transaction.lab_name,'items',transaction.items,
        'transactionTotal',security.lab_money(transaction.transaction_total)
    ) ORDER BY transaction.transaction_date DESC,transaction.consultation_id DESC),'[]'::jsonb)
      INTO v_result
      FROM (
        SELECT consultation.id AS consultation_id,consultation.appointment_id,
               consultation.created_at AS transaction_date,
               min(item.lab_name_snapshot) AS lab_name,
               jsonb_agg(jsonb_build_object(
                 'labProductId',item.lab_product_id,'productName',item.product_name_snapshot,
                 'unitPrice',security.lab_money(item.unit_price_snapshot),'quantity',item.quantity,
                 'totalAmount',security.lab_money(item.total_amount)
               ) ORDER BY item.created_at,item.id) AS items,
               sum(item.total_amount)::numeric(15,2) AS transaction_total
          FROM public.consultation_lab_items AS item
          JOIN public.consultations AS consultation ON consultation.id=item.consultation_id
         WHERE item.lab_id=p_lab_id
           AND consultation.created_at>=p_date_from AND consultation.created_at<p_date_to
         GROUP BY consultation.id,consultation.appointment_id,consultation.created_at
      ) AS transaction;
    RETURN v_result;
END
$function$;

CREATE OR REPLACE FUNCTION public.get_lab_transaction_summary(
    p_lab_id uuid,p_date_from timestamptz,p_date_to timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_purchases numeric(15,2); v_paid numeric(15,2); v_transactions bigint; v_items bigint;
BEGIN
    SELECT actor.id INTO v_actor_id FROM security.lab_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'LAB_TRANSACTION_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
    IF p_lab_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.labs WHERE id=p_lab_id) THEN
        RAISE EXCEPTION 'LAB_TRANSACTION_LAB_NOT_FOUND' USING ERRCODE='P4020';
    END IF;
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>=p_date_to THEN
        RAISE EXCEPTION 'LAB_TRANSACTION_DATE_RANGE_INVALID' USING ERRCODE='22023';
    END IF;
    SELECT coalesce(sum(item.total_amount),0)::numeric(15,2),count(DISTINCT item.consultation_id),count(*)
      INTO v_purchases,v_transactions,v_items
      FROM public.consultation_lab_items AS item
      JOIN public.consultations AS consultation ON consultation.id=item.consultation_id
     WHERE item.lab_id=p_lab_id AND consultation.created_at>=p_date_from AND consultation.created_at<p_date_to;
    WITH latest AS (
        SELECT DISTINCT ON (payment.payment_id) payment.amount
          FROM public.lab_payments AS payment
         WHERE payment.lab_id=p_lab_id AND payment.paid_at>=p_date_from AND payment.paid_at<p_date_to
         ORDER BY payment.payment_id,payment.revision_number DESC
    ) SELECT coalesce(sum(latest.amount),0)::numeric(15,2) INTO v_paid FROM latest;
    RETURN jsonb_build_object('labId',p_lab_id,'dateFrom',p_date_from,'dateTo',p_date_to,
      'totalPurchases',security.lab_money(v_purchases),'totalPaid',security.lab_money(v_paid),
      'remainingBalance',security.lab_money(v_purchases-v_paid),
      'transactionCount',v_transactions,'itemCount',v_items);
END
$function$;

CREATE OR REPLACE FUNCTION public.list_lab_payments(
    p_lab_id uuid,p_date_from timestamptz,p_date_to timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_result jsonb;
BEGIN
    SELECT actor.id INTO v_actor_id FROM security.lab_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'LAB_TRANSACTION_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
    IF p_lab_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.labs WHERE id=p_lab_id) THEN
        RAISE EXCEPTION 'LAB_TRANSACTION_LAB_NOT_FOUND' USING ERRCODE='P4020';
    END IF;
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>=p_date_to THEN
        RAISE EXCEPTION 'LAB_TRANSACTION_DATE_RANGE_INVALID' USING ERRCODE='22023';
    END IF;
    WITH latest AS (
        SELECT DISTINCT ON (payment.payment_id) payment.* FROM public.lab_payments AS payment
         WHERE payment.lab_id=p_lab_id AND payment.paid_at>=p_date_from AND payment.paid_at<p_date_to
         ORDER BY payment.payment_id,payment.revision_number DESC
    ) SELECT coalesce(jsonb_agg(jsonb_build_object(
        'paymentId',latest.payment_id,'labId',latest.lab_id,'amount',security.lab_money(latest.amount),
        'paidAt',latest.paid_at,'note',latest.note,'revision',latest.revision_number,
        'corrected',latest.revision_number>1,'correctionReason',latest.correction_reason,
        'createdAt',latest.created_at
    ) ORDER BY latest.paid_at DESC,latest.payment_id DESC),'[]'::jsonb) INTO v_result FROM latest;
    RETURN v_result;
END
$function$;

CREATE OR REPLACE FUNCTION public.create_lab_payment(
    p_lab_id uuid,p_amount numeric,p_paid_at timestamptz,p_note text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_payment_id uuid:=gen_random_uuid(); v_record public.lab_payments%ROWTYPE;
BEGIN
    SELECT actor.id INTO v_actor_id FROM security.lab_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'LAB_TRANSACTION_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.labs WHERE id=p_lab_id AND is_active) THEN
        RAISE EXCEPTION 'LAB_TRANSACTION_LAB_NOT_ACTIVE' USING ERRCODE='P4021';
    END IF;
    IF p_amount IS NULL OR p_amount<=0 OR scale(p_amount)>2 OR p_paid_at IS NULL
       OR (p_note IS NOT NULL AND char_length(p_note)>2000) THEN
        RAISE EXCEPTION 'LAB_PAYMENT_INVALID' USING ERRCODE='22023';
    END IF;
    INSERT INTO public.lab_payments(payment_id,lab_id,revision_number,amount,paid_at,note,created_by)
    VALUES (v_payment_id,p_lab_id,1,p_amount,p_paid_at,nullif(btrim(p_note),''),v_actor_id)
    RETURNING * INTO v_record;
    RETURN jsonb_build_object('paymentId',v_record.payment_id,'labId',v_record.lab_id,
      'amount',security.lab_money(v_record.amount),'paidAt',v_record.paid_at,'note',v_record.note,'revision',1);
END
$function$;

CREATE OR REPLACE FUNCTION public.correct_lab_payment(
    p_payment_id uuid,p_expected_revision integer,p_amount numeric,p_paid_at timestamptz,p_note text,p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_current public.lab_payments%ROWTYPE; v_record public.lab_payments%ROWTYPE;
BEGIN
    SELECT actor.id INTO v_actor_id FROM security.lab_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'LAB_TRANSACTION_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
    SELECT * INTO v_current FROM public.lab_payments WHERE payment_id=p_payment_id
      ORDER BY revision_number DESC LIMIT 1 FOR UPDATE;
    IF v_current.id IS NULL THEN RAISE EXCEPTION 'LAB_PAYMENT_NOT_FOUND' USING ERRCODE='P4022'; END IF;
    IF v_current.revision_number<>p_expected_revision THEN RAISE EXCEPTION 'LAB_PAYMENT_REVISION_CONFLICT' USING ERRCODE='40001'; END IF;
    IF p_amount IS NULL OR p_amount<=0 OR scale(p_amount)>2 OR p_paid_at IS NULL
       OR p_reason IS NULL OR btrim(p_reason)='' OR char_length(p_reason)>1000
       OR (p_note IS NOT NULL AND char_length(p_note)>2000) THEN
        RAISE EXCEPTION 'LAB_PAYMENT_CORRECTION_INVALID' USING ERRCODE='22023';
    END IF;
    INSERT INTO public.lab_payments(payment_id,lab_id,revision_number,amount,paid_at,note,correction_reason,created_by)
    VALUES (v_current.payment_id,v_current.lab_id,v_current.revision_number+1,p_amount,p_paid_at,
      nullif(btrim(p_note),''),btrim(p_reason),v_actor_id) RETURNING * INTO v_record;
    RETURN jsonb_build_object('paymentId',v_record.payment_id,'labId',v_record.lab_id,
      'amount',security.lab_money(v_record.amount),'paidAt',v_record.paid_at,'note',v_record.note,
      'revision',v_record.revision_number,'corrected',true,'correctionReason',v_record.correction_reason);
END
$function$;

REVOKE ALL ON FUNCTION security.reject_lab_payment_mutation() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.list_lab_transactions(uuid,timestamptz,timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_lab_transaction_summary(uuid,timestamptz,timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_lab_payments(uuid,timestamptz,timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_lab_payment(uuid,numeric,timestamptz,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.correct_lab_payment(uuid,integer,numeric,timestamptz,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_lab_transactions(uuid,timestamptz,timestamptz) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_lab_transaction_summary(uuid,timestamptz,timestamptz) FROM anon;
REVOKE EXECUTE ON FUNCTION public.list_lab_payments(uuid,timestamptz,timestamptz) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_lab_payment(uuid,numeric,timestamptz,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.correct_lab_payment(uuid,integer,numeric,timestamptz,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_lab_transactions(uuid,timestamptz,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_lab_transaction_summary(uuid,timestamptz,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_lab_payments(uuid,timestamptz,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_lab_payment(uuid,numeric,timestamptz,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.correct_lab_payment(uuid,integer,numeric,timestamptz,text,text) TO authenticated;

COMMIT;
