-- READ-ONLY preflight for Migration 024: Lab Transactions.
-- One consolidated result set; this file never mutates schema or data.

WITH target_functions(signature) AS (
    VALUES
        ('public.list_lab_transactions(uuid,timestamp with time zone,timestamp with time zone)'),
        ('public.get_lab_transaction_summary(uuid,timestamp with time zone,timestamp with time zone)'),
        ('public.list_lab_payments(uuid,timestamp with time zone,timestamp with time zone)'),
        ('public.create_lab_payment(uuid,numeric,timestamp with time zone,text)'),
        ('public.correct_lab_payment(uuid,integer,numeric,timestamp with time zone,text,text)'),
        ('security.reject_lab_payment_mutation()')
), required_lab_columns(table_name,column_name) AS (
    VALUES
        ('labs','id'),('labs','is_active'),
        ('consultation_lab_items','consultation_id'),('consultation_lab_items','lab_id'),
        ('consultation_lab_items','lab_product_id'),('consultation_lab_items','lab_name_snapshot'),
        ('consultation_lab_items','product_name_snapshot'),('consultation_lab_items','unit_price_snapshot'),
        ('consultation_lab_items','quantity'),('consultation_lab_items','total_amount'),
        ('consultations','id'),('consultations','appointment_id'),('consultations','created_at'),
        ('appointments','id'),('appointments','date'),('appointments','appointment_date')
), checks AS (
    SELECT 10 AS ordering, 'migration_022.required_columns'::text AS check_name,
           CASE WHEN count(column_row.column_name)=count(*) THEN 'CLEAN' ELSE 'CONFLICT' END AS status,
           jsonb_build_object('required',count(*),'present',count(column_row.column_name),
             'missing',coalesce(jsonb_agg(required.table_name||'.'||required.column_name)
               FILTER (WHERE column_row.column_name IS NULL),'[]'::jsonb))::text AS details
      FROM required_lab_columns AS required
      LEFT JOIN information_schema.columns AS column_row
        ON column_row.table_schema='public' AND column_row.table_name=required.table_name
       AND column_row.column_name=required.column_name

    UNION ALL
    SELECT 20,'migration_023.history_rpc',
           CASE WHEN to_regprocedure('public.list_doctor_consultation_history()') IS NULL THEN 'CONFLICT' ELSE 'CLEAN' END,
           coalesce(to_regprocedure('public.list_doctor_consultation_history()')::text,'missing')

    UNION ALL
    SELECT 30,'transaction_date.source','CLEAN',
           'transactionDate = public.consultations.created_at (immutable consultation/service timestamp); filters are >= dateFrom and < dateTo'

    UNION ALL
    SELECT 40,'consultation_appointment.date_schema','INFO',
           coalesce((SELECT jsonb_agg(jsonb_build_object('table',table_name,'column',column_name,
                    'type',data_type,'nullable',is_nullable) ORDER BY table_name,ordinal_position)::text
             FROM information_schema.columns WHERE table_schema='public'
              AND ((table_name='consultations' AND column_name IN ('id','appointment_id','created_at'))
                OR (table_name='appointments' AND column_name IN ('id','date','appointment_date','time','appointment_time')))),'[]')

    UNION ALL
    SELECT 50,'lab_actor.helper',
           CASE WHEN to_regprocedure('security.lab_actor()') IS NULL THEN 'CONFLICT' ELSE 'CLEAN' END,
           coalesce(to_regprocedure('security.lab_actor()')::text,'missing')

    UNION ALL
    SELECT 60,'financial.payment_conventions','INFO',
           jsonb_build_object(
             'financial_payment_records',to_regclass('public.financial_payment_records'),
             'amount_type',(SELECT format_type(attribute.atttypid,attribute.atttypmod)
                 FROM pg_attribute AS attribute WHERE attribute.attrelid=to_regclass('public.financial_payment_records')
                   AND attribute.attname='amount' AND NOT attribute.attisdropped),
             'immutable_trigger',EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid=to_regclass('public.financial_payment_records')
                   AND tgname='financial_payment_records_immutable' AND NOT tgisinternal),
             'correction_rpc',to_regprocedure('public.correct_financial_payment(uuid,integer,integer,numeric,timestamp with time zone,text)')
           )::text

    UNION ALL
    SELECT 70,'target.table.lab_payments',
           CASE WHEN to_regclass('public.lab_payments') IS NULL THEN 'CLEAN' ELSE 'CONFLICT' END,
           coalesce(to_regclass('public.lab_payments')::text,'not present')

    UNION ALL
    SELECT 80,'target.function.'||target.signature,
           CASE WHEN to_regprocedure(target.signature) IS NULL THEN 'CLEAN' ELSE 'CONFLICT' END,
           coalesce(to_regprocedure(target.signature)::text,'not present')
      FROM target_functions AS target

    UNION ALL
    SELECT 90,'historical.item_counts','INFO',
           jsonb_build_object('items',(SELECT count(*) FROM public.consultation_lab_items),
             'represented_labs',(SELECT count(DISTINCT lab_id) FROM public.consultation_lab_items),
             'archived_lab_items',(SELECT count(*) FROM public.consultation_lab_items AS item
                 JOIN public.labs AS lab ON lab.id=item.lab_id WHERE NOT lab.is_active))::text

    UNION ALL
    SELECT 100,'historical.reference_integrity',
           CASE WHEN broken_consultations=0 AND broken_labs=0 THEN 'CLEAN' ELSE 'CONFLICT' END,
           jsonb_build_object('broken_consultations',broken_consultations,'broken_labs',broken_labs)::text
      FROM (SELECT
          count(*) FILTER (WHERE consultation.id IS NULL) AS broken_consultations,
          count(*) FILTER (WHERE lab.id IS NULL) AS broken_labs
        FROM public.consultation_lab_items AS item
        LEFT JOIN public.consultations AS consultation ON consultation.id=item.consultation_id
        LEFT JOIN public.labs AS lab ON lab.id=item.lab_id) AS integrity

    UNION ALL
    SELECT 110,'historical.snapshot_validity',
           CASE WHEN invalid_rows=0 THEN 'CLEAN' ELSE 'CONFLICT' END,
           jsonb_build_object('invalid_rows',invalid_rows)::text
      FROM (SELECT count(*) AS invalid_rows FROM public.consultation_lab_items
             WHERE btrim(lab_name_snapshot)='' OR btrim(product_name_snapshot)=''
                OR unit_price_snapshot<0 OR quantity NOT BETWEEN 1 AND 999
                OR total_amount<>(unit_price_snapshot*quantity)::numeric(15,2)) AS validity

    UNION ALL
    SELECT 120,'clinical_report.isolation','INFO',
           jsonb_build_object('lab_columns',coalesce((SELECT jsonb_agg(column_name ORDER BY column_name)
             FROM information_schema.columns WHERE table_schema='public' AND table_name='clinical_reports'
               AND lower(column_name) LIKE '%lab%'),'[]'::jsonb),
             'report_functions_referencing_lab_transactions',coalesce((SELECT jsonb_agg(proc.oid::regprocedure::text)
               FROM pg_proc AS proc JOIN pg_namespace AS namespace ON namespace.oid=proc.pronamespace
              WHERE namespace.nspname IN ('public','security')
                AND (proc.proname LIKE '%clinical_report%' OR proc.proname LIKE '%report%')
                AND (lower(pg_get_functiondef(proc.oid)) LIKE '%lab_payments%'
                  OR lower(pg_get_functiondef(proc.oid)) LIKE '%consultation_lab_items%')),'[]'::jsonb))::text

    UNION ALL
    SELECT 130,'target.acl_conflicts','INFO',
           coalesce((SELECT jsonb_agg(jsonb_build_object('signature',target.signature,'acl',proc.proacl)
                        ORDER BY target.signature)::text
             FROM target_functions AS target JOIN pg_proc AS proc ON proc.oid=to_regprocedure(target.signature)::oid),'[]')
), final_checks AS (
    SELECT * FROM checks
    UNION ALL
    SELECT 999,'preflight.summary',
           CASE WHEN EXISTS (SELECT 1 FROM checks WHERE status='CONFLICT') THEN 'CONFLICT' ELSE 'CLEAN' END,
           CASE WHEN EXISTS (SELECT 1 FROM checks WHERE status='CONFLICT')
                THEN 'CONFLICT: resolve reported assumptions before Migration 024.'
                ELSE 'CLEAN: Migration 024 assumptions match current schema.' END
)
SELECT check_name,status,details FROM final_checks ORDER BY ordering,check_name;
