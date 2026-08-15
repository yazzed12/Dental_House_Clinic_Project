-- Migration 023 preflight: read-only Consultation History Lab snapshot checks.
-- Run manually before the migration. This file does not mutate schema or data.
DO $preflight$
BEGIN
    IF to_regprocedure('public.list_doctor_consultation_history()') IS NULL THEN
        RAISE EXCEPTION 'PREFLIGHT BLOCKED: public history function is missing';
    END IF;
    IF to_regprocedure('security.list_doctor_consultation_history_base()') IS NULL THEN
        RAISE EXCEPTION 'PREFLIGHT BLOCKED: contained history base function is missing';
    END IF;
    IF to_regclass('public.consultations') IS NULL
       OR to_regclass('public.consultation_lab_items') IS NULL
       OR to_regclass('public.clinical_reports') IS NULL THEN
        RAISE EXCEPTION 'PREFLIGHT BLOCKED: required Migration 021/022 relations are missing';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='consultations'
           AND column_name='lab_note' AND data_type='text'
    ) THEN
        RAISE EXCEPTION 'PREFLIGHT BLOCKED: consultations.lab_note is missing or incompatible';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM (VALUES
              ('lab_name_snapshot','text'),
              ('product_name_snapshot','text'),
              ('unit_price_snapshot','numeric'),
              ('quantity','integer'),
              ('total_amount','numeric'),
              ('consultation_id','uuid'),
              ('lab_id','uuid'),
              ('lab_product_id','uuid'),
              ('created_at','timestamp with time zone')
          ) AS expected(column_name,data_type)
         WHERE NOT EXISTS (
             SELECT 1 FROM information_schema.columns AS actual
              WHERE actual.table_schema='public'
                AND actual.table_name='consultation_lab_items'
                AND actual.column_name=expected.column_name
                AND actual.data_type=expected.data_type
         )
    ) THEN
        RAISE EXCEPTION 'PREFLIGHT BLOCKED: required Lab snapshot columns are incomplete';
    END IF;
END
$preflight$;

WITH history_proc AS (
    SELECT proc.*
      FROM pg_proc AS proc
     WHERE proc.oid='public.list_doctor_consultation_history()'::regprocedure
), checks AS (
    SELECT 10 AS ordinal, 'history.functions'::text AS check_name, 'OK'::text AS status,
           jsonb_build_object(
               'publicHistory', to_regprocedure('public.list_doctor_consultation_history()'),
               'privateBase', to_regprocedure('security.list_doctor_consultation_history_base()')
           )::text AS details
    UNION ALL
    SELECT 20, 'history.current_definition', 'INFO',
           pg_get_functiondef('public.list_doctor_consultation_history()'::regprocedure)
    UNION ALL
    SELECT 30, 'history.security_posture',
           CASE WHEN proc.prosecdef
                  AND 'search_path=pg_catalog, pg_temp'=ANY(coalesce(proc.proconfig,ARRAY[]::text[]))
                  AND has_function_privilege('authenticated',proc.oid,'EXECUTE')
                  AND NOT has_function_privilege('anon',proc.oid,'EXECUTE')
                  AND NOT EXISTS (
                      SELECT 1
                        FROM aclexplode(coalesce(proc.proacl,acldefault('f',proc.proowner))) AS acl_entry
                       WHERE acl_entry.grantee=0 AND acl_entry.privilege_type='EXECUTE'
                  )
                THEN 'OK' ELSE 'CONFLICT' END,
           jsonb_build_object(
               'owner',pg_get_userbyid(proc.proowner),'securityDefiner',proc.prosecdef,
               'config',proc.proconfig,
               'authenticatedExecute',has_function_privilege('authenticated',proc.oid,'EXECUTE'),
               'anonExecute',has_function_privilege('anon',proc.oid,'EXECUTE'),
               'publicExecute',EXISTS (
                   SELECT 1
                     FROM aclexplode(coalesce(proc.proacl,acldefault('f',proc.proowner))) AS acl_entry
                    WHERE acl_entry.grantee=0 AND acl_entry.privilege_type='EXECUTE'
               )
           )::text
      FROM history_proc AS proc
    UNION ALL
    SELECT 40, 'schema.lab_snapshot_columns',
           CASE WHEN count(*)=9 THEN 'OK' ELSE 'CONFLICT' END,
           jsonb_agg(jsonb_build_object('column',column_name,'type',data_type)
                     ORDER BY ordinal_position)::text
      FROM information_schema.columns
     WHERE table_schema='public' AND table_name='consultation_lab_items'
       AND column_name IN ('consultation_id','lab_id','lab_product_id','lab_name_snapshot',
                           'product_name_snapshot','unit_price_snapshot','quantity',
                           'total_amount','created_at')
    UNION ALL
    SELECT 50, 'data.lab_counts', 'INFO',
           jsonb_build_object(
               'consultationsWithLabNote',(SELECT count(*) FROM public.consultations
                                            WHERE lab_note IS NOT NULL),
               'consultationLabItems',(SELECT count(*) FROM public.consultation_lab_items)
           )::text
    UNION ALL
    SELECT 60, 'data.lab_integrity',
           CASE WHEN count(*) FILTER (WHERE consultation.id IS NULL)=0
                  AND (SELECT count(*) FROM (
                      SELECT duplicate.consultation_id,duplicate.lab_product_id
                        FROM public.consultation_lab_items AS duplicate
                       GROUP BY duplicate.consultation_id,duplicate.lab_product_id
                      HAVING count(*)>1
                  ) AS duplicate_group)=0
                  AND count(*) FILTER (
                      WHERE item.lab_name_snapshot IS NULL OR btrim(item.lab_name_snapshot)=''
                         OR item.product_name_snapshot IS NULL OR btrim(item.product_name_snapshot)=''
                         OR item.quantity IS NULL OR item.quantity NOT BETWEEN 1 AND 999
                         OR item.unit_price_snapshot IS NULL OR item.unit_price_snapshot<0
                         OR item.total_amount IS NULL OR item.total_amount<0
                         OR item.total_amount IS DISTINCT FROM
                            (item.unit_price_snapshot*item.quantity)::numeric(15,2)
                  )=0
                THEN 'OK' ELSE 'CONFLICT' END,
           jsonb_build_object(
               'brokenConsultationReferences',count(*) FILTER (WHERE consultation.id IS NULL),
               'duplicateConsultationProducts',(SELECT count(*) FROM (
                   SELECT duplicate.consultation_id,duplicate.lab_product_id
                     FROM public.consultation_lab_items AS duplicate
                    GROUP BY duplicate.consultation_id,duplicate.lab_product_id
                   HAVING count(*)>1
               ) AS duplicate_group),
               'nullOrBlankSnapshots',count(*) FILTER (
                   WHERE item.lab_name_snapshot IS NULL OR btrim(item.lab_name_snapshot)=''
                      OR item.product_name_snapshot IS NULL OR btrim(item.product_name_snapshot)=''
               ),
               'invalidQuantities',count(*) FILTER (
                   WHERE item.quantity IS NULL OR item.quantity NOT BETWEEN 1 AND 999
               ),
               'invalidMoney',count(*) FILTER (
                   WHERE item.unit_price_snapshot IS NULL OR item.unit_price_snapshot<0
                      OR item.total_amount IS NULL OR item.total_amount<0
                      OR item.total_amount IS DISTINCT FROM
                         (item.unit_price_snapshot*item.quantity)::numeric(15,2)
               )
           )::text
      FROM public.consultation_lab_items AS item
      LEFT JOIN public.consultations AS consultation ON consultation.id=item.consultation_id
    UNION ALL
    SELECT 70, 'medical_report.schema_isolation',
           CASE WHEN count(*)=0 THEN 'OK' ELSE 'CONFLICT' END,
           jsonb_build_object('clinicalReportLabColumns',coalesce(jsonb_agg(column_name), '[]'::jsonb))::text
      FROM information_schema.columns
     WHERE table_schema='public' AND table_name='clinical_reports'
       AND lower(column_name) LIKE '%lab%'
    UNION ALL
    SELECT 80, 'medical_report.function_isolation',
           CASE WHEN count(*)=0 THEN 'OK' ELSE 'CONFLICT' END,
           jsonb_build_object('reportFunctionsReferencingLabObjects',
               coalesce(jsonb_agg(proc.oid::regprocedure::text ORDER BY proc.oid::regprocedure::text),'[]'::jsonb)
           )::text
      FROM pg_proc AS proc
      JOIN pg_namespace AS namespace ON namespace.oid=proc.pronamespace
     WHERE namespace.nspname IN ('public','security')
       AND (proc.proname LIKE '%clinical_report%' OR proc.proname LIKE '%report%')
       AND (lower(pg_get_functiondef(proc.oid)) LIKE '%consultation_lab_items%'
            OR lower(pg_get_functiondef(proc.oid)) LIKE '%lab_note%')
), summary AS (
    SELECT 999 AS ordinal, 'summary'::text AS check_name,
           CASE WHEN bool_or(status='CONFLICT') THEN 'CONFLICT' ELSE 'CLEAN' END AS status,
           CASE WHEN bool_or(status='CONFLICT')
                THEN 'PREFLIGHT CONFLICT: resolve reported conflicts before Migration 023'
                ELSE 'PREFLIGHT CLEAN: Migration 023 assumptions are satisfied' END AS details
      FROM checks
)
SELECT check_name,status,details FROM (
    SELECT * FROM checks UNION ALL SELECT * FROM summary
) AS output
ORDER BY ordinal;
