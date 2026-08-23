-- Migration 035 preflight: remove medication licensing_status.
-- STRICTLY READ ONLY. Resolve every CONFLICT before running Migration 035.

WITH required_tables(name) AS (
  VALUES
    ('medication_import_batches'),('medication_import_rejections'),
    ('dental_medications'),('medication_clinical_presets'),
    ('doctor_medication_presets'),('prescriptions'),('prescription_items')
), required_functions(signature) AS (
  VALUES
    ('security.medication_prescription_actor()'),
    ('security.prescription_projection(uuid)'),
    ('security.prevent_approved_prescription_mutation()'),
    ('security.prevent_approved_prescription_item_mutation()'),
    ('public.search_dental_medications(text,integer)'),
    ('public.create_custom_medication(text,text,text,text,text,text,text)'),
    ('public.get_effective_medication_preset(uuid)'),
    ('public.upsert_doctor_medication_preset(uuid,text,text,text,text,text)'),
    ('public.delete_doctor_medication_preset(uuid)'),
    ('public.get_consultation_prescription(uuid)'),
    ('public.save_prescription_draft(uuid,integer,jsonb)'),
    ('public.approve_prescription(uuid,integer)'),
    ('public.get_patient_consultation_history(uuid)'),
    ('public.list_doctor_consultation_history()'),
    ('public.finish_appointment_by_patient(uuid,uuid)'),
    ('public.format_clinic_data()')
), affected_functions(signature) AS (
  VALUES
    ('security.prescription_projection(uuid)'),
    ('public.search_dental_medications(text,integer)'),
    ('public.create_custom_medication(text,text,text,text,text,text,text)'),
    ('public.get_effective_medication_preset(uuid)'),
    ('public.upsert_doctor_medication_preset(uuid,text,text,text,text,text)'),
    ('public.save_prescription_draft(uuid,integer,jsonb)')
), affected_function_definitions AS (
  SELECT affected.signature,
         to_regprocedure(affected.signature) AS function_oid,
         lower(coalesce(pg_get_functiondef(to_regprocedure(affected.signature)),'')) AS definition
    FROM affected_functions affected
), target_columns AS (
  SELECT class_record.oid AS table_oid,attribute.attnum,
         namespace.nspname AS schema_name,class_record.relname AS table_name,
         attribute.attname AS column_name
    FROM pg_class class_record
    JOIN pg_namespace namespace ON namespace.oid=class_record.relnamespace
    JOIN pg_attribute attribute ON attribute.attrelid=class_record.oid
   WHERE namespace.nspname='public'
     AND ((class_record.relname='dental_medications' AND attribute.attname='licensing_status')
       OR (class_record.relname='prescription_items'
           AND attribute.attname='licensing_status_snapshot'))
     AND attribute.attnum>0 AND NOT attribute.attisdropped
), unexpected_direct_dependencies AS (
  SELECT target.schema_name,target.table_name,target.column_name,
         pg_describe_object(dependency.classid,dependency.objid,dependency.objsubid) AS dependent_object
    FROM target_columns target
    JOIN pg_depend dependency ON dependency.refclassid='pg_class'::regclass
      AND dependency.refobjid=target.table_oid AND dependency.refobjsubid=target.attnum
   WHERE NOT (
       (dependency.classid='pg_attrdef'::regclass AND EXISTS(
         SELECT 1 FROM pg_attrdef attribute_default
          WHERE attribute_default.oid=dependency.objid
            AND attribute_default.adrelid=target.table_oid
            AND attribute_default.adnum=target.attnum))
       OR (dependency.classid='pg_constraint'::regclass AND EXISTS(
         SELECT 1 FROM pg_constraint constraint_record
          WHERE constraint_record.oid=dependency.objid
            AND constraint_record.conrelid=to_regclass('public.dental_medications')
            AND constraint_record.conname IN (
              'dental_medications_licensing_ck','dental_medications_authority_ck')))
       OR (dependency.classid='pg_class'::regclass AND EXISTS(
         SELECT 1 FROM pg_class index_record
          JOIN pg_namespace namespace ON namespace.oid=index_record.relnamespace
         WHERE index_record.oid=dependency.objid AND namespace.nspname='public'
           AND index_record.relname='dental_medications_visible_idx'))
       OR (dependency.classid='pg_proc'::regclass AND dependency.objid IN (
         SELECT to_regprocedure(signature) FROM affected_functions
          WHERE to_regprocedure(signature) IS NOT NULL))
     )
), licensing_constraints AS (
  SELECT namespace.nspname AS schema_name,class_record.relname AS table_name,
         constraint_record.conname AS object_name,
         pg_get_constraintdef(constraint_record.oid) AS definition
    FROM pg_constraint constraint_record
    JOIN pg_class class_record ON class_record.oid=constraint_record.conrelid
    JOIN pg_namespace namespace ON namespace.oid=class_record.relnamespace
   WHERE lower(pg_get_constraintdef(constraint_record.oid)) ~ 'licensing_status|licensingstatus'
), licensing_indexes AS (
  SELECT schemaname AS schema_name,tablename AS table_name,indexname AS object_name,indexdef AS definition
    FROM pg_indexes
   WHERE lower(indexdef) ~ 'licensing_status|licensingstatus'
), licensing_routines AS (
  SELECT procedure.oid AS function_oid,
         procedure.oid::regprocedure::text AS object_name,
         pg_get_functiondef(procedure.oid) AS definition
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid=procedure.pronamespace
   WHERE namespace.nspname NOT IN ('pg_catalog','information_schema')
     AND procedure.prokind IN ('f','p')
     AND lower(pg_get_functiondef(procedure.oid)) ~ 'licensing_status|licensingstatus'
), licensing_views AS (
  SELECT 'view'::text AS object_kind,schemaname AS schema_name,viewname AS object_name,definition
    FROM pg_views
   WHERE lower(definition) ~ 'licensing_status|licensingstatus'
  UNION ALL
  SELECT 'materialized_view',schemaname,matviewname,definition
    FROM pg_matviews
   WHERE lower(definition) ~ 'licensing_status|licensingstatus'
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
   WHERE lower(coalesce(qual,'')||' '||coalesce(with_check,'')) ~ 'licensing_status|licensingstatus'
), licensing_rules AS (
  SELECT schemaname AS schema_name,tablename AS table_name,rulename AS object_name,definition
    FROM pg_rules
   WHERE lower(definition) ~ 'licensing_status|licensingstatus'
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
  SELECT 10 AS ordinal,'prerequisite.table.'||required.name AS check_name,
         CASE WHEN to_regclass('public.'||required.name) IS NULL THEN 'CONFLICT' ELSE 'CLEAN' END AS status,
         coalesce(to_regclass('public.'||required.name)::text,'missing') AS detail
    FROM required_tables required

  UNION ALL
  SELECT 20,'prerequisite.column.dental_medications.licensing_status',
         CASE WHEN EXISTS(
           SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='dental_medications'
              AND column_name='licensing_status' AND data_type='text'
         ) THEN 'CLEAN' ELSE 'CONFLICT' END,
         'Migration 034 text column must exist before Migration 035 removes it'

  UNION ALL
  SELECT 21,'prerequisite.column.prescription_items.licensing_status_snapshot',
         CASE WHEN EXISTS(
           SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='prescription_items'
              AND column_name='licensing_status_snapshot' AND data_type='text'
         ) THEN 'CLEAN' ELSE 'CONFLICT' END,
         'Migration 034 text snapshot column must exist before Migration 035 removes it'

  UNION ALL
  SELECT 30,'prerequisite.function.'||required.signature,
         CASE WHEN to_regprocedure(required.signature) IS NULL THEN 'CONFLICT' ELSE 'CLEAN' END,
         coalesce(to_regprocedure(required.signature)::text,'missing')
    FROM required_functions required

  UNION ALL
  SELECT 40,'prerequisite.constraint.dental_medications_licensing_ck',
         CASE WHEN EXISTS(
           SELECT 1 FROM licensing_constraints dependency
            WHERE dependency.schema_name='public' AND dependency.table_name='dental_medications'
              AND dependency.object_name='dental_medications_licensing_ck'
         ) THEN 'CLEAN' ELSE 'CONFLICT' END,
         'Expected Migration 034 licensing check constraint'

  UNION ALL
  SELECT 41,'prerequisite.constraint.dental_medications_authority_ck',
         CASE WHEN EXISTS(
           SELECT 1 FROM licensing_constraints dependency
            WHERE dependency.schema_name='public' AND dependency.table_name='dental_medications'
              AND dependency.object_name='dental_medications_authority_ck'
         ) THEN 'CLEAN' ELSE 'CONFLICT' END,
         'Expected authority constraint must currently include licensing_status'

  UNION ALL
  SELECT 42,'prerequisite.index.dental_medications_visible_idx',
         CASE WHEN EXISTS(
           SELECT 1 FROM licensing_indexes dependency
            WHERE dependency.schema_name='public' AND dependency.table_name='dental_medications'
              AND dependency.object_name='dental_medications_visible_idx'
         ) THEN 'CLEAN' ELSE 'CONFLICT' END,
         'Expected visibility index must currently include licensing_status'

  UNION ALL
  SELECT 50,'dependency.expected_function.'||definition.signature,
         CASE WHEN definition.function_oid IS NULL THEN 'CONFLICT'
              WHEN definition.definition ~ 'licensing_status|licensingstatus' THEN 'CLEAN'
              ELSE 'CONFLICT' END,
         CASE WHEN definition.function_oid IS NULL THEN 'missing'
              WHEN definition.definition ~ 'licensing_status|licensingstatus'
                THEN 'Expected licensing dependency found'
              ELSE 'Expected Migration 034 licensing dependency is absent; inspect possible partial application or drift' END
    FROM affected_function_definitions definition

  UNION ALL
  SELECT 60,'dependency.unexpected_constraint',
         CASE WHEN count(*)=0 THEN 'CLEAN' ELSE 'CONFLICT' END,
         CASE WHEN count(*)=0 THEN 'No unexpected licensing constraints'
              ELSE string_agg(format('%I.%I.%I',schema_name,table_name,object_name),', ' ORDER BY schema_name,table_name,object_name) END
    FROM licensing_constraints
   WHERE NOT (schema_name='public' AND table_name='dental_medications'
          AND object_name IN ('dental_medications_licensing_ck','dental_medications_authority_ck'))

  UNION ALL
  SELECT 61,'dependency.unexpected_index',
         CASE WHEN count(*)=0 THEN 'CLEAN' ELSE 'CONFLICT' END,
         CASE WHEN count(*)=0 THEN 'No unexpected licensing indexes'
              ELSE string_agg(format('%I.%I',schema_name,object_name),', ' ORDER BY schema_name,object_name) END
    FROM licensing_indexes
   WHERE NOT (schema_name='public' AND table_name='dental_medications'
          AND object_name='dental_medications_visible_idx')

  UNION ALL
  SELECT 62,'dependency.unexpected_routine',
         CASE WHEN count(*)=0 THEN 'CLEAN' ELSE 'CONFLICT' END,
         CASE WHEN count(*)=0 THEN 'No unexpected licensing routines'
              ELSE string_agg(object_name,', ' ORDER BY object_name) END
    FROM licensing_routines
   WHERE function_oid NOT IN (
     SELECT to_regprocedure(signature) FROM affected_functions
      WHERE to_regprocedure(signature) IS NOT NULL
   )

  UNION ALL
  SELECT 63,'dependency.view_or_materialized_view',
         CASE WHEN count(*)=0 THEN 'CLEAN' ELSE 'CONFLICT' END,
         CASE WHEN count(*)=0 THEN 'No licensing views or materialized views'
              ELSE string_agg(format('%s %I.%I',object_kind,schema_name,object_name),', '
                   ORDER BY object_kind,schema_name,object_name) END
    FROM licensing_views

  UNION ALL
  SELECT 64,'dependency.trigger',
         CASE WHEN count(*)=0 THEN 'CLEAN' ELSE 'CONFLICT' END,
         CASE WHEN count(*)=0 THEN 'No trigger definition references licensing status'
              ELSE string_agg(format('%I.%I.%I',schema_name,table_name,object_name),', '
                   ORDER BY schema_name,table_name,object_name) END
    FROM licensing_triggers

  UNION ALL
  SELECT 65,'dependency.policy',
         CASE WHEN count(*)=0 THEN 'CLEAN' ELSE 'CONFLICT' END,
         CASE WHEN count(*)=0 THEN 'No policy expression references licensing status'
              ELSE string_agg(format('%I.%I.%I',schema_name,table_name,object_name),', '
                   ORDER BY schema_name,table_name,object_name) END
    FROM licensing_policies

  UNION ALL
  SELECT 66,'dependency.rule',
         CASE WHEN count(*)=0 THEN 'CLEAN' ELSE 'CONFLICT' END,
         CASE WHEN count(*)=0 THEN 'No rule definition references licensing status'
              ELSE string_agg(format('%I.%I.%I',schema_name,table_name,object_name),', '
                   ORDER BY schema_name,table_name,object_name) END
    FROM licensing_rules

  UNION ALL
  SELECT 67,'dependency.generated_or_default_expression',
         CASE WHEN count(*)=0 THEN 'CLEAN' ELSE 'CONFLICT' END,
         CASE WHEN count(*)=0 THEN 'No generated/default expression references licensing status'
              ELSE string_agg(format('%I.%I.%I',schema_name,table_name,object_name),', '
                   ORDER BY schema_name,table_name,object_name) END
    FROM licensing_attribute_expressions

  UNION ALL
  SELECT 68,'dependency.unexpected_direct_catalog_dependency',
         CASE WHEN count(*)=0 THEN 'CLEAN' ELSE 'CONFLICT' END,
         CASE WHEN count(*)=0 THEN 'No unidentified direct pg_depend entries for target columns'
              ELSE string_agg(format('%I.%I.%I -> %s',schema_name,table_name,column_name,
                     dependent_object),', ' ORDER BY schema_name,table_name,column_name,dependent_object) END
    FROM unexpected_direct_dependencies

  UNION ALL
  SELECT 70,'security.rls_foundation',
         CASE WHEN count(*)=7 AND bool_and(class_record.relrowsecurity) THEN 'CLEAN' ELSE 'CONFLICT' END,
         count(*)::text||' required tables found; RLS enabled='||coalesce(bool_and(class_record.relrowsecurity)::text,'false')
    FROM required_tables required
    JOIN pg_class class_record ON class_record.oid=to_regclass('public.'||required.name)

  UNION ALL
  SELECT 71,'security.no_direct_browser_table_access',
         CASE WHEN count(*) FILTER(WHERE
           coalesce(has_table_privilege('anon',to_regclass('public.'||required.name),'SELECT'),false)
           OR coalesce(has_table_privilege('anon',to_regclass('public.'||required.name),'INSERT'),false)
           OR coalesce(has_table_privilege('anon',to_regclass('public.'||required.name),'UPDATE'),false)
           OR coalesce(has_table_privilege('anon',to_regclass('public.'||required.name),'DELETE'),false)
           OR coalesce(has_table_privilege('authenticated',to_regclass('public.'||required.name),'SELECT'),false)
           OR coalesce(has_table_privilege('authenticated',to_regclass('public.'||required.name),'INSERT'),false)
           OR coalesce(has_table_privilege('authenticated',to_regclass('public.'||required.name),'UPDATE'),false)
           OR coalesce(has_table_privilege('authenticated',to_regclass('public.'||required.name),'DELETE'),false))=0
           THEN 'CLEAN' ELSE 'CONFLICT' END,
         'Medication/prescription tables must remain RPC-only'
    FROM required_tables required

  UNION ALL
  SELECT 80,'regression.format_clinic_data',
         CASE WHEN definition LIKE '%public.lab_products%'
                AND definition LIKE '%public.labs%'
                AND definition LIKE '%public.prescription_items%'
                AND definition LIKE '%public.prescriptions%'
                AND definition NOT LIKE '%public.users%'
              THEN 'CLEAN' ELSE 'CONFLICT' END,
         'Format must preserve Migration 032 Lab reset and Migration 034 prescription ordering'
    FROM (SELECT lower(coalesce(pg_get_functiondef(
      to_regprocedure('public.format_clinic_data()')),'')) AS definition) current_format

  UNION ALL
  SELECT 90,'dependency.inventory.constraints','INFO',
         coalesce(jsonb_agg(jsonb_build_object('schema',schema_name,'table',table_name,
           'name',object_name,'definition',definition) ORDER BY schema_name,table_name,object_name),'[]'::jsonb)::text
    FROM licensing_constraints

  UNION ALL
  SELECT 91,'dependency.inventory.indexes','INFO',
         coalesce(jsonb_agg(jsonb_build_object('schema',schema_name,'table',table_name,
           'name',object_name,'definition',definition) ORDER BY schema_name,table_name,object_name),'[]'::jsonb)::text
    FROM licensing_indexes

  UNION ALL
  SELECT 92,'dependency.inventory.routines','INFO',
         coalesce(jsonb_agg(jsonb_build_object('name',object_name,'definition',definition)
           ORDER BY object_name),'[]'::jsonb)::text
    FROM licensing_routines

  UNION ALL
  SELECT 93,'dependency.inventory.direct_catalog_dependencies','INFO',
         coalesce(jsonb_agg(jsonb_build_object('schema',schema_name,'table',table_name,
           'column',column_name,'dependentObject',dependent_object)
           ORDER BY schema_name,table_name,column_name,dependent_object),'[]'::jsonb)::text
    FROM unexpected_direct_dependencies
), summary AS (
  SELECT count(*) FILTER(WHERE status='CONFLICT') AS conflict_count,
         count(*) FILTER(WHERE status='CLEAN') AS clean_count,
         count(*) FILTER(WHERE status='INFO') AS info_count
    FROM base_diagnostics
), diagnostics AS (
  SELECT ordinal,check_name,status,detail FROM base_diagnostics
  UNION ALL
  SELECT 999,'migration_035.overall',
         CASE WHEN conflict_count=0 THEN 'CLEAN' ELSE 'CONFLICT' END,
         clean_count::text||' CLEAN, '||info_count::text||' INFO, '||conflict_count::text||' CONFLICT'
    FROM summary
)
SELECT check_name,status,detail
  FROM diagnostics
 ORDER BY ordinal,check_name;
