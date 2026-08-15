-- Read-only verifier for Migration 022. Run manually only after approval.
DO $verify$
DECLARE
    v_definition text;
    v_signature regprocedure;
    v_security_definer boolean;
    v_config text[];
BEGIN
    IF to_regclass('public.labs') IS NULL
       OR to_regclass('public.lab_products') IS NULL
       OR to_regclass('public.consultation_lab_items') IS NULL THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Lab tables missing';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='consultations'
                      AND column_name='lab_note' AND data_type='text' AND is_nullable='YES') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: consultations.lab_note differs';
    END IF;
    IF EXISTS (
        SELECT 1 FROM (VALUES
            ('lab_products','current_price',12,2),
            ('consultation_lab_items','unit_price_snapshot',12,2),
            ('consultation_lab_items','total_amount',15,2)
        ) AS expected(table_name,column_name,precision_value,scale_value)
        LEFT JOIN information_schema.columns AS column_row
          ON column_row.table_schema='public' AND column_row.table_name=expected.table_name
         AND column_row.column_name=expected.column_name
        WHERE column_row.data_type IS DISTINCT FROM 'numeric'
           OR column_row.numeric_precision IS DISTINCT FROM expected.precision_value
           OR column_row.numeric_scale IS DISTINCT FROM expected.scale_value
    ) THEN RAISE EXCEPTION 'VERIFICATION FAILED: Lab money types differ'; END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='consultation_lab_items'
                      AND column_name='total_amount' AND is_generated='ALWAYS'
                      AND generation_expression LIKE '%unit_price_snapshot%quantity%') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: generated total_amount missing';
    END IF;
    IF EXISTS (
        SELECT 1 FROM (VALUES ('labs'),('lab_products'),('consultation_lab_items')) AS target(table_name)
        WHERE NOT (SELECT relation.relrowsecurity FROM pg_class AS relation
                    WHERE relation.oid=('public.'||target.table_name)::regclass)
           OR has_table_privilege('anon','public.'||target.table_name,'SELECT,INSERT,UPDATE,DELETE')
           OR has_table_privilege('authenticated','public.'||target.table_name,'SELECT,INSERT,UPDATE,DELETE')
           OR EXISTS (
               SELECT 1 FROM pg_class AS relation
               CROSS JOIN LATERAL aclexplode(coalesce(relation.relacl,acldefault('r',relation.relowner))) AS acl_entry
                WHERE relation.oid=('public.'||target.table_name)::regclass
                  AND acl_entry.grantee=0
                  AND acl_entry.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')
           )
    ) THEN RAISE EXCEPTION 'VERIFICATION FAILED: Lab table containment differs'; END IF;
    IF EXISTS (
        SELECT 1 FROM (VALUES
            ('public.labs'::regclass,'labs_created_by_fk'),
            ('public.lab_products'::regclass,'lab_products_lab_fk'),
            ('public.consultation_lab_items'::regclass,'consultation_lab_items_consultation_fk'),
            ('public.consultation_lab_items'::regclass,'consultation_lab_items_patient_fk'),
            ('public.consultation_lab_items'::regclass,'consultation_lab_items_doctor_fk'),
            ('public.consultation_lab_items'::regclass,'consultation_lab_items_lab_fk'),
            ('public.consultation_lab_items'::regclass,'consultation_lab_items_product_fk')
        ) AS expected(table_oid,constraint_name)
        WHERE NOT EXISTS (SELECT 1 FROM pg_constraint
                           WHERE conrelid=expected.table_oid
                             AND conname=expected.constraint_name AND contype='f')
    ) OR NOT EXISTS (SELECT 1 FROM pg_constraint
                     WHERE conrelid='public.consultation_lab_items'::regclass
                       AND conname='consultation_lab_items_consultation_product_uq')
       OR NOT EXISTS (SELECT 1 FROM pg_constraint
                      WHERE conrelid='public.consultation_lab_items'::regclass
                        AND conname='consultation_lab_items_quantity_ck') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Lab constraints missing';
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name IN ('labs','lab_products')
           AND column_name='is_active'
           AND (data_type<>'boolean' OR is_nullable<>'NO' OR column_default NOT LIKE '%true%')
    ) OR (SELECT count(*) FROM information_schema.columns
           WHERE table_schema='public' AND table_name IN ('labs','lab_products')
             AND column_name='is_active')<>2 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: archive fields differ';
    END IF;
    SELECT regexp_replace(lower(pg_get_functiondef('security.lab_actor()'::regprocedure)),
                          '[[:space:]]+',' ','g') INTO v_definition;
    IF v_definition !~ 'supabase_user_id[[:space:]]*=[[:space:]]*auth\.uid\(\)'
       OR v_definition !~ 'is_active[[:space:]]*=[[:space:]]*true'
       OR v_definition !~ 'approved_at[[:space:]]+is[[:space:]]+not[[:space:]]+null'
       OR position('''doctor''' IN v_definition)=0
       OR position('''admin''' IN v_definition)=0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Lab actor authorization differs';
    END IF;
    SELECT regexp_replace(lower(pg_get_functiondef(
               'public.save_consultation_lab_items(uuid,jsonb,text,boolean)'::regprocedure)),
               '[[:space:]]+',' ','g') INTO v_definition;
    IF position('for update' IN v_definition)=0
       OR position('appointment.status::text' IN v_definition)=0
       OR position('''pending''' IN v_definition)=0
       OR position('''confirmed''' IN v_definition)=0
       OR position('product.current_price' IN v_definition)=0
       OR position('v_consultation.patient_id' IN v_definition)=0
       OR position('v_consultation.doctor_id' IN v_definition)=0
       OR v_definition !~ 'on[[:space:]]+conflict[[:space:]]*\([[:space:]]*consultation_id[[:space:]]*,[[:space:]]*lab_product_id[[:space:]]*\)[[:space:]]+do[[:space:]]+update'
       OR v_definition !~ 'set[[:space:]]+quantity[[:space:]]*=[[:space:]]*excluded\.quantity' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: authoritative Lab snapshot/save logic differs';
    END IF;
    FOREACH v_signature IN ARRAY ARRAY[
        'public.list_labs(boolean)'::regprocedure,
        'public.create_lab(text)'::regprocedure,
        'public.archive_lab(uuid)'::regprocedure,
        'public.list_lab_products(uuid,boolean)'::regprocedure,
        'public.create_lab_product(uuid,text,numeric)'::regprocedure,
        'public.update_lab_product_price(uuid,numeric)'::regprocedure,
        'public.archive_lab_product(uuid)'::regprocedure,
        'public.get_consultation_lab_items(uuid)'::regprocedure,
        'public.save_consultation_lab_items(uuid,jsonb,text,boolean)'::regprocedure
    ] LOOP
        SELECT proc.prosecdef,proc.proconfig
          INTO v_security_definer,v_config
          FROM pg_proc AS proc WHERE proc.oid=v_signature::oid;
        IF NOT v_security_definer
           OR NOT ('search_path=pg_catalog, pg_temp'=ANY(coalesce(v_config,ARRAY[]::text[])))
           OR has_function_privilege('anon',v_signature,'EXECUTE')
           OR NOT has_function_privilege('authenticated',v_signature,'EXECUTE')
           OR EXISTS (
               SELECT 1 FROM pg_proc AS proc
               CROSS JOIN LATERAL aclexplode(coalesce(proc.proacl,acldefault('f',proc.proowner))) AS acl_entry
                WHERE proc.oid=v_signature::oid AND acl_entry.grantee=0
                  AND acl_entry.privilege_type='EXECUTE'
           ) THEN RAISE EXCEPTION 'VERIFICATION FAILED: Lab RPC security differs for %',v_signature; END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='clinical_reports'
                  AND column_name LIKE '%lab%') THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Lab data leaked into clinical_reports';
    END IF;
    FOREACH v_signature IN ARRAY ARRAY[
        'public.finalize_clinical_report(uuid,jsonb,text,text)'::regprocedure,
        'public.get_patient_clinical_reports(uuid)'::regprocedure
    ] LOOP
        SELECT lower(pg_get_functiondef(v_signature)) INTO v_definition;
        IF position('consultation_lab_items' IN v_definition)>0
           OR position('lab_note' IN v_definition)>0 THEN
            RAISE EXCEPTION 'VERIFICATION FAILED: Lab data entered medical report function %',v_signature;
        END IF;
    END LOOP;
END
$verify$;

SELECT 'VERIFICATION SUCCESSFUL: Lab foundation is contained and medically isolated' AS result;
