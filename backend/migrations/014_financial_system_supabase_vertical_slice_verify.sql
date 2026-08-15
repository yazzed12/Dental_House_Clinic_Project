-- Read-only verification for Migration 014. Run manually only after approval.
DO $verify$
DECLARE v_definition text;
BEGIN
    IF EXISTS (
        SELECT 1 FROM unnest(ARRAY[
            'clinic_procedures', 'consultation_procedures',
            'financial_payment_records', 'financial_payment_allocations',
            'financial_charge_adjustments'
        ]) AS target(table_name)
        WHERE NOT (SELECT relrowsecurity FROM pg_class
                   WHERE oid = ('public.' || target.table_name)::regclass)
    ) THEN RAISE EXCEPTION 'VERIFICATION FAILED: financial RLS is not enabled'; END IF;

    IF EXISTS (
        SELECT 1 FROM unnest(ARRAY[
            'clinic_procedures', 'consultation_procedures',
            'financial_payment_records', 'financial_payment_allocations',
            'financial_charge_adjustments'
        ]) AS target(table_name)
        WHERE has_table_privilege('PUBLIC', 'public.' || target.table_name, 'SELECT,INSERT,UPDATE,DELETE')
           OR has_table_privilege('anon', 'public.' || target.table_name, 'SELECT,INSERT,UPDATE,DELETE')
           OR has_table_privilege('authenticated', 'public.' || target.table_name, 'SELECT,INSERT,UPDATE,DELETE')
    ) THEN RAISE EXCEPTION 'VERIFICATION FAILED: browser roles retain financial table privileges'; END IF;

    SELECT pg_get_functiondef('security.financial_actor()'::regprocedure) INTO v_definition;
    IF v_definition NOT LIKE '%supabase_user_id = auth.uid()%'
       OR v_definition NOT LIKE '%is_active = true%'
       OR v_definition NOT LIKE '%approved_at IS NOT NULL%'
       OR v_definition NOT LIKE '%role IN (''doctor'', ''admin'')%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: financial actor authorization differs';
    END IF;

    SELECT pg_get_functiondef('public.save_current_consultation_procedures(uuid,integer,jsonb)'::regprocedure) INTO v_definition;
    IF v_definition NOT LIKE '%FOR UPDATE%'
       OR v_definition NOT LIKE '%procedures_version <> p_version%'
       OR v_definition NOT LIKE '%financial_charge_adjustments%'
       OR v_definition NOT LIKE '%rebalance_financial_allocations%'
       OR v_definition NOT LIKE '%billing_version = billing_version + 1%'
       OR v_definition NOT LIKE '%procedures_version = procedures_version + 1%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: procedure mutation accounting differs';
    END IF;

    SELECT pg_get_functiondef('security.rebalance_financial_allocations(uuid,uuid,uuid)'::regprocedure) INTO v_definition;
    IF v_definition NOT LIKE '%DISTINCT ON (payment.payment_id)%'
       OR v_definition NOT LIKE '%revision_number + 1%'
       OR v_definition NOT LIKE '%Automatic allocation rebalance%'
       OR v_definition NOT LIKE '%financial_payment_allocations%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: allocation/revision behavior differs';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.triggers
                   WHERE event_object_table = 'financial_payment_records'
                     AND trigger_name = 'financial_payment_records_immutable')
       OR NOT EXISTS (SELECT 1 FROM information_schema.triggers
                   WHERE event_object_table = 'financial_payment_allocations'
                     AND trigger_name = 'financial_payment_allocations_immutable')
       OR NOT EXISTS (SELECT 1 FROM information_schema.triggers
                   WHERE event_object_table = 'financial_charge_adjustments'
                     AND trigger_name = 'financial_charge_adjustments_immutable') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: immutable ledger triggers are missing';
    END IF;

    IF EXISTS (
        SELECT 1 FROM unnest(ARRAY[
            'list_clinic_procedures(boolean)',
            'create_clinic_procedure(text,numeric)',
            'update_clinic_procedure(uuid,jsonb)',
            'get_current_consultation_procedures(uuid)',
            'save_current_consultation_procedures(uuid,integer,jsonb)',
            'list_financial_billing()',
            'get_patient_financial_history(uuid)',
            'get_patient_financial_outstanding(uuid)',
            'get_patient_financial_summaries()',
            'add_financial_payment(uuid,integer,numeric,timestamp with time zone)',
            'correct_financial_payment(uuid,integer,integer,numeric,timestamp with time zone,text)'
        ]) AS signature(value)
        WHERE has_function_privilege('PUBLIC', 'public.' || signature.value, 'EXECUTE')
           OR has_function_privilege('anon', 'public.' || signature.value, 'EXECUTE')
           OR NOT has_function_privilege('authenticated', 'public.' || signature.value, 'EXECUTE')
    ) THEN RAISE EXCEPTION 'VERIFICATION FAILED: financial RPC execution privileges differ'; END IF;
END
$verify$;
