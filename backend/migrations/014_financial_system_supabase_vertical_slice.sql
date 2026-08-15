-- C6 complete financial-system Supabase vertical slice.
BEGIN;

-- RPC-only containment: financial internals are never directly writable/readable
-- by browser roles.
REVOKE ALL ON TABLE public.clinic_procedures FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.consultation_procedures FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.financial_payment_records FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.financial_payment_allocations FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.financial_charge_adjustments FROM PUBLIC, anon, authenticated;
ALTER TABLE public.clinic_procedures ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consultation_procedures ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financial_payment_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financial_payment_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financial_charge_adjustments ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION security.financial_actor()
RETURNS TABLE (id uuid, role text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT app_user.id, app_user.role::text
    FROM public.users AS app_user
    WHERE app_user.supabase_user_id = auth.uid()
      AND app_user.is_active = true
      AND app_user.approved_at IS NOT NULL
      AND app_user.role IN ('doctor', 'admin')
    LIMIT 1
$function$;

CREATE OR REPLACE FUNCTION security.financial_money(p_value numeric)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT to_char(coalesce(p_value, 0), 'FM999999999999990.00')
$function$;

CREATE OR REPLACE FUNCTION security.current_financial_appointment(
    p_patient_id uuid, p_actor_id uuid, p_actor_role text
)
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT appointment.id
    FROM public.appointments AS appointment
    WHERE appointment.patient_id = p_patient_id
      AND (appointment.date = CURRENT_DATE OR appointment.appointment_date = CURRENT_DATE)
      AND appointment.status::text IN ('pending', 'confirmed')
      AND appointment.doctor_id IS NOT NULL
      AND (p_actor_role = 'admin' OR appointment.doctor_id = p_actor_id)
    ORDER BY CASE WHEN appointment.doctor_id = p_actor_id THEN 0 ELSE 1 END,
             appointment.date NULLS LAST, appointment.appointment_date NULLS LAST,
             appointment.appointment_time NULLS LAST, appointment.time NULLS LAST,
             appointment.id
    LIMIT 1
$function$;

CREATE OR REPLACE FUNCTION security.financial_effective_items(p_consultation_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
    WITH effective AS (
        SELECT selection.id, selection.procedure_id, selection.procedure_name_snapshot,
               selection.unit_price_snapshot,
               selection.quantity - coalesce(sum(adjustment.quantity_delta), 0)::integer AS quantity,
               selection.created_at
        FROM public.consultation_procedures AS selection
        LEFT JOIN public.financial_charge_adjustments AS adjustment
          ON adjustment.consultation_procedure_id = selection.id
        WHERE selection.consultation_id = p_consultation_id
        GROUP BY selection.id
    )
    SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', effective.id,
        'procedureId', effective.procedure_id,
        'name', effective.procedure_name_snapshot,
        'unitPrice', security.financial_money(effective.unit_price_snapshot),
        'quantity', effective.quantity,
        'lineTotal', security.financial_money(effective.unit_price_snapshot * effective.quantity)
    ) ORDER BY effective.created_at, effective.id), '[]'::jsonb)
    FROM effective
    WHERE effective.quantity > 0
$function$;

CREATE OR REPLACE FUNCTION security.financial_billing_projection(p_consultation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_consultation public.consultations%ROWTYPE;
    v_patient_name text;
    v_items jsonb;
    v_payments jsonb;
    v_outstanding jsonb := '[]'::jsonb;
    v_gross numeric := 0;
    v_billed numeric := 0;
    v_paid numeric := 0;
    v_remaining_payment numeric;
    v_item jsonb;
    v_line numeric;
    v_due numeric;
BEGIN
    SELECT * INTO v_consultation FROM public.consultations WHERE id = p_consultation_id;
    IF v_consultation.id IS NULL THEN RETURN NULL; END IF;
    SELECT patient.name INTO v_patient_name FROM public.patients AS patient
      WHERE patient.id = v_consultation.patient_id;
    v_items := security.financial_effective_items(p_consultation_id);
    SELECT coalesce(sum(selection.quantity * selection.unit_price_snapshot), 0)
      INTO v_gross
      FROM public.consultation_procedures AS selection
     WHERE selection.consultation_id = p_consultation_id;
    SELECT coalesce(sum((item ->> 'lineTotal')::numeric), 0)
      INTO v_billed FROM jsonb_array_elements(v_items) AS item;

    WITH latest AS (
        SELECT DISTINCT ON (payment.payment_id) payment.*
        FROM public.financial_payment_records AS payment
        WHERE payment.consultation_id = p_consultation_id
        ORDER BY payment.payment_id, payment.revision_number DESC
    )
    SELECT coalesce(sum(latest.amount), 0),
           coalesce(jsonb_agg(jsonb_build_object(
               'paymentId', latest.payment_id,
               'revision', latest.revision_number,
               'amount', security.financial_money(latest.amount),
               'paidAt', latest.paid_at,
               'corrected', latest.revision_number > 1,
               'correctionReason', latest.correction_reason
           ) ORDER BY latest.paid_at, latest.payment_id), '[]'::jsonb)
      INTO v_paid, v_payments
      FROM latest;

    v_remaining_payment := v_paid;
    FOR v_item IN SELECT value FROM jsonb_array_elements(v_items) LOOP
        v_line := (v_item ->> 'lineTotal')::numeric;
        v_due := greatest(v_line - least(v_line, v_remaining_payment), 0);
        v_remaining_payment := greatest(v_remaining_payment - v_line, 0);
        IF v_due > 0 THEN
            v_outstanding := v_outstanding || jsonb_build_array(jsonb_build_object(
                'procedureId', v_item ->> 'id', 'name', v_item ->> 'name',
                'remaining', security.financial_money(v_due)
            ));
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'consultationId', v_consultation.id,
        'consultationReference', v_consultation.id::text,
        'consultationDate', v_consultation.created_at,
        'appointmentId', v_consultation.appointment_id,
        'patient', jsonb_build_object('id', v_consultation.patient_id, 'name', coalesce(v_patient_name, 'Unknown')),
        'billingVersion', v_consultation.billing_version,
        'procedures', v_items,
        'payments', v_payments,
        'grossTotal', security.financial_money(v_gross),
        'adjustmentTotal', security.financial_money(v_gross - v_billed),
        'effectiveTotal', security.financial_money(v_billed),
        'billedTotal', security.financial_money(v_billed),
        'paidTotal', security.financial_money(v_paid),
        'balance', security.financial_money(v_paid - v_billed),
        'outstandingTotal', security.financial_money(greatest(v_billed - v_paid, 0)),
        'creditTotal', security.financial_money(greatest(v_paid - v_billed, 0)),
        'outstandingItems', v_outstanding
    );
END
$function$;

-- Forward declarations allow public RPC bodies to be created before the full
-- private helper implementations later in this transaction.
CREATE OR REPLACE FUNCTION security.financial_patient_history(uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $function$ SELECT NULL::jsonb $function$;
CREATE OR REPLACE FUNCTION security.financial_patient_outstanding(uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $function$ SELECT NULL::jsonb $function$;
CREATE OR REPLACE FUNCTION security.rebalance_financial_allocations(uuid, uuid, uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $function$ BEGIN RETURN; END $function$;

CREATE OR REPLACE FUNCTION public.list_financial_billing()
RETURNS SETOF jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text;
BEGIN
    SELECT actor.id, actor.role INTO v_actor_id, v_actor_role FROM security.financial_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'FINANCIAL_AUTHORIZATION_DENIED' USING ERRCODE = '42501'; END IF;
    RETURN QUERY SELECT security.financial_billing_projection(consultation.id)
    FROM public.consultations AS consultation
    WHERE EXISTS (SELECT 1 FROM public.consultation_procedures AS selection
                  WHERE selection.consultation_id = consultation.id)
    ORDER BY consultation.created_at DESC, consultation.id DESC;
END
$function$;

CREATE OR REPLACE FUNCTION public.get_patient_financial_history(p_patient_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text;
BEGIN
    SELECT actor.id, actor.role INTO v_actor_id, v_actor_role FROM security.financial_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'FINANCIAL_AUTHORIZATION_DENIED' USING ERRCODE = '42501'; END IF;
    RETURN security.financial_patient_history(p_patient_id);
END
$function$;

CREATE OR REPLACE FUNCTION public.get_patient_financial_outstanding(p_patient_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text;
BEGIN
    SELECT actor.id, actor.role INTO v_actor_id, v_actor_role FROM security.financial_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'FINANCIAL_AUTHORIZATION_DENIED' USING ERRCODE = '42501'; END IF;
    RETURN security.financial_patient_outstanding(p_patient_id);
END
$function$;

CREATE OR REPLACE FUNCTION public.get_patient_financial_summaries()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text; v_result jsonb;
BEGIN
    SELECT actor.id, actor.role INTO v_actor_id, v_actor_role FROM security.financial_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'FINANCIAL_AUTHORIZATION_DENIED' USING ERRCODE = '42501'; END IF;
    SELECT coalesce(jsonb_object_agg(patient_id::text,
               security.financial_patient_outstanding(patient_id)), '{}'::jsonb)
      INTO v_result
      FROM (SELECT DISTINCT consultation.patient_id
            FROM public.consultations AS consultation
            WHERE EXISTS (SELECT 1 FROM public.consultation_procedures AS selection
                          WHERE selection.consultation_id = consultation.id)) AS patients;
    RETURN v_result;
END
$function$;

CREATE OR REPLACE FUNCTION public.add_financial_payment(
    p_consultation_id uuid, p_billing_version integer,
    p_amount numeric, p_paid_at timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text; v_consultation public.consultations%ROWTYPE;
        v_record_id uuid := gen_random_uuid();
BEGIN
    SELECT actor.id, actor.role INTO v_actor_id, v_actor_role FROM security.financial_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'FINANCIAL_AUTHORIZATION_DENIED' USING ERRCODE = '42501'; END IF;
    IF p_amount IS NULL OR p_amount <= 0 OR scale(p_amount) > 2 OR p_paid_at IS NULL THEN
        RAISE EXCEPTION 'FINANCIAL_PAYMENT_INVALID' USING ERRCODE = 'P3013';
    END IF;
    SELECT * INTO v_consultation FROM public.consultations
      WHERE id = p_consultation_id FOR UPDATE;
    IF v_consultation.id IS NULL THEN RAISE EXCEPTION 'FINANCIAL_NO_CURRENT_CONSULTATION' USING ERRCODE = 'P3004'; END IF;
    IF v_consultation.billing_version <> p_billing_version THEN
        RAISE EXCEPTION 'FINANCIAL_BILLING_VERSION_CONFLICT' USING ERRCODE = 'P3011';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.consultation_procedures
                   WHERE consultation_id = p_consultation_id) THEN
        RAISE EXCEPTION 'FINANCIAL_NO_BILLED_PROCEDURES' USING ERRCODE = 'P3006';
    END IF;
    PERFORM 1 FROM public.financial_payment_records
      WHERE consultation_id = p_consultation_id FOR UPDATE;
    INSERT INTO public.financial_payment_records (
        id, payment_id, consultation_id, revision_number, amount, paid_at,
        correction_reason, created_by, created_at
    ) VALUES (
        v_record_id, gen_random_uuid(), p_consultation_id, 1, p_amount,
        p_paid_at, NULL, v_actor_id, now()
    );
    PERFORM security.rebalance_financial_allocations(p_consultation_id, v_actor_id, v_record_id);
    UPDATE public.consultations SET billing_version = billing_version + 1
      WHERE id = p_consultation_id;
    RETURN security.financial_billing_projection(p_consultation_id);
END
$function$;

CREATE OR REPLACE FUNCTION public.correct_financial_payment(
    p_payment_id uuid, p_billing_version integer, p_expected_revision integer,
    p_amount numeric, p_paid_at timestamptz, p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text; v_current public.financial_payment_records%ROWTYPE;
        v_consultation public.consultations%ROWTYPE; v_record_id uuid := gen_random_uuid();
BEGIN
    SELECT actor.id, actor.role INTO v_actor_id, v_actor_role FROM security.financial_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'FINANCIAL_AUTHORIZATION_DENIED' USING ERRCODE = '42501'; END IF;
    IF p_amount IS NULL OR p_amount <= 0 OR scale(p_amount) > 2 OR p_paid_at IS NULL
       OR p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'FINANCIAL_PAYMENT_INVALID' USING ERRCODE = 'P3013';
    END IF;
    SELECT * INTO v_current FROM public.financial_payment_records
      WHERE payment_id = p_payment_id
      ORDER BY revision_number DESC LIMIT 1 FOR UPDATE;
    IF v_current.id IS NULL THEN RAISE EXCEPTION 'FINANCIAL_PAYMENT_NOT_FOUND' USING ERRCODE = 'P3007'; END IF;
    SELECT * INTO v_consultation FROM public.consultations
      WHERE id = v_current.consultation_id FOR UPDATE;
    IF v_consultation.billing_version <> p_billing_version THEN
        RAISE EXCEPTION 'FINANCIAL_BILLING_VERSION_CONFLICT' USING ERRCODE = 'P3011';
    END IF;
    IF v_current.revision_number <> p_expected_revision THEN
        RAISE EXCEPTION 'FINANCIAL_PAYMENT_REVISION_CONFLICT' USING ERRCODE = 'P3012';
    END IF;
    INSERT INTO public.financial_payment_records (
        id, payment_id, consultation_id, revision_number, amount, paid_at,
        correction_reason, created_by, created_at
    ) VALUES (
        v_record_id, v_current.payment_id, v_current.consultation_id,
        v_current.revision_number + 1, p_amount, p_paid_at,
        btrim(p_reason), v_actor_id, now()
    );
    PERFORM security.rebalance_financial_allocations(v_current.consultation_id, v_actor_id, v_record_id);
    UPDATE public.consultations SET billing_version = billing_version + 1
      WHERE id = v_current.consultation_id;
    RETURN security.financial_billing_projection(v_current.consultation_id);
END
$function$;

CREATE OR REPLACE FUNCTION public.save_current_consultation_procedures(
    p_patient_id uuid, p_version integer, p_selections jsonb
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text; v_appointment_id uuid;
        v_consultation public.consultations%ROWTYPE; v_selection jsonb;
        v_previous record; v_catalog public.clinic_procedures%ROWTYPE;
        v_snapshots jsonb := '{}'::jsonb; v_snapshot jsonb;
        v_target_quantity integer; v_current_quantity integer; v_delta integer;
        v_has_payments boolean; v_changed boolean := false;
BEGIN
    SELECT actor.id, actor.role INTO v_actor_id, v_actor_role FROM security.financial_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'FINANCIAL_AUTHORIZATION_DENIED' USING ERRCODE = '42501'; END IF;
    IF p_version IS NULL OR p_version < 0 OR p_selections IS NULL
       OR jsonb_typeof(p_selections) <> 'array' THEN
        RAISE EXCEPTION 'FINANCIAL_SELECTION_INVALID' USING ERRCODE = 'P3014';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_selections) AS selected(value)
        WHERE jsonb_typeof(selected.value) <> 'object'
           OR NOT (selected.value ? 'procedureId' AND selected.value ? 'quantity')
           OR jsonb_typeof(selected.value -> 'quantity') <> 'number'
           OR (selected.value ->> 'quantity')::numeric <> trunc((selected.value ->> 'quantity')::numeric)
           OR (selected.value ->> 'quantity')::numeric NOT BETWEEN 1 AND 999
    ) THEN RAISE EXCEPTION 'FINANCIAL_INVALID_QUANTITY' USING ERRCODE = 'P3008'; END IF;
    IF EXISTS (
        SELECT selected.value ->> 'procedureId'
        FROM jsonb_array_elements(p_selections) AS selected(value)
        GROUP BY selected.value ->> 'procedureId' HAVING count(*) > 1
    ) THEN RAISE EXCEPTION 'FINANCIAL_DUPLICATE_SELECTION' USING ERRCODE = 'P3009'; END IF;

    v_appointment_id := security.current_financial_appointment(p_patient_id, v_actor_id, v_actor_role);
    IF v_appointment_id IS NULL THEN RAISE EXCEPTION 'FINANCIAL_NO_CURRENT_APPOINTMENT' USING ERRCODE = 'P3002'; END IF;
    PERFORM 1 FROM public.appointments WHERE id = v_appointment_id FOR UPDATE;
    SELECT * INTO v_consultation FROM public.consultations
    WHERE appointment_id = v_appointment_id AND patient_id = p_patient_id
    ORDER BY last_updated DESC NULLS LAST, created_at DESC NULLS LAST, id DESC
    LIMIT 1 FOR UPDATE;
    IF v_consultation.id IS NULL THEN RAISE EXCEPTION 'FINANCIAL_NO_CURRENT_CONSULTATION' USING ERRCODE = 'P3004'; END IF;
    IF v_consultation.doctor_id IS NOT NULL AND v_actor_role = 'doctor'
       AND v_consultation.doctor_id <> v_actor_id THEN RAISE EXCEPTION 'FINANCIAL_AUTHORIZATION_DENIED' USING ERRCODE = '42501'; END IF;
    IF v_consultation.procedures_version <> p_version THEN
        RAISE EXCEPTION 'FINANCIAL_PROCEDURES_VERSION_CONFLICT' USING ERRCODE = 'P3010';
    END IF;

    PERFORM 1 FROM public.consultation_procedures
      WHERE consultation_id = v_consultation.id FOR UPDATE;
    PERFORM 1 FROM public.financial_payment_records
      WHERE consultation_id = v_consultation.id FOR UPDATE;

    FOR v_selection IN SELECT value FROM jsonb_array_elements(p_selections) LOOP
        BEGIN
            SELECT * INTO v_catalog FROM public.clinic_procedures
              WHERE id = (v_selection ->> 'procedureId')::uuid FOR SHARE;
        EXCEPTION WHEN invalid_text_representation THEN
            RAISE EXCEPTION 'FINANCIAL_INVALID_PROCEDURE' USING ERRCODE = '22023';
        END;
        IF v_catalog.id IS NULL THEN RAISE EXCEPTION 'FINANCIAL_INVALID_PROCEDURE' USING ERRCODE = 'P3003'; END IF;
        IF NOT v_catalog.is_active AND NOT EXISTS (
            SELECT 1 FROM public.consultation_procedures
            WHERE consultation_id = v_consultation.id AND procedure_id = v_catalog.id
        ) THEN RAISE EXCEPTION 'FINANCIAL_INACTIVE_PROCEDURE' USING ERRCODE = 'P3005'; END IF;
    END LOOP;

    SELECT EXISTS (SELECT 1 FROM public.financial_payment_records
                   WHERE consultation_id = v_consultation.id) INTO v_has_payments;
    IF NOT v_has_payments THEN
        SELECT coalesce(jsonb_object_agg(previous.procedure_id::text,
                   jsonb_build_object('name', previous.procedure_name_snapshot,
                                      'price', previous.unit_price_snapshot)), '{}'::jsonb)
          INTO v_snapshots
          FROM public.consultation_procedures AS previous
         WHERE previous.consultation_id = v_consultation.id;
        DELETE FROM public.consultation_procedures WHERE consultation_id = v_consultation.id;
        FOR v_selection IN SELECT value FROM jsonb_array_elements(p_selections) LOOP
            SELECT * INTO v_catalog FROM public.clinic_procedures
              WHERE id = (v_selection ->> 'procedureId')::uuid;
            v_snapshot := v_snapshots -> (v_catalog.id::text);
            INSERT INTO public.consultation_procedures (
                id, consultation_id, procedure_id, procedure_name_snapshot,
                unit_price_snapshot, quantity, created_at
            ) VALUES (
                gen_random_uuid(), v_consultation.id, v_catalog.id,
                coalesce(v_snapshot ->> 'name', v_catalog.name),
                coalesce((v_snapshot ->> 'price')::numeric, v_catalog.price),
                (v_selection ->> 'quantity')::integer, now()
            );
        END LOOP;
    ELSE
        FOR v_previous IN
            SELECT selection.*,
                   selection.quantity - coalesce(sum(adjustment.quantity_delta), 0)::integer AS effective_quantity
            FROM public.consultation_procedures AS selection
            LEFT JOIN public.financial_charge_adjustments AS adjustment
              ON adjustment.consultation_procedure_id = selection.id
            WHERE selection.consultation_id = v_consultation.id
            GROUP BY selection.id
            ORDER BY selection.created_at, selection.id
        LOOP
            SELECT coalesce(max((selected.value ->> 'quantity')::integer), 0)
              INTO v_target_quantity
              FROM jsonb_array_elements(p_selections) AS selected(value)
             WHERE selected.value ->> 'procedureId' = v_previous.procedure_id::text;
            v_current_quantity := v_previous.effective_quantity;
            v_delta := v_current_quantity - v_target_quantity;
            IF v_delta <> 0 THEN
                INSERT INTO public.financial_charge_adjustments (
                    id, consultation_procedure_id, quantity_delta,
                    unit_price_snapshot, reason, created_by, created_at
                ) VALUES (
                    gen_random_uuid(), v_previous.id, v_delta,
                    v_previous.unit_price_snapshot,
                    'Procedure quantity corrected after payment history',
                    v_actor_id, now()
                );
                v_changed := true;
            END IF;
        END LOOP;
        FOR v_selection IN SELECT value FROM jsonb_array_elements(p_selections) LOOP
            IF NOT EXISTS (SELECT 1 FROM public.consultation_procedures
                           WHERE consultation_id = v_consultation.id
                             AND procedure_id = (v_selection ->> 'procedureId')::uuid) THEN
                SELECT * INTO v_catalog FROM public.clinic_procedures
                  WHERE id = (v_selection ->> 'procedureId')::uuid;
                INSERT INTO public.consultation_procedures (
                    id, consultation_id, procedure_id, procedure_name_snapshot,
                    unit_price_snapshot, quantity, created_at
                ) VALUES (
                    gen_random_uuid(), v_consultation.id, v_catalog.id, v_catalog.name,
                    v_catalog.price, (v_selection ->> 'quantity')::integer, now()
                );
                v_changed := true;
            END IF;
        END LOOP;
        IF v_changed THEN
            PERFORM security.rebalance_financial_allocations(v_consultation.id, v_actor_id, NULL);
            UPDATE public.consultations SET billing_version = billing_version + 1
              WHERE id = v_consultation.id;
        END IF;
    END IF;
    UPDATE public.consultations SET procedures_version = procedures_version + 1
      WHERE id = v_consultation.id;
    RETURN public.get_current_consultation_procedures(p_patient_id);
END
$function$;

CREATE OR REPLACE FUNCTION security.financial_patient_history(p_patient_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_patient_name text;
    v_cards jsonb;
    v_billed numeric;
    v_paid numeric;
BEGIN
    SELECT patient.name INTO v_patient_name FROM public.patients AS patient
      WHERE patient.id = p_patient_id;
    IF v_patient_name IS NULL THEN
        RAISE EXCEPTION 'FINANCIAL_PATIENT_NOT_FOUND' USING ERRCODE = 'P3001';
    END IF;
    WITH cards AS (
        SELECT security.financial_billing_projection(consultation.id) AS card,
               consultation.created_at, consultation.id
        FROM public.consultations AS consultation
        WHERE consultation.patient_id = p_patient_id
          AND EXISTS (SELECT 1 FROM public.consultation_procedures AS selection
                      WHERE selection.consultation_id = consultation.id)
        ORDER BY consultation.created_at DESC, consultation.id DESC
    )
    SELECT coalesce(jsonb_agg(card ORDER BY created_at DESC, id DESC), '[]'::jsonb),
           coalesce(sum((card ->> 'billedTotal')::numeric), 0),
           coalesce(sum((card ->> 'paidTotal')::numeric), 0)
      INTO v_cards, v_billed, v_paid FROM cards;
    RETURN jsonb_build_object(
        'patient', jsonb_build_object('id', p_patient_id, 'name', v_patient_name),
        'billedTotal', security.financial_money(v_billed),
        'paidTotal', security.financial_money(v_paid),
        'balance', security.financial_money(v_paid - v_billed),
        'outstandingTotal', security.financial_money(greatest(v_billed - v_paid, 0)),
        'creditTotal', security.financial_money(greatest(v_paid - v_billed, 0)),
        'consultations', v_cards
    );
END
$function$;

CREATE OR REPLACE FUNCTION security.financial_patient_outstanding(p_patient_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_history jsonb := security.financial_patient_history(p_patient_id);
    v_items jsonb;
BEGIN
    SELECT coalesce(jsonb_agg(
        outstanding.item || jsonb_build_object(
            'consultationId', card.value -> 'consultationId',
            'consultationReference', card.value -> 'consultationReference',
            'consultationDate', card.value -> 'consultationDate'
        )
    ), '[]'::jsonb)
    INTO v_items
    FROM jsonb_array_elements(v_history -> 'consultations') AS card(value)
    CROSS JOIN LATERAL jsonb_array_elements(card.value -> 'outstandingItems') AS outstanding(item);
    RETURN jsonb_build_object(
        'patient', v_history -> 'patient',
        'totalOutstanding', v_history -> 'outstandingTotal',
        'items', v_items
    );
END
$function$;

CREATE OR REPLACE FUNCTION security.rebalance_financial_allocations(
    p_consultation_id uuid,
    p_actor_id uuid,
    p_new_record_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_payment record;
    v_item record;
    v_remaining_by_item jsonb := '{}'::jsonb;
    v_desired jsonb;
    v_existing jsonb;
    v_amount numeric;
    v_available numeric;
    v_allocate numeric;
    v_target_record_id uuid;
    v_pair jsonb;
BEGIN
    FOR v_item IN
        SELECT selection.id,
               selection.unit_price_snapshot *
                 (selection.quantity - coalesce(sum(adjustment.quantity_delta), 0)) AS amount
        FROM public.consultation_procedures AS selection
        LEFT JOIN public.financial_charge_adjustments AS adjustment
          ON adjustment.consultation_procedure_id = selection.id
        WHERE selection.consultation_id = p_consultation_id
        GROUP BY selection.id
        HAVING selection.quantity - coalesce(sum(adjustment.quantity_delta), 0) > 0
        ORDER BY selection.created_at, selection.id
    LOOP
        v_remaining_by_item := v_remaining_by_item || jsonb_build_object(v_item.id::text, v_item.amount);
    END LOOP;

    FOR v_payment IN
        SELECT latest.* FROM (
            SELECT DISTINCT ON (payment.payment_id) payment.*
            FROM public.financial_payment_records AS payment
            WHERE payment.consultation_id = p_consultation_id
            ORDER BY payment.payment_id, payment.revision_number DESC
        ) AS latest
        ORDER BY latest.paid_at, latest.payment_id
    LOOP
        v_amount := v_payment.amount;
        v_desired := '[]'::jsonb;
        FOR v_item IN
            SELECT selection.id
            FROM public.consultation_procedures AS selection
            WHERE selection.consultation_id = p_consultation_id
              AND (v_remaining_by_item ->> selection.id::text)::numeric > 0
            ORDER BY selection.created_at, selection.id
        LOOP
            EXIT WHEN v_amount <= 0;
            v_available := (v_remaining_by_item ->> v_item.id::text)::numeric;
            v_allocate := least(v_available, v_amount);
            IF v_allocate > 0 THEN
                v_desired := v_desired || jsonb_build_array(jsonb_build_object(
                    'procedureId', v_item.id, 'amount', v_allocate
                ));
                v_remaining_by_item := jsonb_set(
                    v_remaining_by_item, ARRAY[v_item.id::text],
                    to_jsonb(v_available - v_allocate)
                );
                v_amount := v_amount - v_allocate;
            END IF;
        END LOOP;

        SELECT coalesce(jsonb_agg(jsonb_build_object(
                   'procedureId', allocation.consultation_procedure_id,
                   'amount', allocation.allocated_amount
               ) ORDER BY allocation.consultation_procedure_id), '[]'::jsonb)
          INTO v_existing
          FROM public.financial_payment_allocations AS allocation
         WHERE allocation.payment_record_id = v_payment.id;

        SELECT coalesce(jsonb_agg(value ORDER BY value ->> 'procedureId'), '[]'::jsonb)
          INTO v_desired FROM jsonb_array_elements(v_desired);

        IF v_existing IS DISTINCT FROM v_desired THEN
            v_target_record_id := v_payment.id;
            IF (p_new_record_id IS NULL OR v_payment.id <> p_new_record_id)
               AND jsonb_array_length(v_existing) > 0 THEN
                INSERT INTO public.financial_payment_records (
                    id, payment_id, consultation_id, revision_number, amount,
                    paid_at, correction_reason, created_by, created_at
                ) VALUES (
                    gen_random_uuid(), v_payment.payment_id, v_payment.consultation_id,
                    v_payment.revision_number + 1, v_payment.amount, v_payment.paid_at,
                    'Automatic allocation rebalance', p_actor_id, now()
                ) RETURNING id INTO v_target_record_id;
            END IF;
            FOR v_pair IN SELECT value FROM jsonb_array_elements(v_desired) LOOP
                INSERT INTO public.financial_payment_allocations (
                    id, payment_record_id, consultation_procedure_id,
                    allocated_amount, created_at
                ) VALUES (
                    gen_random_uuid(), v_target_record_id,
                    (v_pair ->> 'procedureId')::uuid,
                    (v_pair ->> 'amount')::numeric, now()
                );
            END LOOP;
        END IF;
    END LOOP;
END
$function$;

REVOKE ALL ON FUNCTION security.financial_actor() FROM PUBLIC;
REVOKE ALL ON FUNCTION security.financial_money(numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION security.current_financial_appointment(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION security.financial_effective_items(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION security.financial_billing_projection(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION security.financial_patient_history(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION security.financial_patient_outstanding(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION security.rebalance_financial_allocations(uuid, uuid, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.list_clinic_procedures(p_active_only boolean DEFAULT false)
RETURNS TABLE (id uuid, name text, price text, "isActive" boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text;
BEGIN
    SELECT actor.id, actor.role INTO v_actor_id, v_actor_role FROM security.financial_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'FINANCIAL_AUTHORIZATION_DENIED' USING ERRCODE = '42501'; END IF;
    RETURN QUERY SELECT procedure.id, procedure.name::text,
        security.financial_money(procedure.price), procedure.is_active
    FROM public.clinic_procedures AS procedure
    WHERE NOT p_active_only OR procedure.is_active
    ORDER BY lower(btrim(procedure.name)), procedure.id;
END
$function$;

CREATE OR REPLACE FUNCTION public.create_clinic_procedure(p_name text, p_price numeric)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text; v_row public.clinic_procedures%ROWTYPE;
BEGIN
    SELECT actor.id, actor.role INTO v_actor_id, v_actor_role FROM security.financial_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'FINANCIAL_AUTHORIZATION_DENIED' USING ERRCODE = '42501'; END IF;
    IF p_name IS NULL OR btrim(p_name) = '' THEN RAISE EXCEPTION 'PROCEDURE_NAME_REQUIRED' USING ERRCODE = '22023'; END IF;
    IF p_price IS NULL OR p_price < 0 OR scale(p_price) > 2 THEN RAISE EXCEPTION 'PROCEDURE_PRICE_INVALID' USING ERRCODE = '22023'; END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(lower(btrim(p_name)), 0));
    IF EXISTS (SELECT 1 FROM public.clinic_procedures WHERE lower(btrim(name)) = lower(btrim(p_name))) THEN
        RAISE EXCEPTION 'PROCEDURE_DUPLICATE' USING ERRCODE = '23505';
    END IF;
    INSERT INTO public.clinic_procedures (id, name, price, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), btrim(p_name), p_price, true, now(), now()) RETURNING * INTO v_row;
    RETURN jsonb_build_object('id', v_row.id, 'name', v_row.name,
        'price', security.financial_money(v_row.price), 'isActive', v_row.is_active);
END
$function$;

CREATE OR REPLACE FUNCTION public.update_clinic_procedure(p_procedure_id uuid, p_updates jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text; v_row public.clinic_procedures%ROWTYPE;
        v_name text; v_price numeric;
BEGIN
    SELECT actor.id, actor.role INTO v_actor_id, v_actor_role FROM security.financial_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'FINANCIAL_AUTHORIZATION_DENIED' USING ERRCODE = '42501'; END IF;
    IF p_updates IS NULL OR jsonb_typeof(p_updates) <> 'object'
       OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_updates) AS key
                  WHERE key NOT IN ('name', 'price', 'is_active')) THEN
        RAISE EXCEPTION 'PROCEDURE_UPDATE_INVALID' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_row FROM public.clinic_procedures WHERE id = p_procedure_id FOR UPDATE;
    IF v_row.id IS NULL THEN RAISE EXCEPTION 'PROCEDURE_NOT_FOUND' USING ERRCODE = 'P3003'; END IF;
    v_name := CASE WHEN p_updates ? 'name' THEN btrim(p_updates ->> 'name') ELSE v_row.name END;
    v_price := CASE WHEN p_updates ? 'price' THEN (p_updates ->> 'price')::numeric ELSE v_row.price END;
    IF v_name IS NULL OR v_name = '' OR v_price < 0 OR scale(v_price) > 2 THEN
        RAISE EXCEPTION 'PROCEDURE_UPDATE_INVALID' USING ERRCODE = '22023';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(lower(v_name), 0));
    IF EXISTS (SELECT 1 FROM public.clinic_procedures
               WHERE lower(btrim(name)) = lower(v_name) AND id <> p_procedure_id) THEN
        RAISE EXCEPTION 'PROCEDURE_DUPLICATE' USING ERRCODE = '23505';
    END IF;
    UPDATE public.clinic_procedures SET name = v_name, price = v_price,
        is_active = CASE WHEN p_updates ? 'is_active' THEN (p_updates ->> 'is_active')::boolean ELSE is_active END,
        updated_at = now() WHERE id = p_procedure_id RETURNING * INTO v_row;
    RETURN jsonb_build_object('id', v_row.id, 'name', v_row.name,
        'price', security.financial_money(v_row.price), 'isActive', v_row.is_active);
END
$function$;

CREATE OR REPLACE FUNCTION public.get_current_consultation_procedures(p_patient_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text; v_appointment_id uuid; v_consultation public.consultations%ROWTYPE;
        v_items jsonb; v_total numeric;
BEGIN
    SELECT actor.id, actor.role INTO v_actor_id, v_actor_role FROM security.financial_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'FINANCIAL_AUTHORIZATION_DENIED' USING ERRCODE = '42501'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = p_patient_id) THEN RAISE EXCEPTION 'FINANCIAL_PATIENT_NOT_FOUND' USING ERRCODE = 'P3001'; END IF;
    v_appointment_id := security.current_financial_appointment(p_patient_id, v_actor_id, v_actor_role);
    IF v_appointment_id IS NULL THEN RAISE EXCEPTION 'FINANCIAL_NO_CURRENT_APPOINTMENT' USING ERRCODE = 'P3002'; END IF;
    SELECT * INTO v_consultation FROM public.consultations
    WHERE appointment_id = v_appointment_id AND patient_id = p_patient_id
    ORDER BY last_updated DESC NULLS LAST, created_at DESC NULLS LAST, id DESC LIMIT 1;
    IF v_consultation.id IS NULL THEN
        RETURN jsonb_build_object(
            'consultationId', NULL,
            'version', 0,
            'items', '[]'::jsonb,
            'total', '0.00'
        );
    END IF;
    IF v_consultation.doctor_id IS NOT NULL AND v_actor_role = 'doctor'
       AND v_consultation.doctor_id <> v_actor_id THEN RAISE EXCEPTION 'FINANCIAL_AUTHORIZATION_DENIED' USING ERRCODE = '42501'; END IF;
    v_items := security.financial_effective_items(v_consultation.id);
    SELECT coalesce(sum((item ->> 'lineTotal')::numeric), 0) INTO v_total
      FROM jsonb_array_elements(v_items) AS item;
    RETURN jsonb_build_object('consultationId', v_consultation.id,
        'version', v_consultation.procedures_version, 'items', v_items,
        'total', security.financial_money(v_total));
END
$function$;

REVOKE ALL ON FUNCTION public.list_clinic_procedures(boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_clinic_procedure(text, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_clinic_procedure(uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_current_consultation_procedures(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.save_current_consultation_procedures(uuid, integer, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_financial_billing() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_patient_financial_history(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_patient_financial_outstanding(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_patient_financial_summaries() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.add_financial_payment(uuid, integer, numeric, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.correct_financial_payment(uuid, integer, integer, numeric, timestamptz, text) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.list_clinic_procedures(boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_clinic_procedure(text, numeric) FROM anon;
REVOKE EXECUTE ON FUNCTION public.update_clinic_procedure(uuid, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_current_consultation_procedures(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.save_current_consultation_procedures(uuid, integer, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.list_financial_billing() FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_patient_financial_history(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_patient_financial_outstanding(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_patient_financial_summaries() FROM anon;
REVOKE EXECUTE ON FUNCTION public.add_financial_payment(uuid, integer, numeric, timestamptz) FROM anon;
REVOKE EXECUTE ON FUNCTION public.correct_financial_payment(uuid, integer, integer, numeric, timestamptz, text) FROM anon;

GRANT EXECUTE ON FUNCTION public.list_clinic_procedures(boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_clinic_procedure(text, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_clinic_procedure(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_current_consultation_procedures(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_current_consultation_procedures(uuid, integer, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_financial_billing() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_patient_financial_history(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_patient_financial_outstanding(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_patient_financial_summaries() TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_financial_payment(uuid, integer, numeric, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.correct_financial_payment(uuid, integer, integer, numeric, timestamptz, text) TO authenticated;

COMMIT;
