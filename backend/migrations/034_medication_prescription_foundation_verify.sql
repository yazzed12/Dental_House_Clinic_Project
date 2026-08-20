-- Migration 034 verification.
-- READ ONLY: returns PASS / FAIL / INFO diagnostics.
-- This script must not mutate schema or data.

WITH required_tables(name) AS (
    VALUES
      ('dental_medications'),
      ('medication_clinical_presets'),
      ('doctor_medication_presets'),
      ('medication_import_batches'),
      ('medication_import_rejections'),
      ('prescriptions'),
      ('prescription_items')
),

required_foreign_keys(table_name,constraint_name) AS (
    VALUES
      ('medication_import_batches','medication_import_batches_imported_by_fk'),
      ('medication_import_rejections','medication_import_rejections_batch_fk'),
      ('dental_medications','dental_medications_created_by_fk'),
      ('dental_medications','dental_medications_import_batch_fk'),
      ('medication_clinical_presets','medication_clinical_presets_medication_fk'),
      ('medication_clinical_presets','medication_clinical_presets_reviewed_by_fk'),
      ('doctor_medication_presets','doctor_medication_presets_doctor_fk'),
      ('doctor_medication_presets','doctor_medication_presets_medication_fk'),
      ('prescriptions','prescriptions_consultation_fk'),
      ('prescriptions','prescriptions_patient_fk'),
      ('prescriptions','prescriptions_doctor_fk'),
      ('prescriptions','prescriptions_appointment_fk'),
      ('prescriptions','prescriptions_approved_by_fk'),
      ('prescription_items','prescription_items_prescription_fk'),
      ('prescription_items','prescription_items_medication_fk'),
      ('prescription_items','prescription_items_clinical_preset_fk'),
      ('prescription_items','prescription_items_doctor_preset_fk')
),

required_columns(table_name,column_name,data_type) AS (
    VALUES
      ('dental_medications','catalog_scope','text'),
      ('dental_medications','identity_key','text'),
      ('dental_medications','brand_name','text'),
      ('dental_medications','generic_name','text'),
      ('dental_medications','strength','text'),
      ('dental_medications','dosage_form','text'),
      ('dental_medications','route','text'),
      ('dental_medications','category','text'),
      ('dental_medications','manufacturer','text'),
      ('dental_medications','market','text'),
      ('dental_medications','source_type','text'),
      ('dental_medications','source_name','text'),
      ('dental_medications','source_reference','text'),
      ('dental_medications','source_version','text'),
      ('dental_medications','source_record_id','text'),
      ('dental_medications','verification_status','text'),
      ('dental_medications','licensing_status','text'),
      ('dental_medications','imported_at','timestamp with time zone'),
      ('dental_medications','last_verified_at','timestamp with time zone'),
      ('dental_medications','is_active','boolean'),
      ('dental_medications','created_by','uuid'),
      ('dental_medications','import_batch_id','uuid'),
      ('dental_medications','search_document','tsvector'),

      ('medication_clinical_presets','medication_id','uuid'),

      ('doctor_medication_presets','doctor_id','uuid'),
      ('doctor_medication_presets','medication_id','uuid'),

      ('medication_import_batches','source_name','text'),
      ('medication_import_batches','source_version','text'),
      ('medication_import_batches','source_reference','text'),
      ('medication_import_batches','market','text'),
      ('medication_import_batches','imported_by','uuid'),

      ('medication_import_rejections','batch_id','uuid'),
      ('medication_import_rejections','raw_payload','jsonb'),
      ('medication_import_rejections','reasons','jsonb'),

      ('prescriptions','consultation_id','uuid'),
      ('prescriptions','patient_id','uuid'),
      ('prescriptions','doctor_id','uuid'),
      ('prescriptions','appointment_id','uuid'),
      ('prescriptions','status','text'),
      ('prescriptions','version','integer'),
      ('prescriptions','approved_by','uuid'),
      ('prescriptions','approved_at','timestamp with time zone'),

      ('prescription_items','prescription_id','uuid'),
      ('prescription_items','medication_id','uuid'),
      ('prescription_items','brand_name_snapshot','text'),
      ('prescription_items','generic_name_snapshot','text'),
      ('prescription_items','strength_snapshot','text'),
      ('prescription_items','dosage_form_snapshot','text'),
      ('prescription_items','route_snapshot','text'),
      ('prescription_items','dose_snapshot','text'),
      ('prescription_items','frequency_snapshot','text'),
      ('prescription_items','duration_snapshot','text'),
      ('prescription_items','instructions_snapshot','text'),
      ('prescription_items','doctor_notes_snapshot','text'),
      ('prescription_items','source_type_snapshot','text'),
      ('prescription_items','source_name_snapshot','text'),
      ('prescription_items','source_reference_snapshot','text'),
      ('prescription_items','source_version_snapshot','text'),
      ('prescription_items','source_record_id_snapshot','text'),
      ('prescription_items','verification_status_snapshot','text'),
      ('prescription_items','licensing_status_snapshot','text'),
      ('prescription_items','position','integer')
),

required_functions(signature,requires_definer) AS (
    VALUES
      ('security.medication_prescription_actor()',true),
      ('security.prescription_projection(uuid)',true),
      ('security.prevent_approved_prescription_mutation()',false),
      ('security.prevent_approved_prescription_item_mutation()',false),
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
),

base_diagnostics AS (

    -- ---------------------------------------------------------
    -- TABLES
    -- ---------------------------------------------------------

    SELECT
      10 AS ordinal,
      'table.' || required.name AS check_name,
      CASE
        WHEN to_regclass('public.' || required.name) IS NULL
        THEN 'FAIL'
        ELSE 'PASS'
      END AS status,
      coalesce(
        to_regclass('public.' || required.name)::text,
        'missing'
      ) AS detail
    FROM required_tables required

    UNION ALL

    -- ---------------------------------------------------------
    -- COLUMNS
    -- ---------------------------------------------------------

    SELECT
      20,
      'column.' || required.table_name || '.' || required.column_name,
      CASE
        WHEN actual.column_name IS NULL
          OR actual.data_type <> required.data_type
        THEN 'FAIL'
        ELSE 'PASS'
      END,
      coalesce(actual.data_type,'missing')
        || '; expected '
        || required.data_type
    FROM required_columns required
    LEFT JOIN information_schema.columns actual
      ON actual.table_schema='public'
     AND actual.table_name=required.table_name
     AND actual.column_name=required.column_name

    UNION ALL

    -- ---------------------------------------------------------
    -- RLS
    -- ---------------------------------------------------------

    SELECT
      30,
      'rls.' || required.name,
      CASE
        WHEN class_record.relrowsecurity
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      'enabled=' || coalesce(
        class_record.relrowsecurity::text,
        'missing'
      )
    FROM required_tables required
    LEFT JOIN pg_class class_record
      ON class_record.oid =
         to_regclass('public.' || required.name)

    UNION ALL

    SELECT
      31,
      'rls.direct_policy_count.' || required.name,
      CASE
        WHEN count(policy.policyname)=0
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      count(policy.policyname)::text
        || ' policies; RPC-only tables expect zero direct browser policies'
    FROM required_tables required
    LEFT JOIN pg_policies policy
      ON policy.schemaname='public'
     AND policy.tablename=required.name
    GROUP BY required.name

    UNION ALL

    -- ---------------------------------------------------------
    -- DIRECT TABLE PRIVILEGES
    -- ---------------------------------------------------------

    SELECT
      32,
      'acl.no_direct_browser_table_access.' || required.name,
      CASE
        WHEN
          has_table_privilege(
            'anon',
            'public.' || required.name,
            'SELECT'
          )
          OR has_table_privilege(
            'anon',
            'public.' || required.name,
            'INSERT'
          )
          OR has_table_privilege(
            'anon',
            'public.' || required.name,
            'UPDATE'
          )
          OR has_table_privilege(
            'anon',
            'public.' || required.name,
            'DELETE'
          )
          OR has_table_privilege(
            'authenticated',
            'public.' || required.name,
            'SELECT'
          )
          OR has_table_privilege(
            'authenticated',
            'public.' || required.name,
            'INSERT'
          )
          OR has_table_privilege(
            'authenticated',
            'public.' || required.name,
            'UPDATE'
          )
          OR has_table_privilege(
            'authenticated',
            'public.' || required.name,
            'DELETE'
          )
        THEN 'FAIL'
        ELSE 'PASS'
      END,
      'all browser table access revoked; controlled SECURITY DEFINER RPCs are required'
    FROM required_tables required

    UNION ALL

    -- ---------------------------------------------------------
    -- FUNCTIONS + SECURITY DEFINER + SEARCH PATH
    -- ---------------------------------------------------------

    SELECT
      40,
      'function.' || required.signature,
      CASE
        WHEN proc.oid IS NULL THEN 'FAIL'
        WHEN required.requires_definer
          AND NOT proc.prosecdef THEN 'FAIL'
        WHEN NOT coalesce(
          proc.proconfig,
          '{}'::text[]
        ) @> ARRAY['search_path=pg_catalog, pg_temp']
          THEN 'FAIL'
        ELSE 'PASS'
      END,
      CASE
        WHEN proc.oid IS NULL
          THEN 'missing'
        ELSE
          'security_definer='
          || proc.prosecdef
          || '; config='
          || coalesce(proc.proconfig::text,'{}')
      END
    FROM required_functions required
    LEFT JOIN pg_proc proc
      ON proc.oid=to_regprocedure(required.signature)

    UNION ALL

    -- ---------------------------------------------------------
    -- FUNCTION ACL
    -- ---------------------------------------------------------

    SELECT
      50,
      'acl.no_anon_execute.' || required.signature,
      CASE
        WHEN to_regprocedure(required.signature) IS NULL
          THEN 'FAIL'
        WHEN has_function_privilege(
          'anon',
          required.signature,
          'EXECUTE'
        )
          THEN 'FAIL'
        ELSE 'PASS'
      END,
      'anon_execute=' ||
      CASE
        WHEN to_regprocedure(required.signature) IS NULL
          THEN 'unknown'
        ELSE has_function_privilege(
          'anon',
          required.signature,
          'EXECUTE'
        )::text
      END
    FROM required_functions required

    UNION ALL

    SELECT
      51,
      'acl.no_public_execute.' || required.signature,
      CASE
        WHEN to_regprocedure(required.signature) IS NULL
          THEN 'FAIL'
        WHEN EXISTS (
          SELECT 1
          FROM aclexplode(
            coalesce(
              proc.proacl,
              acldefault('f',proc.proowner)
            )
          ) acl
          WHERE acl.grantee=0
            AND acl.privilege_type='EXECUTE'
        )
          THEN 'FAIL'
        ELSE 'PASS'
      END,
      'PUBLIC execute must be absent'
    FROM required_functions required
    LEFT JOIN pg_proc proc
      ON proc.oid=to_regprocedure(required.signature)
    WHERE required.signature LIKE 'security.%'
       OR required.signature IN (
          'public.search_dental_medications(text,integer)',
          'public.create_custom_medication(text,text,text,text,text,text,text)',
          'public.get_effective_medication_preset(uuid)',
          'public.upsert_doctor_medication_preset(uuid,text,text,text,text,text)',
          'public.delete_doctor_medication_preset(uuid)',
          'public.get_consultation_prescription(uuid)',
          'public.save_prescription_draft(uuid,integer,jsonb)',
          'public.approve_prescription(uuid,integer)'
       )

    UNION ALL

    -- ---------------------------------------------------------
    -- SEARCH INDEX
    -- ---------------------------------------------------------

    SELECT
      60,
      'index.gin_medication_search',
      CASE
        WHEN EXISTS (
          SELECT 1
          FROM pg_indexes
          WHERE schemaname='public'
            AND tablename='dental_medications'
            AND indexname=
                'dental_medications_search_gin_idx'
            AND indexdef ILIKE
                '%USING gin%search_document%'
        )
          THEN 'PASS'
        ELSE 'FAIL'
      END,
      'required GIN search_document index'

    UNION ALL

    -- ---------------------------------------------------------
    -- IMPORT IDEMPOTENCY
    -- ---------------------------------------------------------

    SELECT
      61,
      'index.import_idempotency',
      CASE
        WHEN
          to_regclass(
            'public.dental_medications_global_source_identity_uq'
          ) IS NOT NULL
          AND
          to_regclass(
            'public.dental_medications_global_source_record_uq'
          ) IS NOT NULL
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      'source identity and source record uniqueness'

    UNION ALL

    -- ---------------------------------------------------------
    -- CONSTRAINTS
    -- ---------------------------------------------------------

    SELECT
      70,
      'constraints.snapshot_and_lifecycle',
      CASE
        WHEN count(*) FILTER (
          WHERE conname IN (
            'prescriptions_status_ck',
            'prescriptions_approval_state_ck',
            'prescriptions_consultation_uq',
            'prescription_items_required_snapshot_ck',
            'prescription_items_position_uq'
          )
        )=5
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      string_agg(
        conname,
        ', '
        ORDER BY conname
      )
    FROM pg_constraint
    WHERE conrelid IN (
      'public.prescriptions'::regclass,
      'public.prescription_items'::regclass
    )

    UNION ALL

    SELECT
      71,
      'constraints.catalog_authority',
      CASE
        WHEN EXISTS (
          SELECT 1
          FROM pg_constraint
          WHERE conrelid=
              'public.dental_medications'::regclass
            AND conname=
              'dental_medications_authority_ck'
        )
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      'custom rows cannot satisfy global/imported authority state'

    UNION ALL

    -- ---------------------------------------------------------
    -- FOREIGN KEYS
    -- ---------------------------------------------------------

    SELECT
      72,
      'foreign_key.'
        || required.table_name
        || '.'
        || required.constraint_name,
      CASE
        WHEN constraint_record.oid IS NULL
        THEN 'FAIL'
        ELSE 'PASS'
      END,
      coalesce(
        pg_get_constraintdef(
          constraint_record.oid
        ),
        'missing'
      )
    FROM required_foreign_keys required
    LEFT JOIN pg_constraint constraint_record
      ON constraint_record.conrelid=
         to_regclass(
           'public.' || required.table_name
         )
     AND constraint_record.conname=
         required.constraint_name
     AND constraint_record.contype='f'

    UNION ALL

    -- ---------------------------------------------------------
    -- TRIGGERS EXIST
    -- ---------------------------------------------------------

    SELECT
      80,
      'triggers.approved_immutability',
      CASE
        WHEN count(*)=2
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      string_agg(
        tgname,
        ', '
        ORDER BY tgname
      )
    FROM pg_trigger
    WHERE NOT tgisinternal
      AND tgname IN (
        'prescriptions_approved_immutability',
        'prescription_items_approved_immutability'
      )

    UNION ALL

    -- ---------------------------------------------------------
    -- APPROVED ITEM IMMUTABILITY MUST CHECK OLD AND NEW
    -- ---------------------------------------------------------

    SELECT
      81,
      'triggers.approved_item_old_new_protection',
      CASE
        WHEN
          lower(
            pg_get_functiondef(
              'security.prevent_approved_prescription_item_mutation()'
              ::regprocedure
            )
          ) LIKE '%old.prescription_id%'
          AND
          lower(
            pg_get_functiondef(
              'security.prevent_approved_prescription_item_mutation()'
              ::regprocedure
            )
          ) LIKE '%new.prescription_id%'
          AND
lower(
  pg_get_functiondef(
    'security.prevent_approved_prescription_item_mutation()'
    ::regprocedure
  )
) ~ 'status[[:space:]]*=[[:space:]]*''approved'''
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      'item mutation trigger must protect both OLD and NEW prescription relationships'

    UNION ALL

    -- ---------------------------------------------------------
    -- FINISH BARRIER
    -- ---------------------------------------------------------

    SELECT
      90,
      'function.finish_review_barrier',
      CASE
        WHEN lower(
          pg_get_functiondef(
            'public.finish_appointment_by_patient(uuid,uuid)'
            ::regprocedure
          )
        ) LIKE '%prescription_review_required%'
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      'draft prescription must block appointment completion'

    UNION ALL

    -- ---------------------------------------------------------
    -- HISTORY PRESCRIPTION SNAPSHOT
    -- ---------------------------------------------------------

    SELECT
      91,
      'function.history_snapshot_projection',
      CASE
        WHEN lower(
          pg_get_functiondef(
            'public.list_doctor_consultation_history()'
            ::regprocedure
          )
        ) LIKE '%security.prescription_projection%'
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      'history reads stored prescription snapshots'

    UNION ALL

    -- ---------------------------------------------------------
    -- HISTORY REGRESSION GUARDS
    -- ---------------------------------------------------------

    SELECT
      92,
      'function.history_regression_guards',
      CASE
        WHEN
          lower(
            pg_get_functiondef(
              'public.list_doctor_consultation_history()'
              ::regprocedure
            )
          ) LIKE '%consultation_lab_items%'
          AND
          lower(
            pg_get_functiondef(
              'public.list_doctor_consultation_history()'
              ::regprocedure
            )
          ) LIKE '%report_snapshot%'
          AND
          lower(
            pg_get_functiondef(
              'public.get_patient_consultation_history(uuid)'
              ::regprocedure
            )
          ) LIKE '%clinical_findings_snapshot%'
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      'pre-034 history lab/report/clinical findings projections remain present'

    UNION ALL

    -- ---------------------------------------------------------
    -- DOCTOR-ONLY DRAFT MUTATION
    -- ---------------------------------------------------------

    SELECT
      93,
      'ownership.prescription_draft_doctor_only',
      CASE
        WHEN
          lower(
            pg_get_functiondef(
              'public.save_prescription_draft(uuid,integer,jsonb)'
              ::regprocedure
            )
          ) ~
          'v_actor_role[[:space:]]*<>[[:space:]]*''doctor'''
          AND
          lower(
            pg_get_functiondef(
              'public.save_prescription_draft(uuid,integer,jsonb)'
              ::regprocedure
            )
          ) ~
          'v_consultation\.doctor_id[[:space:]]*<>[[:space:]]*v_actor_id'
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      'prescription draft mutation must require the authenticated owning doctor'

    UNION ALL

    -- ---------------------------------------------------------
    -- DOCTOR-ONLY APPROVAL
    -- ---------------------------------------------------------

    SELECT
      94,
      'ownership.prescription_approval_doctor_only',
      CASE
        WHEN
          lower(
            pg_get_functiondef(
              'public.approve_prescription(uuid,integer)'
              ::regprocedure
            )
          ) ~
          'v_actor_role[[:space:]]*<>[[:space:]]*''doctor'''
          AND
          lower(
            pg_get_functiondef(
              'public.approve_prescription(uuid,integer)'
              ::regprocedure
            )
          ) ~
          'v_prescription\.doctor_id[[:space:]]*<>[[:space:]]*v_actor_id'
          AND
          lower(
            pg_get_functiondef(
              'public.approve_prescription(uuid,integer)'
              ::regprocedure
            )
          ) ~
          'consultation\.doctor_id[[:space:]]*=[[:space:]]*v_actor_id'
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      'only the consultation-owning doctor may approve the prescription'

    UNION ALL

    -- ---------------------------------------------------------
    -- CLINICAL PRESET MUST BE ACTIVE + APPROVED
    -- ---------------------------------------------------------

    SELECT
      95,
      'prescription.clinical_preset_approved_active',
      CASE
        WHEN
          lower(
            pg_get_functiondef(
              'public.save_prescription_draft(uuid,integer,jsonb)'
              ::regprocedure
            )
          ) ~
          'preset\.is_active[[:space:]]*=[[:space:]]*true'
          AND
          lower(
            pg_get_functiondef(
              'public.save_prescription_draft(uuid,integer,jsonb)'
              ::regprocedure
            )
          ) ~
          'preset\.review_status[[:space:]]*=[[:space:]]*''approved'''
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      'clinicalPresetId must reference an active approved preset for the selected medication'

    UNION ALL

    -- ---------------------------------------------------------
    -- NO PG16-ONLY UUID VALIDATOR
    -- ---------------------------------------------------------

    SELECT
      96,
      'compatibility.no_pg_input_is_valid_dependency',
      CASE
        WHEN lower(
          pg_get_functiondef(
            'public.save_prescription_draft(uuid,integer,jsonb)'
            ::regprocedure
          )
        ) NOT LIKE '%pg_input_is_valid%'
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      'Migration 034 must not depend on pg_input_is_valid() for UUID validation'

    UNION ALL

    -- ---------------------------------------------------------
    -- FORMAT CLINIC PRESERVES MIGRATION 032 LAB RESET
    -- ---------------------------------------------------------

    SELECT
      97,
      'function.format_clinic_preserves_lab_catalog_reset',
      CASE
        WHEN
          lower(
            pg_get_functiondef(
              'public.format_clinic_data()'
              ::regprocedure
            )
          ) LIKE '%public.lab_products%'
          AND
          lower(
            pg_get_functiondef(
              'public.format_clinic_data()'
              ::regprocedure
            )
          ) LIKE '%public.labs%'
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      'format_clinic_data must preserve lab_products and labs reset behavior introduced before 034'

    UNION ALL

    -- ---------------------------------------------------------
    -- FORMAT CLINIC INCLUDES NEW PRESCRIPTION DEPENDENCIES
    -- ---------------------------------------------------------

    SELECT
      98,
      'function.format_clinic_prescription_compatibility',
      CASE
        WHEN
          lower(
            pg_get_functiondef(
              'public.format_clinic_data()'
              ::regprocedure
            )
          ) LIKE '%public.prescription_items%'
          AND
          lower(
            pg_get_functiondef(
              'public.format_clinic_data()'
              ::regprocedure
            )
          ) LIKE '%public.prescriptions%'
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      'format_clinic_data must clear prescription dependants before consultations/patients'

    UNION ALL

    -- ---------------------------------------------------------
    -- DOCTOR PRESET OWNERSHIP
    -- ---------------------------------------------------------

    SELECT
      99,
      'ownership.doctor_medication_preset',
      CASE
        WHEN
          lower(
            pg_get_functiondef(
              'public.upsert_doctor_medication_preset(uuid,text,text,text,text,text)'
              ::regprocedure
            )
          ) ~
          'values[[:space:]]*\([[:space:]]*v_actor_id[[:space:]]*,[[:space:]]*p_medication_id'
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      'doctor preset ownership is derived from the authenticated doctor actor'

    UNION ALL

    -- ---------------------------------------------------------
    -- TENANCY INFO
    -- ---------------------------------------------------------

    SELECT
      100,
      'tenancy.single_clinic_scope',
      'INFO',
      'Project has no clinic_id on current clinical ownership tables; clinic custom rows are isolated to this database tenant'

    UNION ALL

    -- ---------------------------------------------------------
    -- SEED DATA INFO
    -- ---------------------------------------------------------

    SELECT
      101,
      'catalog.seed_data',
      'INFO',
      count(*)::text
        || ' medication rows present; Migration 034 itself seeds zero rows'
    FROM public.dental_medications
),

summary AS (
    SELECT
      count(*) FILTER (
        WHERE status='FAIL'
      ) AS fail_count,
      count(*) FILTER (
        WHERE status='PASS'
      ) AS pass_count,
      count(*) FILTER (
        WHERE status='INFO'
      ) AS info_count
    FROM base_diagnostics
),

diagnostics AS (
    SELECT
      ordinal,
      check_name,
      status,
      detail
    FROM base_diagnostics

    UNION ALL

    SELECT
      999,
      'migration_034.overall',
      CASE
        WHEN fail_count=0
        THEN 'PASS'
        ELSE 'FAIL'
      END,
      CASE
        WHEN fail_count=0
        THEN
          pass_count::text
          || ' PASS, '
          || info_count::text
          || ' INFO, 0 FAIL'
        ELSE
          pass_count::text
          || ' PASS, '
          || info_count::text
          || ' INFO, '
          || fail_count::text
          || ' FAIL'
      END
    FROM summary
)

SELECT
  check_name,
  status,
  detail
FROM diagnostics
ORDER BY ordinal,check_name;