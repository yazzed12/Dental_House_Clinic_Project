-- Migration 035 verification. STRICTLY READ ONLY.

WITH required_tables(name) AS (
  VALUES
    ('medication_import_batches'),('medication_import_rejections'),
    ('dental_medications'),('medication_clinical_presets'),
    ('doctor_medication_presets'),('prescriptions'),('prescription_items')
), expected_security_definer_functions(signature,exposed_to_authenticated) AS (
  VALUES
    ('security.medication_prescription_actor()',false),
    ('security.prescription_projection(uuid)',false),
    ('public.search_dental_medications(text,integer)',true),
    ('public.create_custom_medication(text,text,text,text,text,text,text)',true),
    ('public.get_effective_medication_preset(uuid)',true),
    ('public.upsert_doctor_medication_preset(uuid,text,text,text,text,text)',true),
    ('public.delete_doctor_medication_preset(uuid)',true),
    ('public.get_consultation_prescription(uuid)',true),
    ('public.save_prescription_draft(uuid,integer,jsonb)',true),
    ('public.approve_prescription(uuid,integer)',true),
    ('public.get_patient_consultation_history(uuid)',true),
    ('public.list_doctor_consultation_history()',true),
    ('public.finish_appointment_by_patient(uuid,uuid)',true),
    ('public.format_clinic_data()',true)
), restricted_path_functions(signature) AS (
  SELECT signature FROM expected_security_definer_functions
  UNION ALL VALUES
    ('security.prevent_approved_prescription_mutation()'),
    ('security.prevent_approved_prescription_item_mutation()')
), affected_functions(signature) AS (
  VALUES
    ('security.prescription_projection(uuid)'),
    ('public.search_dental_medications(text,integer)'),
    ('public.create_custom_medication(text,text,text,text,text,text,text)'),
    ('public.get_effective_medication_preset(uuid)'),
    ('public.upsert_doctor_medication_preset(uuid,text,text,text,text,text)'),
    ('public.save_prescription_draft(uuid,integer,jsonb)')
), function_definitions AS (
  SELECT affected.signature,to_regprocedure(affected.signature) AS function_oid,
         lower(coalesce(pg_get_functiondef(to_regprocedure(affected.signature)),'')) AS definition,
         regexp_replace(lower(coalesce(pg_get_functiondef(to_regprocedure(affected.signature)),'')),
                        '[[:space:]]+','','g') AS normalized
    FROM affected_functions affected
), availability_functions(signature,definition,normalized) AS (
  SELECT definition.signature,definition.definition,definition.normalized
    FROM function_definitions definition
   WHERE definition.signature IN (
     'public.search_dental_medications(text,integer)',
     'public.get_effective_medication_preset(uuid)',
     'public.upsert_doctor_medication_preset(uuid,text,text,text,text,text)',
     'public.save_prescription_draft(uuid,integer,jsonb)')
), licensing_constraints AS (
  SELECT namespace.nspname AS schema_name,class_record.relname AS table_name,
         constraint_record.conname AS object_name,pg_get_constraintdef(constraint_record.oid) AS definition
    FROM pg_constraint constraint_record
    JOIN pg_class class_record ON class_record.oid=constraint_record.conrelid
    JOIN pg_namespace namespace ON namespace.oid=class_record.relnamespace
   WHERE lower(pg_get_constraintdef(constraint_record.oid)) ~ 'licensing_status|licensingstatus'
), licensing_indexes AS (
  SELECT schemaname AS schema_name,tablename AS table_name,indexname AS object_name,indexdef AS definition
    FROM pg_indexes
   WHERE lower(indexdef) ~ 'licensing_status|licensingstatus'
), licensing_routines AS (
  SELECT procedure.oid::regprocedure::text AS object_name,pg_get_functiondef(procedure.oid) AS definition
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid=procedure.pronamespace
   WHERE namespace.nspname NOT IN ('pg_catalog','information_schema')
     AND procedure.prokind IN ('f','p')
     AND lower(pg_get_functiondef(procedure.oid)) ~ 'licensing_status|licensingstatus'
), licensing_views AS (
  SELECT 'view'::text AS object_kind,schemaname AS schema_name,viewname AS object_name,definition
    FROM pg_views WHERE lower(definition) ~ 'licensing_status|licensingstatus'
  UNION ALL
  SELECT 'materialized_view',schemaname,matviewname,definition
    FROM pg_matviews WHERE lower(definition) ~ 'licensing_status|licensingstatus'
), licensing_triggers AS (
  SELECT namespace.nspname AS schema_name,class_record.relname AS table_name,
         trigger_record.tgname AS object_name,pg_get_triggerdef(trigger_record.oid) AS definition
    FROM pg_trigger trigger_record
    JOIN pg_class class_record ON class_record.oid=trigger_record.tgrelid
    JOIN pg_namespace namespace ON namespace.oid=class_record.relnamespace
   WHERE NOT trigger_record.tgisinternal
     AND lower(pg_get_triggerdef(trigger_record.oid)) ~ 'licensing_status|licensingstatus'
), licensing_policies AS (
  SELECT schemaname AS schema_name,tablename AS table_name,policyname AS object_name,
         coalesce(qual,'')||' '||coalesce(with_check,'') AS definition
    FROM pg_policies
   WHERE lower(coalesce(qual,'')||' '||coalesce(with_check,''))
         ~ 'licensing_status|licensingstatus'
), licensing_rules AS (
  SELECT schemaname AS schema_name,tablename AS table_name,rulename AS object_name,definition
    FROM pg_rules WHERE lower(definition) ~ 'licensing_status|licensingstatus'
), licensing_attribute_expressions AS (
  SELECT namespace.nspname AS schema_name,class_record.relname AS table_name,
         attribute.attname AS object_name,
         pg_get_expr(attribute_default.adbin,attribute_default.adrelid) AS definition
    FROM pg_attrdef attribute_default
    JOIN pg_class class_record ON class_record.oid=attribute_default.adrelid
    JOIN pg_namespace namespace ON namespace.oid=class_record.relnamespace
    JOIN pg_attribute attribute ON attribute.attrelid=attribute_default.adrelid
      AND attribute.attnum=attribute_default.adnum
   WHERE lower(pg_get_expr(attribute_default.adbin,attribute_default.adrelid))
         ~ 'licensing_status|licensingstatus'
), base_diagnostics AS (
  SELECT 10 AS ordinal,'schema.column.dental_medications.licensing_status' AS check_name,
         CASE WHEN EXISTS(
           SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='dental_medications'
              AND column_name='licensing_status') THEN 'FAIL' ELSE 'PASS' END AS status,
         'Column must be absent' AS detail

  UNION ALL
  SELECT 11,'schema.column.prescription_items.licensing_status_snapshot',
         CASE WHEN EXISTS(
           SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='prescription_items'
              AND column_name='licensing_status_snapshot') THEN 'FAIL' ELSE 'PASS' END,
         'Column must be absent'

  UNION ALL
  SELECT 20,'dependency.constraint',CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END,
         CASE WHEN count(*)=0 THEN 'No licensing constraint remains'
              ELSE string_agg(format('%I.%I.%I',schema_name,table_name,object_name),', '
                   ORDER BY schema_name,table_name,object_name) END
    FROM licensing_constraints

  UNION ALL
  SELECT 21,'dependency.index',CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END,
         CASE WHEN count(*)=0 THEN 'No licensing index remains'
              ELSE string_agg(format('%I.%I',schema_name,object_name),', '
                   ORDER BY schema_name,object_name) END
    FROM licensing_indexes

  UNION ALL
  SELECT 22,'dependency.routine',CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END,
         CASE WHEN count(*)=0 THEN 'No live non-system routine references licensing status'
              ELSE string_agg(object_name,', ' ORDER BY object_name) END
    FROM licensing_routines

  UNION ALL
  SELECT 23,'dependency.view_or_materialized_view',CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END,
         CASE WHEN count(*)=0 THEN 'No licensing view remains'
              ELSE string_agg(format('%s %I.%I',object_kind,schema_name,object_name),', '
                   ORDER BY object_kind,schema_name,object_name) END
    FROM licensing_views

  UNION ALL
  SELECT 24,'dependency.trigger',CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END,
         CASE WHEN count(*)=0 THEN 'No licensing trigger remains'
              ELSE string_agg(format('%I.%I.%I',schema_name,table_name,object_name),', '
                   ORDER BY schema_name,table_name,object_name) END
    FROM licensing_triggers

  UNION ALL
  SELECT 25,'dependency.policy',CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END,
         CASE WHEN count(*)=0 THEN 'No licensing policy remains'
              ELSE string_agg(format('%I.%I.%I',schema_name,table_name,object_name),', '
                   ORDER BY schema_name,table_name,object_name) END
    FROM licensing_policies

  UNION ALL
  SELECT 26,'dependency.rule',CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END,
         CASE WHEN count(*)=0 THEN 'No licensing rule remains'
              ELSE string_agg(format('%I.%I.%I',schema_name,table_name,object_name),', '
                   ORDER BY schema_name,table_name,object_name) END
    FROM licensing_rules

  UNION ALL
  SELECT 27,'dependency.generated_or_default_expression',
         CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END,
         CASE WHEN count(*)=0 THEN 'No licensing generated/default expression remains'
              ELSE string_agg(format('%I.%I.%I',schema_name,table_name,object_name),', '
                   ORDER BY schema_name,table_name,object_name) END
    FROM licensing_attribute_expressions

  UNION ALL
  SELECT 30,'function.exists.'||definition.signature,
         CASE WHEN definition.function_oid IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
         coalesce(definition.function_oid::regprocedure::text,'missing')
    FROM function_definitions definition

  UNION ALL
  SELECT 31,'function.no_licensing_projection_or_logic.'||definition.signature,
         CASE WHEN definition.function_oid IS NOT NULL
                   AND definition.definition !~ 'licensing_status|licensingstatus'
              THEN 'PASS' ELSE 'FAIL' END,
         'Function definition must contain neither SQL licensing identifiers nor licensingStatus JSON keys'
    FROM function_definitions definition

  UNION ALL
  SELECT 32,'availability.'||availability.signature,
         CASE WHEN availability.normalized LIKE '%medication.is_active%'
                   OR availability.normalized LIKE '%v_medication.is_active%'
              THEN CASE WHEN availability.normalized LIKE
                   '%catalog_scope=''clinic''and%verification_status=''unverified''%'
                     AND availability.normalized LIKE
                   '%catalog_scope=''global''and%verification_status=''verified''%'
                     AND availability.definition !~ 'licensing_status|licensingstatus'
                   THEN 'PASS' ELSE 'FAIL' END
              ELSE 'FAIL' END,
         'Required visibility: active clinic+unverified OR active global+verified'
    FROM availability_functions availability

  UNION ALL
  SELECT 33,'function.create_custom_medication.provenance',
         CASE WHEN normalized LIKE '%''clinic_custom''%'
                   AND normalized LIKE '%''unverified''%'
                   AND normalized LIKE '%created_by%'
                   AND definition !~ 'licensing_status|licensingstatus'
              THEN 'PASS' ELSE 'FAIL' END,
         'Clinic custom creation must retain author, source, and unverified status without licensing'
    FROM function_definitions
   WHERE signature='public.create_custom_medication(text,text,text,text,text,text,text)'

  UNION ALL
  SELECT 40,'index.dental_medications_visible_idx',
         CASE WHEN count(*)=1
                   AND bool_and(lower(indexdef) LIKE '%catalog_scope%')
                   AND bool_and(lower(indexdef) LIKE '%verification_status%')
                   AND bool_and(lower(indexdef) LIKE '%lower(brand_name)%')
                   AND bool_and(lower(indexdef) LIKE '% where is_active%')
                   AND bool_and(lower(indexdef) NOT LIKE '%licensing%')
              THEN 'PASS' ELSE 'FAIL' END,
         coalesce(max(indexdef),'missing')
    FROM pg_indexes
   WHERE schemaname='public' AND tablename='dental_medications'
     AND indexname='dental_medications_visible_idx'

  UNION ALL
  SELECT 41,'constraint.dental_medications_authority_ck',
         CASE WHEN count(*)=1
                   AND bool_and(definition LIKE '%catalog_scope%')
                   AND bool_and(definition LIKE '%created_by%')
                   AND bool_and(definition LIKE '%clinic_custom%')
                   AND bool_and(definition LIKE '%verification_status%')
                   AND bool_and(definition LIKE '%unverified%')
                   AND bool_and(definition LIKE '%source_record_id%')
                   AND bool_and(definition LIKE '%imported_at%')
                   AND bool_and(definition LIKE '%import_batch_id%')
                   AND bool_and(definition NOT LIKE '%licensing%')
              THEN 'PASS' ELSE 'FAIL' END,
         coalesce(max(definition),'missing')
    FROM (
      SELECT lower(pg_get_constraintdef(constraint_record.oid)) AS definition
        FROM pg_constraint constraint_record
       WHERE constraint_record.conrelid=to_regclass('public.dental_medications')
         AND constraint_record.conname='dental_medications_authority_ck'
    ) authority

  UNION ALL
  SELECT 42,'constraint.dental_medications_verification_ck',
         CASE WHEN count(*)=1
                   AND bool_and(definition LIKE '%pending%')
                   AND bool_and(definition LIKE '%verified%')
                   AND bool_and(definition LIKE '%unverified%')
                   AND bool_and(definition LIKE '%deprecated%')
              THEN 'PASS' ELSE 'FAIL' END,
         coalesce(max(definition),'missing')
    FROM (
      SELECT lower(pg_get_constraintdef(constraint_record.oid)) AS definition
        FROM pg_constraint constraint_record
       WHERE constraint_record.conrelid=to_regclass('public.dental_medications')
         AND constraint_record.conname='dental_medications_verification_ck'
    ) verification

  UNION ALL
  SELECT 50,'security.rls_foundation',
         CASE WHEN count(*)=7 AND bool_and(class_record.relrowsecurity) THEN 'PASS' ELSE 'FAIL' END,
         count(*)::text||' required tables found; RLS enabled='||
           coalesce(bool_and(class_record.relrowsecurity)::text,'false')
    FROM required_tables required
    JOIN pg_class class_record ON class_record.oid=to_regclass('public.'||required.name)

  UNION ALL
  SELECT 51,'security.no_direct_browser_table_access',
         CASE WHEN count(*) FILTER(WHERE
           coalesce(has_table_privilege('anon',to_regclass('public.'||required.name),'SELECT'),false)
           OR coalesce(has_table_privilege('anon',to_regclass('public.'||required.name),'INSERT'),false)
           OR coalesce(has_table_privilege('anon',to_regclass('public.'||required.name),'UPDATE'),false)
           OR coalesce(has_table_privilege('anon',to_regclass('public.'||required.name),'DELETE'),false)
           OR coalesce(has_table_privilege('authenticated',to_regclass('public.'||required.name),'SELECT'),false)
           OR coalesce(has_table_privilege('authenticated',to_regclass('public.'||required.name),'INSERT'),false)
           OR coalesce(has_table_privilege('authenticated',to_regclass('public.'||required.name),'UPDATE'),false)
           OR coalesce(has_table_privilege('authenticated',to_regclass('public.'||required.name),'DELETE'),false))=0
              THEN 'PASS' ELSE 'FAIL' END,
         'anon/authenticated must have no direct medication/prescription table DML privileges'
    FROM required_tables required

  UNION ALL
  SELECT 52,'security.security_definer.'||expected.signature,
         CASE WHEN procedure.oid IS NOT NULL AND procedure.prosecdef THEN 'PASS' ELSE 'FAIL' END,
         CASE WHEN procedure.oid IS NULL THEN 'missing' ELSE 'SECURITY DEFINER='||procedure.prosecdef::text END
    FROM expected_security_definer_functions expected
    LEFT JOIN pg_proc procedure ON procedure.oid=to_regprocedure(expected.signature)

  UNION ALL
  SELECT 53,'security.restricted_search_path.'||expected.signature,
         CASE WHEN procedure.oid IS NOT NULL
                   AND coalesce(procedure.proconfig,'{}'::text[])
                       @> ARRAY['search_path=pg_catalog, pg_temp']
              THEN 'PASS' ELSE 'FAIL' END,
         coalesce(array_to_string(procedure.proconfig,', '),'missing')
    FROM restricted_path_functions expected
    LEFT JOIN pg_proc procedure ON procedure.oid=to_regprocedure(expected.signature)

  UNION ALL
  SELECT 54,'security.rpc_acl.'||expected.signature,
         CASE WHEN procedure.oid IS NOT NULL
                   AND NOT EXISTS(
                     SELECT 1
                       FROM aclexplode(coalesce(procedure.proacl,
                         acldefault('f',procedure.proowner))) acl
                      WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')
                   AND NOT has_function_privilege('anon',procedure.oid,'EXECUTE')
                   AND (NOT expected.exposed_to_authenticated
                        OR has_function_privilege('authenticated',procedure.oid,'EXECUTE'))
                   AND (expected.exposed_to_authenticated
                        OR NOT has_function_privilege('authenticated',procedure.oid,'EXECUTE'))
              THEN 'PASS' ELSE 'FAIL' END,
         CASE WHEN expected.exposed_to_authenticated
              THEN 'authenticated-only RPC' ELSE 'internal function' END
    FROM expected_security_definer_functions expected
    LEFT JOIN pg_proc procedure ON procedure.oid=to_regprocedure(expected.signature)

  UNION ALL
  SELECT 60,'regression.prescription_draft_doctor_ownership_version_appointment',
         CASE WHEN definition LIKE '%v_actor_role<>''doctor''%'
                   AND definition LIKE '%v_consultation.doctor_id<>v_actor_id%'
                   AND definition LIKE '%p_expected_version%'
                   AND definition LIKE '%appointment.status::text in (''pending'',''confirmed'')%'
              THEN 'PASS' ELSE 'FAIL' END,
         'Draft must remain doctor-only, consultation-owned, versioned, and active-appointment-bound'
    FROM (SELECT lower(coalesce(pg_get_functiondef(
      to_regprocedure('public.save_prescription_draft(uuid,integer,jsonb)')),'')) definition) draft

  UNION ALL
  SELECT 61,'regression.prescription_approval_doctor_ownership_version',
         CASE WHEN definition LIKE '%v_actor_role<>''doctor''%'
                   AND definition LIKE '%v_prescription.doctor_id<>v_actor_id%'
                   AND definition LIKE '%p_expected_version%'
                   AND definition LIKE '%set status=''approved''%'
              THEN 'PASS' ELSE 'FAIL' END,
         'Approval must remain doctor-only, owned, versioned, and status-changing'
    FROM (SELECT lower(coalesce(pg_get_functiondef(
      to_regprocedure('public.approve_prescription(uuid,integer)')),'')) definition) approval

  UNION ALL
  SELECT 62,'regression.approved_prescription_immutability',
         CASE WHEN count(*)=2
                   AND bool_and(lower(pg_get_triggerdef(trigger_record.oid)) LIKE '%before%')
                   AND bool_and(lower(pg_get_triggerdef(trigger_record.oid)) LIKE '%approved_immutability%')
                   AND pg_get_functiondef(to_regprocedure(
                     'security.prevent_approved_prescription_mutation()')) ILIKE '%OLD.status=''approved''%'
                   AND pg_get_functiondef(to_regprocedure(
                     'security.prevent_approved_prescription_item_mutation()')) ILIKE '%status=''approved''%'
              THEN 'PASS' ELSE 'FAIL' END,
         count(*)::text||' approved immutability triggers found'
    FROM pg_trigger trigger_record
   WHERE NOT trigger_record.tgisinternal
     AND ((trigger_record.tgrelid=to_regclass('public.prescriptions')
            AND trigger_record.tgname='prescriptions_approved_immutability')
       OR (trigger_record.tgrelid=to_regclass('public.prescription_items')
            AND trigger_record.tgname='prescription_items_approved_immutability'))

  UNION ALL
  SELECT 63,'regression.finish_prescription_review_barrier',
         CASE WHEN definition LIKE '%prescription_review_required%'
                   AND definition LIKE '%prescription.status=''draft''%'
              THEN 'PASS' ELSE 'FAIL' END,
         'Finishing an appointment must remain blocked by a draft prescription'
    FROM (SELECT lower(coalesce(pg_get_functiondef(
      to_regprocedure('public.finish_appointment_by_patient(uuid,uuid)')),'')) definition) finish

  UNION ALL
  SELECT 64,'regression.history_prescription_projection',
         CASE WHEN patient_definition LIKE '%security.prescription_projection%'
                   AND doctor_definition LIKE '%security.prescription_projection%'
                   AND patient_definition LIKE '%prescription.status=''approved''%'
                   AND doctor_definition LIKE '%prescription.status=''approved''%'
              THEN 'PASS' ELSE 'FAIL' END,
         'Patient and doctor history must retain approved prescription snapshot integration'
    FROM (SELECT
      lower(coalesce(pg_get_functiondef(to_regprocedure(
        'public.get_patient_consultation_history(uuid)')),'')) patient_definition,
      lower(coalesce(pg_get_functiondef(to_regprocedure(
        'public.list_doctor_consultation_history()')),'')) doctor_definition) history

  UNION ALL
  SELECT 65,'regression.doctor_preset_ownership',
         CASE WHEN upsert_definition LIKE '%v_actor_role<>''doctor''%'
                   AND upsert_definition LIKE '%values(v_actor_id,%'
                   AND delete_definition LIKE '%doctor_id=v_actor_id%'
                   AND effective_definition LIKE '%preset.doctor_id=v_actor_id%'
              THEN 'PASS' ELSE 'FAIL' END,
         'Preset write, delete, and effective lookup must remain scoped to the doctor'
    FROM (SELECT
      lower(coalesce(pg_get_functiondef(to_regprocedure(
        'public.upsert_doctor_medication_preset(uuid,text,text,text,text,text)')),'')) upsert_definition,
      lower(coalesce(pg_get_functiondef(to_regprocedure(
        'public.delete_doctor_medication_preset(uuid)')),'')) delete_definition,
      lower(coalesce(pg_get_functiondef(to_regprocedure(
        'public.get_effective_medication_preset(uuid)')),'')) effective_definition) preset_ownership

  UNION ALL
  SELECT 66,'regression.medication_import_provenance_foundation',
         CASE WHEN to_regclass('public.medication_import_batches') IS NOT NULL
                   AND to_regclass('public.medication_import_rejections') IS NOT NULL
                   AND count(*)=9
                   AND EXISTS(SELECT 1 FROM pg_constraint constraint_record
                     WHERE constraint_record.conrelid=to_regclass('public.dental_medications')
                       AND constraint_record.conname='dental_medications_import_batch_fk')
                   AND EXISTS(SELECT 1 FROM pg_indexes
                     WHERE schemaname='public' AND tablename='dental_medications'
                       AND indexname='dental_medications_global_source_identity_uq')
                   AND EXISTS(SELECT 1 FROM pg_indexes
                     WHERE schemaname='public' AND tablename='dental_medications'
                       AND indexname='dental_medications_global_source_record_uq')
              THEN 'PASS' ELSE 'FAIL' END,
         count(*)::text||' of 9 medication provenance columns found'
    FROM information_schema.columns
   WHERE table_schema='public' AND table_name='dental_medications'
     AND column_name IN ('source_type','source_name','source_reference','source_version',
       'source_record_id','verification_status','imported_at','last_verified_at','import_batch_id')

  UNION ALL
  SELECT 67,'regression.format_clinic_data_lab_and_prescription_ordering',
         CASE WHEN definition LIKE '%public.prescription_items%'
                   AND definition LIKE '%public.prescriptions%'
                   AND definition LIKE '%public.lab_products%'
                   AND definition LIKE '%public.labs%'
                   AND definition NOT LIKE '%public.users%'
              THEN 'PASS' ELSE 'FAIL' END,
         'Clinic format must retain prescription cleanup and Migration 032 lab catalog preservation'
    FROM (SELECT lower(coalesce(pg_get_functiondef(
      to_regprocedure('public.format_clinic_data()')),'')) definition) format_function

  UNION ALL
  SELECT 90,'inventory.medication_rows','INFO',
         count(*)::text||' medication rows (read only; no row values changed by verification)'
    FROM public.dental_medications

  UNION ALL
  SELECT 91,'inventory.prescription_items','INFO',
         count(*)::text||' prescription item rows'
    FROM public.prescription_items
), summary AS (
  SELECT count(*) FILTER(WHERE status='PASS') AS pass_count,
         count(*) FILTER(WHERE status='INFO') AS info_count,
         count(*) FILTER(WHERE status='FAIL') AS fail_count
    FROM base_diagnostics
), diagnostics AS (
  SELECT ordinal,check_name,status,detail FROM base_diagnostics
  UNION ALL
  SELECT 999,'migration_035.overall',
         CASE WHEN fail_count=0 THEN 'PASS' ELSE 'FAIL' END,
         pass_count::text||' PASS, '||info_count::text||' INFO, '||fail_count::text||' FAIL'
    FROM summary
)
SELECT check_name,status,detail
  FROM diagnostics
 ORDER BY ordinal,check_name;
