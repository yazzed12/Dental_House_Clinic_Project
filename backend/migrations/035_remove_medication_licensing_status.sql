-- Migration 035: remove medication licensing status from the live design.
-- Migration 034 must be fully applied before this transaction is run.

BEGIN;

DO $migration_guard$
DECLARE
  v_unexpected text;
BEGIN
  IF to_regclass('public.dental_medications') IS NULL
     OR to_regclass('public.prescription_items') IS NULL THEN
    RAISE EXCEPTION 'MIGRATION_035_PREREQUISITE_MISSING: required tables';
  END IF;

  IF NOT EXISTS(
       SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='dental_medications'
          AND column_name='licensing_status' AND data_type='text')
     OR NOT EXISTS(
       SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='prescription_items'
          AND column_name='licensing_status_snapshot' AND data_type='text') THEN
    RAISE EXCEPTION 'MIGRATION_035_PREREQUISITE_MISSING: licensing columns';
  END IF;

  IF to_regprocedure('security.prescription_projection(uuid)') IS NULL
     OR to_regprocedure('public.search_dental_medications(text,integer)') IS NULL
     OR to_regprocedure('public.create_custom_medication(text,text,text,text,text,text,text)') IS NULL
     OR to_regprocedure('public.get_effective_medication_preset(uuid)') IS NULL
     OR to_regprocedure('public.upsert_doctor_medication_preset(uuid,text,text,text,text,text)') IS NULL
     OR to_regprocedure('public.save_prescription_draft(uuid,integer,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'MIGRATION_035_PREREQUISITE_MISSING: affected functions';
  END IF;

  IF NOT EXISTS(
       SELECT 1 FROM pg_constraint constraint_record
        WHERE constraint_record.conrelid='public.dental_medications'::regclass
          AND constraint_record.conname='dental_medications_licensing_ck'
          AND lower(pg_get_constraintdef(constraint_record.oid)) LIKE '%licensing_status%')
     OR NOT EXISTS(
       SELECT 1 FROM pg_constraint constraint_record
        WHERE constraint_record.conrelid='public.dental_medications'::regclass
          AND constraint_record.conname='dental_medications_authority_ck'
          AND lower(pg_get_constraintdef(constraint_record.oid)) LIKE '%licensing_status%')
     OR NOT EXISTS(
       SELECT 1 FROM pg_indexes
        WHERE schemaname='public' AND tablename='dental_medications'
          AND indexname='dental_medications_visible_idx'
          AND lower(indexdef) LIKE '%licensing_status%') THEN
    RAISE EXCEPTION 'MIGRATION_035_PREREQUISITE_MISSING: expected constraint or index';
  END IF;

  SELECT string_agg(dependency.object_name,', ' ORDER BY dependency.object_name)
    INTO v_unexpected
    FROM (
      SELECT procedure.oid::regprocedure::text AS object_name
        FROM pg_proc procedure
        JOIN pg_namespace namespace ON namespace.oid=procedure.pronamespace
       WHERE namespace.nspname NOT IN ('pg_catalog','information_schema')
         AND procedure.prokind IN ('f','p')
         AND lower(pg_get_functiondef(procedure.oid)) ~ 'licensing_status|licensingstatus'
         AND procedure.oid NOT IN (
           'security.prescription_projection(uuid)'::regprocedure,
           'public.search_dental_medications(text,integer)'::regprocedure,
           'public.create_custom_medication(text,text,text,text,text,text,text)'::regprocedure,
           'public.get_effective_medication_preset(uuid)'::regprocedure,
           'public.upsert_doctor_medication_preset(uuid,text,text,text,text,text)'::regprocedure,
           'public.save_prescription_draft(uuid,integer,jsonb)'::regprocedure)
    ) dependency;
  IF v_unexpected IS NOT NULL THEN
    RAISE EXCEPTION 'MIGRATION_035_UNEXPECTED_ROUTINE_DEPENDENCY: %',v_unexpected;
  END IF;

  SELECT string_agg(format('%I.%I.%I',namespace.nspname,class_record.relname,
      constraint_record.conname),', ' ORDER BY namespace.nspname,class_record.relname,
      constraint_record.conname)
    INTO v_unexpected
    FROM pg_constraint constraint_record
    JOIN pg_class class_record ON class_record.oid=constraint_record.conrelid
    JOIN pg_namespace namespace ON namespace.oid=class_record.relnamespace
   WHERE lower(pg_get_constraintdef(constraint_record.oid)) ~ 'licensing_status|licensingstatus'
     AND NOT (namespace.nspname='public' AND class_record.relname='dental_medications'
       AND constraint_record.conname IN (
         'dental_medications_licensing_ck','dental_medications_authority_ck'));
  IF v_unexpected IS NOT NULL THEN
    RAISE EXCEPTION 'MIGRATION_035_UNEXPECTED_CONSTRAINT_DEPENDENCY: %',v_unexpected;
  END IF;

  SELECT string_agg(format('%I.%I',schemaname,indexname),', ' ORDER BY schemaname,indexname)
    INTO v_unexpected
    FROM pg_indexes
   WHERE lower(indexdef) ~ 'licensing_status|licensingstatus'
     AND NOT (schemaname='public' AND tablename='dental_medications'
       AND indexname='dental_medications_visible_idx');
  IF v_unexpected IS NOT NULL THEN
    RAISE EXCEPTION 'MIGRATION_035_UNEXPECTED_INDEX_DEPENDENCY: %',v_unexpected;
  END IF;

  SELECT string_agg(dependency.object_name,', ' ORDER BY dependency.object_name)
    INTO v_unexpected
    FROM (
      SELECT format('view %I.%I',schemaname,viewname) AS object_name
        FROM pg_views WHERE lower(definition) ~ 'licensing_status|licensingstatus'
      UNION ALL
      SELECT format('materialized view %I.%I',schemaname,matviewname)
        FROM pg_matviews WHERE lower(definition) ~ 'licensing_status|licensingstatus'
      UNION ALL
      SELECT format('trigger %I.%I.%I',namespace.nspname,class_record.relname,
                    trigger_record.tgname)
        FROM pg_trigger trigger_record
        JOIN pg_class class_record ON class_record.oid=trigger_record.tgrelid
        JOIN pg_namespace namespace ON namespace.oid=class_record.relnamespace
       WHERE NOT trigger_record.tgisinternal
         AND lower(pg_get_triggerdef(trigger_record.oid)) ~ 'licensing_status|licensingstatus'
      UNION ALL
      SELECT format('policy %I.%I.%I',schemaname,tablename,policyname)
        FROM pg_policies
       WHERE lower(coalesce(qual,'')||' '||coalesce(with_check,''))
             ~ 'licensing_status|licensingstatus'
      UNION ALL
      SELECT format('rule %I.%I.%I',schemaname,tablename,rulename)
        FROM pg_rules WHERE lower(definition) ~ 'licensing_status|licensingstatus'
      UNION ALL
      SELECT format('attribute expression %I.%I.%I',namespace.nspname,class_record.relname,
                    attribute.attname)
        FROM pg_attrdef attribute_default
        JOIN pg_class class_record ON class_record.oid=attribute_default.adrelid
        JOIN pg_namespace namespace ON namespace.oid=class_record.relnamespace
        JOIN pg_attribute attribute ON attribute.attrelid=attribute_default.adrelid
          AND attribute.attnum=attribute_default.adnum
       WHERE lower(pg_get_expr(attribute_default.adbin,attribute_default.adrelid))
             ~ 'licensing_status|licensingstatus'
    ) dependency;
  IF v_unexpected IS NOT NULL THEN
    RAISE EXCEPTION 'MIGRATION_035_UNEXPECTED_SCHEMA_DEPENDENCY: %',v_unexpected;
  END IF;
END
$migration_guard$;

CREATE OR REPLACE FUNCTION security.prescription_projection(p_prescription_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $function$
  SELECT jsonb_build_object(
    'id',prescription.id,'consultationId',prescription.consultation_id,
    'patientId',prescription.patient_id,'doctorId',prescription.doctor_id,
    'appointmentId',prescription.appointment_id,'status',prescription.status,
    'version',prescription.version,'approvedBy',prescription.approved_by,
    'approvedAt',prescription.approved_at,'createdAt',prescription.created_at,
    'updatedAt',prescription.updated_at,
    'items',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',item.id,'medicationId',item.medication_id,'clinicalPresetId',item.clinical_preset_id,
      'doctorPresetId',item.doctor_preset_id,'position',item.position,
      'brandName',item.brand_name_snapshot,'genericName',item.generic_name_snapshot,
      'strength',item.strength_snapshot,'dosageForm',item.dosage_form_snapshot,
      'route',item.route_snapshot,'dose',item.dose_snapshot,'frequency',item.frequency_snapshot,
      'duration',item.duration_snapshot,'instructions',item.instructions_snapshot,
      'doctorNotes',item.doctor_notes_snapshot,'sourceType',item.source_type_snapshot,
      'sourceName',item.source_name_snapshot,'sourceReference',item.source_reference_snapshot,
      'sourceVersion',item.source_version_snapshot,'sourceRecordId',item.source_record_id_snapshot,
      'verificationStatus',item.verification_status_snapshot
    ) ORDER BY item.position,item.id) FROM public.prescription_items item
      WHERE item.prescription_id=prescription.id),'[]'::jsonb))
  FROM public.prescriptions prescription WHERE prescription.id=p_prescription_id
$function$;

CREATE OR REPLACE FUNCTION public.save_prescription_draft(p_consultation_id uuid,p_expected_version integer,p_items jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text; v_consultation public.consultations%ROWTYPE;
  v_prescription public.prescriptions%ROWTYPE; v_item jsonb; v_medication public.dental_medications%ROWTYPE;
  v_medication_id uuid; v_clinical_preset_id uuid; v_doctor_preset_id uuid;
  v_position integer:=0; v_seen uuid[]:='{}'::uuid[];
BEGIN
  SELECT actor.id,actor.role INTO v_actor_id,v_actor_role
    FROM security.medication_prescription_actor() actor;
  IF v_actor_id IS NULL OR v_actor_role<>'doctor' THEN
    RAISE EXCEPTION 'PRESCRIPTION_AUTHORIZATION_DENIED' USING ERRCODE='42501';
  END IF;
  IF p_expected_version IS NULL OR p_expected_version<0 OR p_items IS NULL
     OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)>50 THEN
    RAISE EXCEPTION 'PRESCRIPTION_DRAFT_INVALID' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_consultation FROM public.consultations consultation
   WHERE consultation.id=p_consultation_id FOR UPDATE;
  IF v_consultation.id IS NULL THEN
    RAISE EXCEPTION 'PRESCRIPTION_CONSULTATION_NOT_FOUND' USING ERRCODE='P3402';
  END IF;
  IF v_consultation.doctor_id IS NULL OR v_consultation.doctor_id<>v_actor_id THEN
    RAISE EXCEPTION 'PRESCRIPTION_AUTHORIZATION_DENIED' USING ERRCODE='42501';
  END IF;
  IF v_consultation.appointment_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.appointments appointment WHERE appointment.id=v_consultation.appointment_id
      AND appointment.patient_id=v_consultation.patient_id
      AND appointment.doctor_id=v_consultation.doctor_id
      AND appointment.status::text IN ('pending','confirmed')) THEN
    RAISE EXCEPTION 'PRESCRIPTION_CONSULTATION_NOT_ACTIVE' USING ERRCODE='P3403';
  END IF;
  SELECT * INTO v_prescription FROM public.prescriptions prescription
   WHERE prescription.consultation_id=v_consultation.id FOR UPDATE;
  IF v_prescription.id IS NOT NULL AND v_prescription.status<>'draft' THEN
    RAISE EXCEPTION 'APPROVED_PRESCRIPTION_IMMUTABLE' USING ERRCODE='P3405';
  END IF;
  IF v_prescription.id IS NULL THEN
    IF p_expected_version<>0 THEN
      RAISE EXCEPTION 'PRESCRIPTION_VERSION_CONFLICT' USING ERRCODE='40001';
    END IF;
    IF jsonb_array_length(p_items)=0 THEN RETURN NULL; END IF;
    INSERT INTO public.prescriptions(consultation_id,patient_id,doctor_id,appointment_id,status,version)
    VALUES(v_consultation.id,v_consultation.patient_id,v_consultation.doctor_id,v_consultation.appointment_id,'draft',1)
    RETURNING * INTO v_prescription;
  ELSE
    IF p_expected_version<>v_prescription.version THEN
      RAISE EXCEPTION 'PRESCRIPTION_VERSION_CONFLICT' USING ERRCODE='40001';
    END IF;
    IF jsonb_array_length(p_items)=0 THEN
      DELETE FROM public.prescription_items WHERE prescription_id=v_prescription.id;
      DELETE FROM public.prescriptions WHERE id=v_prescription.id;
      RETURN NULL;
    END IF;
    UPDATE public.prescriptions SET version=version+1,updated_at=clock_timestamp()
     WHERE id=v_prescription.id RETURNING * INTO v_prescription;
    DELETE FROM public.prescription_items WHERE prescription_id=v_prescription.id;
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_position:=v_position+1;
    IF jsonb_typeof(v_item)<>'object'
      OR NOT (v_item ?& ARRAY['medicationId','brandName','genericName','strength','dosageForm','route',
        'dose','frequency','duration','instructions','doctorNotes','clinicalPresetId','doctorPresetId'])
      OR EXISTS(SELECT 1 FROM jsonb_object_keys(v_item) key(value) WHERE key.value<>ALL(ARRAY[
        'medicationId','brandName','genericName','strength','dosageForm','route','dose','frequency',
        'duration','instructions','doctorNotes','clinicalPresetId','doctorPresetId']))
      OR jsonb_typeof(v_item->'medicationId')<>'string'
      OR (v_item->>'medicationId') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR jsonb_typeof(v_item->'brandName')<>'string' OR btrim(v_item->>'brandName')=''
      OR jsonb_typeof(v_item->'strength')<>'string' OR btrim(v_item->>'strength')=''
      OR jsonb_typeof(v_item->'dosageForm')<>'string' OR btrim(v_item->>'dosageForm')=''
      OR jsonb_typeof(v_item->'route')<>'string' OR btrim(v_item->>'route')=''
      OR jsonb_typeof(v_item->'dose')<>'string' OR btrim(v_item->>'dose')=''
      OR jsonb_typeof(v_item->'frequency')<>'string' OR btrim(v_item->>'frequency')=''
      OR jsonb_typeof(v_item->'duration')<>'string' OR btrim(v_item->>'duration')=''
      OR char_length(v_item->>'brandName')>300 OR char_length(v_item->>'strength')>200
      OR char_length(v_item->>'dosageForm')>200 OR char_length(v_item->>'route')>200
      OR char_length(v_item->>'dose')>300 OR char_length(v_item->>'frequency')>300
      OR char_length(v_item->>'duration')>300
      OR (jsonb_typeof(v_item->'genericName') NOT IN ('string','null'))
      OR (jsonb_typeof(v_item->'instructions') NOT IN ('string','null'))
      OR (jsonb_typeof(v_item->'doctorNotes') NOT IN ('string','null'))
      OR (jsonb_typeof(v_item->'clinicalPresetId') NOT IN ('string','null'))
      OR (jsonb_typeof(v_item->'clinicalPresetId')='string'
        AND (v_item->>'clinicalPresetId') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      OR (jsonb_typeof(v_item->'doctorPresetId') NOT IN ('string','null'))
      OR (jsonb_typeof(v_item->'doctorPresetId')='string'
        AND (v_item->>'doctorPresetId') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      OR coalesce(char_length(v_item->>'genericName'),0)>500
      OR coalesce(char_length(v_item->>'instructions'),0)>4000
      OR coalesce(char_length(v_item->>'doctorNotes'),0)>4000 THEN
      RAISE EXCEPTION 'PRESCRIPTION_ITEM_INVALID' USING ERRCODE='22023';
    END IF;

    v_medication_id:=(v_item->>'medicationId')::uuid;
    IF v_medication_id=ANY(v_seen) THEN
      RAISE EXCEPTION 'PRESCRIPTION_ITEM_DUPLICATE' USING ERRCODE='22023';
    END IF;
    v_seen:=array_append(v_seen,v_medication_id);

    SELECT * INTO v_medication FROM public.dental_medications medication
     WHERE medication.id=v_medication_id FOR SHARE;
    IF v_medication.id IS NULL THEN
      RAISE EXCEPTION 'MEDICATION_NOT_AVAILABLE' USING ERRCODE='P3401';
    END IF;
    IF NOT v_medication.is_active OR NOT (
      (v_medication.catalog_scope='clinic' AND v_medication.verification_status='unverified')
      OR
      (v_medication.catalog_scope='global' AND v_medication.verification_status='verified')
    ) THEN
      RAISE EXCEPTION 'MEDICATION_NOT_AVAILABLE' USING ERRCODE='P3401';
    END IF;

    v_clinical_preset_id:=CASE
      WHEN jsonb_typeof(v_item->'clinicalPresetId')='string'
        THEN (v_item->>'clinicalPresetId')::uuid
      ELSE NULL
    END;
    v_doctor_preset_id:=CASE
      WHEN jsonb_typeof(v_item->'doctorPresetId')='string'
        THEN (v_item->>'doctorPresetId')::uuid
      ELSE NULL
    END;

    IF v_clinical_preset_id IS NOT NULL AND NOT EXISTS(
      SELECT 1
        FROM public.medication_clinical_presets preset
       WHERE preset.id=v_clinical_preset_id
         AND preset.medication_id=v_medication_id
         AND preset.is_active=true
         AND preset.review_status='approved'
    ) THEN
      RAISE EXCEPTION 'PRESCRIPTION_PRESET_MISMATCH' USING ERRCODE='22023';
    END IF;
    IF v_doctor_preset_id IS NOT NULL AND NOT EXISTS(
      SELECT 1 FROM public.doctor_medication_presets preset
       WHERE preset.id=v_doctor_preset_id
         AND preset.medication_id=v_medication_id
         AND preset.doctor_id=v_consultation.doctor_id
    ) THEN
      RAISE EXCEPTION 'PRESCRIPTION_PRESET_MISMATCH' USING ERRCODE='22023';
    END IF;

    INSERT INTO public.prescription_items(
      prescription_id,medication_id,clinical_preset_id,doctor_preset_id,position,
      brand_name_snapshot,generic_name_snapshot,strength_snapshot,dosage_form_snapshot,route_snapshot,
      dose_snapshot,frequency_snapshot,duration_snapshot,instructions_snapshot,doctor_notes_snapshot,
      source_type_snapshot,source_name_snapshot,source_reference_snapshot,source_version_snapshot,
      source_record_id_snapshot,verification_status_snapshot)
    VALUES(v_prescription.id,v_medication_id,v_clinical_preset_id,v_doctor_preset_id,v_position,
      btrim(v_item->>'brandName'),nullif(btrim(v_item->>'genericName'),''),btrim(v_item->>'strength'),
      btrim(v_item->>'dosageForm'),btrim(v_item->>'route'),btrim(v_item->>'dose'),
      btrim(v_item->>'frequency'),btrim(v_item->>'duration'),nullif(btrim(v_item->>'instructions'),''),
      nullif(btrim(v_item->>'doctorNotes'),''),v_medication.source_type,v_medication.source_name,
      v_medication.source_reference,v_medication.source_version,v_medication.source_record_id,
      v_medication.verification_status);
  END LOOP;

  RETURN security.prescription_projection(v_prescription.id);
END
$function$;

CREATE OR REPLACE FUNCTION public.search_dental_medications(p_query text,p_limit integer DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_actor_id uuid; v_query text:=lower(btrim(p_query)); v_limit integer; v_result jsonb;
BEGIN
  SELECT actor.id INTO v_actor_id FROM security.medication_prescription_actor() actor;
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'MEDICATION_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  IF v_query IS NULL OR v_query='' OR char_length(v_query)>200 THEN
    RAISE EXCEPTION 'MEDICATION_SEARCH_INVALID' USING ERRCODE='22023';
  END IF;
  v_limit:=least(greatest(coalesce(p_limit,20),1),50);
  SELECT coalesce(jsonb_agg(row.payload ORDER BY row.rank DESC,row.brand,row.strength,row.form,row.id),'[]'::jsonb)
    INTO v_result FROM (
      SELECT medication.id,lower(medication.brand_name) brand,lower(medication.strength) strength,
        lower(medication.dosage_form) form,
        ts_rank_cd(medication.search_document,plainto_tsquery('simple',v_query)) rank,
        jsonb_build_object(
          'id',medication.id,'brandName',medication.brand_name,'genericName',medication.generic_name,
          'strength',medication.strength,'dosageForm',medication.dosage_form,'route',medication.route,
          'category',medication.category,'manufacturer',medication.manufacturer,'market',medication.market,
          'catalogScope',medication.catalog_scope,'isCustom',medication.catalog_scope='clinic',
          'verificationStatus',medication.verification_status,
          'sourceType',medication.source_type,'sourceName',medication.source_name
        ) payload
      FROM public.dental_medications medication
      WHERE medication.is_active
        AND ((medication.catalog_scope='clinic' AND medication.verification_status='unverified')
          OR (medication.catalog_scope='global' AND medication.verification_status='verified'))
        AND (medication.search_document @@ plainto_tsquery('simple',v_query)
          OR lower(medication.brand_name) LIKE v_query||'%'
          OR lower(coalesce(medication.generic_name,'')) LIKE v_query||'%'
          OR lower(medication.strength) LIKE v_query||'%'
          OR lower(medication.dosage_form) LIKE v_query||'%'
          OR lower(coalesce(medication.category,'')) LIKE v_query||'%')
      ORDER BY rank DESC,brand,strength,form,medication.id LIMIT v_limit
    ) row;
  RETURN v_result;
END
$function$;

CREATE OR REPLACE FUNCTION public.create_custom_medication(
  p_brand_name text,p_generic_name text,p_strength text,p_dosage_form text,
  p_route text,p_category text,p_manufacturer text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text; v_identity text; v_medication public.dental_medications%ROWTYPE;
BEGIN
  SELECT actor.id,actor.role INTO v_actor_id,v_actor_role FROM security.medication_prescription_actor() actor;
  IF v_actor_id IS NULL OR v_actor_role NOT IN ('doctor','admin') THEN
    RAISE EXCEPTION 'MEDICATION_AUTHORIZATION_DENIED' USING ERRCODE='42501';
  END IF;
  IF p_brand_name IS NULL OR btrim(p_brand_name)='' OR char_length(btrim(p_brand_name))>300
    OR p_strength IS NULL OR btrim(p_strength)='' OR char_length(btrim(p_strength))>200
    OR p_dosage_form IS NULL OR btrim(p_dosage_form)='' OR char_length(btrim(p_dosage_form))>200
    OR p_route IS NULL OR btrim(p_route)='' OR char_length(btrim(p_route))>200
    OR (p_generic_name IS NOT NULL AND char_length(btrim(p_generic_name))>500)
    OR (p_category IS NOT NULL AND char_length(btrim(p_category))>300)
    OR (p_manufacturer IS NOT NULL AND char_length(btrim(p_manufacturer))>300) THEN
    RAISE EXCEPTION 'CUSTOM_MEDICATION_INVALID' USING ERRCODE='22023';
  END IF;
  v_identity:=lower(regexp_replace(btrim(p_brand_name)||'|'||coalesce(btrim(p_generic_name),'')||'|'||
    btrim(p_strength)||'|'||btrim(p_dosage_form)||'|'||btrim(p_route),'[[:space:]]+',' ','g'));
  PERFORM pg_advisory_xact_lock(hashtextextended('custom-medication:'||v_identity,0));
  SELECT * INTO v_medication FROM public.dental_medications medication
   WHERE medication.catalog_scope='clinic' AND medication.identity_key=v_identity LIMIT 1 FOR UPDATE;
  IF v_medication.id IS NULL THEN
    INSERT INTO public.dental_medications(
      catalog_scope,identity_key,brand_name,generic_name,strength,dosage_form,route,
      category,manufacturer,market,country,source_type,source_name,verification_status,
      is_active,created_by)
    VALUES('clinic',v_identity,btrim(p_brand_name),nullif(btrim(p_generic_name),''),btrim(p_strength),
      btrim(p_dosage_form),btrim(p_route),nullif(btrim(p_category),''),nullif(btrim(p_manufacturer),''),
      'clinic','clinic','clinic_custom','Clinician-entered custom medication','unverified',true,v_actor_id)
    RETURNING * INTO v_medication;
  ELSIF NOT v_medication.is_active THEN
    UPDATE public.dental_medications SET is_active=true,updated_at=clock_timestamp()
     WHERE id=v_medication.id RETURNING * INTO v_medication;
  END IF;
  RETURN jsonb_build_object('id',v_medication.id,'brandName',v_medication.brand_name,
    'genericName',v_medication.generic_name,'strength',v_medication.strength,
    'dosageForm',v_medication.dosage_form,'route',v_medication.route,'category',v_medication.category,
    'manufacturer',v_medication.manufacturer,'market',v_medication.market,'catalogScope','clinic',
    'isCustom',true,'verificationStatus','unverified',
    'sourceType','clinic_custom','sourceName',v_medication.source_name);
END
$function$;

CREATE OR REPLACE FUNCTION public.get_effective_medication_preset(p_medication_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_actor_id uuid; v_medication public.dental_medications%ROWTYPE;
  v_standard public.medication_clinical_presets%ROWTYPE; v_doctor public.doctor_medication_presets%ROWTYPE;
BEGIN
  SELECT actor.id INTO v_actor_id FROM security.medication_prescription_actor() actor;
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'MEDICATION_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_medication FROM public.dental_medications medication
   WHERE medication.id=p_medication_id AND medication.is_active
     AND ((medication.catalog_scope='clinic' AND medication.verification_status='unverified')
       OR (medication.catalog_scope='global' AND medication.verification_status='verified'));
  IF v_medication.id IS NULL THEN RAISE EXCEPTION 'MEDICATION_NOT_AVAILABLE' USING ERRCODE='P3401'; END IF;
  SELECT * INTO v_standard FROM public.medication_clinical_presets preset
   WHERE preset.medication_id=v_medication.id AND preset.is_active AND preset.review_status='approved'
   ORDER BY preset.preset_version DESC,preset.reviewed_at DESC,preset.id LIMIT 1;
  SELECT * INTO v_doctor FROM public.doctor_medication_presets preset
   WHERE preset.medication_id=v_medication.id AND preset.doctor_id=v_actor_id;
  RETURN jsonb_build_object(
    'medication',jsonb_build_object('id',v_medication.id,'brandName',v_medication.brand_name,
      'genericName',v_medication.generic_name,'strength',v_medication.strength,
      'dosageForm',v_medication.dosage_form,'route',v_medication.route,'category',v_medication.category,
      'manufacturer',v_medication.manufacturer,'isCustom',v_medication.catalog_scope='clinic',
      'sourceType',v_medication.source_type,'sourceName',v_medication.source_name,
      'sourceReference',v_medication.source_reference,'sourceVersion',v_medication.source_version,
      'sourceRecordId',v_medication.source_record_id,'verificationStatus',v_medication.verification_status),
    'clinicalPreset',CASE WHEN v_standard.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id',v_standard.id,'dose',v_standard.default_dose,'frequency',v_standard.default_frequency,
      'duration',v_standard.default_duration,'instructions',v_standard.default_instructions,
      'clinicalContext',v_standard.clinical_context,'presetVersion',v_standard.preset_version) END,
    'doctorPreset',CASE WHEN v_doctor.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id',v_doctor.id,'dose',v_doctor.default_dose,'frequency',v_doctor.default_frequency,
      'duration',v_doctor.default_duration,'instructions',v_doctor.default_instructions,
      'doctorNotes',v_doctor.doctor_notes) END,
    'effectivePreset',jsonb_build_object(
      'dose',coalesce(v_doctor.default_dose,v_standard.default_dose),
      'frequency',coalesce(v_doctor.default_frequency,v_standard.default_frequency),
      'duration',coalesce(v_doctor.default_duration,v_standard.default_duration),
      'instructions',coalesce(v_doctor.default_instructions,v_standard.default_instructions),
      'doctorNotes',v_doctor.doctor_notes,
      'clinicalPresetId',v_standard.id,'doctorPresetId',v_doctor.id));
END
$function$;

CREATE OR REPLACE FUNCTION public.upsert_doctor_medication_preset(
  p_medication_id uuid,p_dose text,p_frequency text,p_duration text,p_instructions text,p_doctor_notes text
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text; v_preset public.doctor_medication_presets%ROWTYPE;
BEGIN
  SELECT actor.id,actor.role INTO v_actor_id,v_actor_role FROM security.medication_prescription_actor() actor;
  IF v_actor_id IS NULL OR v_actor_role<>'doctor' THEN RAISE EXCEPTION 'DOCTOR_PRESET_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.dental_medications medication
    WHERE medication.id=p_medication_id AND medication.is_active
      AND ((medication.catalog_scope='clinic' AND medication.verification_status='unverified')
        OR (medication.catalog_scope='global' AND medication.verification_status='verified')))
    OR (p_dose IS NOT NULL AND char_length(p_dose)>300)
    OR (p_frequency IS NOT NULL AND char_length(p_frequency)>300)
    OR (p_duration IS NOT NULL AND char_length(p_duration)>300)
    OR (p_instructions IS NOT NULL AND char_length(p_instructions)>4000)
    OR (p_doctor_notes IS NOT NULL AND char_length(p_doctor_notes)>4000) THEN
    RAISE EXCEPTION 'DOCTOR_PRESET_INVALID' USING ERRCODE='22023';
  END IF;
  INSERT INTO public.doctor_medication_presets(doctor_id,medication_id,default_dose,default_frequency,
    default_duration,default_instructions,doctor_notes)
  VALUES(v_actor_id,p_medication_id,nullif(btrim(p_dose),''),nullif(btrim(p_frequency),''),
    nullif(btrim(p_duration),''),nullif(btrim(p_instructions),''),nullif(btrim(p_doctor_notes),''))
  ON CONFLICT(doctor_id,medication_id) DO UPDATE SET
    default_dose=excluded.default_dose,default_frequency=excluded.default_frequency,
    default_duration=excluded.default_duration,default_instructions=excluded.default_instructions,
    doctor_notes=excluded.doctor_notes,updated_at=clock_timestamp()
  RETURNING * INTO v_preset;
  RETURN jsonb_build_object('id',v_preset.id,'medicationId',v_preset.medication_id,
    'dose',v_preset.default_dose,'frequency',v_preset.default_frequency,'duration',v_preset.default_duration,
    'instructions',v_preset.default_instructions,'doctorNotes',v_preset.doctor_notes);
END
$function$;

DROP INDEX public.dental_medications_visible_idx;

ALTER TABLE public.dental_medications
  DROP CONSTRAINT dental_medications_licensing_ck;
ALTER TABLE public.dental_medications
  DROP CONSTRAINT dental_medications_authority_ck;

ALTER TABLE public.dental_medications
  ADD CONSTRAINT dental_medications_authority_ck CHECK (
    (catalog_scope='clinic' AND created_by IS NOT NULL AND source_type='clinic_custom'
      AND verification_status='unverified'
      AND imported_at IS NULL AND import_batch_id IS NULL)
    OR
    (catalog_scope='global' AND source_type<>'clinic_custom' AND source_record_id IS NOT NULL
      AND imported_at IS NOT NULL AND import_batch_id IS NOT NULL));

CREATE INDEX dental_medications_visible_idx
  ON public.dental_medications(catalog_scope,verification_status,lower(brand_name),id)
  WHERE is_active;

ALTER TABLE public.prescription_items
  DROP COLUMN licensing_status_snapshot;
ALTER TABLE public.dental_medications
  DROP COLUMN licensing_status;

REVOKE ALL ON TABLE public.medication_import_batches,public.medication_import_rejections,
  public.dental_medications,public.medication_clinical_presets,public.doctor_medication_presets,
  public.prescriptions,public.prescription_items FROM PUBLIC,anon,authenticated;

REVOKE ALL ON FUNCTION security.prescription_projection(uuid) FROM PUBLIC,anon,authenticated;

REVOKE ALL ON FUNCTION public.search_dental_medications(text,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_custom_medication(text,text,text,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_effective_medication_preset(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.upsert_doctor_medication_preset(uuid,text,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.save_prescription_draft(uuid,integer,jsonb) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.search_dental_medications(text,integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_custom_medication(text,text,text,text,text,text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_effective_medication_preset(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.upsert_doctor_medication_preset(uuid,text,text,text,text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.save_prescription_draft(uuid,integer,jsonb) FROM anon;

GRANT EXECUTE ON FUNCTION public.search_dental_medications(text,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_custom_medication(text,text,text,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_effective_medication_preset(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_doctor_medication_preset(uuid,text,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_prescription_draft(uuid,integer,jsonb) TO authenticated;

COMMIT;
