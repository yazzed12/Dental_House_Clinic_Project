-- Migration 034: production Medication + Prescription + controlled import foundation.
-- No medication or prescribing data is seeded. Runtime access is RPC-only.
BEGIN;

DO $precondition$
BEGIN
  IF to_regclass('public.users') IS NULL OR to_regclass('public.patients') IS NULL
     OR to_regclass('public.appointments') IS NULL OR to_regclass('public.consultations') IS NULL
     OR to_regprocedure('security.current_app_user_id()') IS NULL
     OR to_regprocedure('security.current_app_role()') IS NULL
     OR to_regprocedure('security.get_patient_consultation_history_base(uuid)') IS NULL
     OR to_regprocedure('security.list_doctor_consultation_history_base()') IS NULL
     OR to_regclass('public.consultation_lab_items') IS NULL
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
       WHERE table_schema='public' AND table_name='consultations' AND column_name='lab_note')
     OR to_regprocedure('public.get_patient_consultation_history(uuid)') IS NULL
     OR to_regprocedure('public.list_doctor_consultation_history()') IS NULL
     OR to_regprocedure('public.finish_appointment_by_patient(uuid,uuid)') IS NULL
     OR to_regprocedure('public.format_clinic_data()') IS NULL THEN
    RAISE EXCEPTION 'MEDICATION_PRESCRIPTION_REQUIRED_FOUNDATION_MISSING';
  END IF;
  IF to_regclass('public.dental_medications') IS NOT NULL
     OR to_regclass('public.medication_clinical_presets') IS NOT NULL
     OR to_regclass('public.doctor_medication_presets') IS NOT NULL
     OR to_regclass('public.medication_import_batches') IS NOT NULL
     OR to_regclass('public.medication_import_rejections') IS NOT NULL
     OR to_regclass('public.prescriptions') IS NOT NULL
     OR to_regclass('public.prescription_items') IS NOT NULL THEN
    RAISE EXCEPTION 'MEDICATION_PRESCRIPTION_TARGET_CONFLICT';
  END IF;
END
$precondition$;

CREATE TABLE public.medication_import_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_name text NOT NULL,
  source_version text NULL,
  source_reference text NULL,
  market text NOT NULL,
  input_format text NOT NULL,
  status text NOT NULL DEFAULT 'processing',
  total_rows integer NOT NULL DEFAULT 0,
  inserted_count integer NOT NULL DEFAULT 0,
  updated_count integer NOT NULL DEFAULT 0,
  unchanged_count integer NOT NULL DEFAULT 0,
  rejected_count integer NOT NULL DEFAULT 0,
  duplicate_count integer NOT NULL DEFAULT 0,
  imported_by uuid NOT NULL,
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at timestamptz NULL,
  CONSTRAINT medication_import_batches_imported_by_fk FOREIGN KEY (imported_by)
    REFERENCES public.users(id) ON DELETE RESTRICT,
  CONSTRAINT medication_import_batches_source_ck CHECK (btrim(source_name)<>'' AND char_length(btrim(source_name))<=300),
  CONSTRAINT medication_import_batches_market_ck CHECK (btrim(market)<>'' AND char_length(btrim(market))<=100),
  CONSTRAINT medication_import_batches_format_ck CHECK (input_format IN ('csv','json')),
  CONSTRAINT medication_import_batches_status_ck CHECK (status IN ('processing','previewed','completed','failed')),
  CONSTRAINT medication_import_batches_counts_ck CHECK (
    total_rows>=0 AND inserted_count>=0 AND updated_count>=0 AND unchanged_count>=0
    AND rejected_count>=0 AND duplicate_count>=0),
  CONSTRAINT medication_import_batches_completion_ck CHECK (
    (status IN ('processing','previewed') AND completed_at IS NULL)
    OR (status IN ('completed','failed') AND completed_at IS NOT NULL))
);

CREATE TABLE public.medication_import_rejections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL,
  row_number integer NOT NULL,
  source_record_id text NULL,
  raw_payload jsonb NOT NULL,
  reasons jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT medication_import_rejections_batch_fk FOREIGN KEY (batch_id)
    REFERENCES public.medication_import_batches(id) ON DELETE RESTRICT,
  CONSTRAINT medication_import_rejections_row_ck CHECK (row_number>=1),
  CONSTRAINT medication_import_rejections_payload_ck CHECK (jsonb_typeof(raw_payload)='object'),
  CONSTRAINT medication_import_rejections_reasons_ck CHECK (
    jsonb_typeof(reasons)='array' AND jsonb_array_length(reasons)>0),
  CONSTRAINT medication_import_rejections_batch_row_uq UNIQUE (batch_id,row_number)
);

CREATE TABLE public.dental_medications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  catalog_scope text NOT NULL,
  identity_key text NOT NULL,
  brand_name text NOT NULL,
  generic_name text NULL,
  strength text NOT NULL,
  dosage_form text NOT NULL,
  route text NOT NULL,
  category text NULL,
  manufacturer text NULL,
  market text NOT NULL,
  country text NULL,
  source_type text NOT NULL,
  source_name text NOT NULL,
  source_reference text NULL,
  source_version text NULL,
  source_record_id text NULL,
  verification_status text NOT NULL DEFAULT 'pending',
  licensing_status text NOT NULL DEFAULT 'pending',
  imported_at timestamptz NULL,
  last_verified_at timestamptz NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid NULL,
  import_batch_id uuid NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  search_document tsvector GENERATED ALWAYS AS (
    to_tsvector('simple'::regconfig,
      coalesce(brand_name,'') || ' ' || coalesce(generic_name,'') || ' ' ||
      coalesce(strength,'') || ' ' || coalesce(dosage_form,'') || ' ' ||
      coalesce(category,'') || ' ' || coalesce(manufacturer,''))
  ) STORED,
  CONSTRAINT dental_medications_created_by_fk FOREIGN KEY (created_by)
    REFERENCES public.users(id) ON DELETE RESTRICT,
  CONSTRAINT dental_medications_import_batch_fk FOREIGN KEY (import_batch_id)
    REFERENCES public.medication_import_batches(id) ON DELETE RESTRICT,
  CONSTRAINT dental_medications_scope_ck CHECK (catalog_scope IN ('global','clinic')),
  CONSTRAINT dental_medications_identity_ck CHECK (btrim(identity_key)<>'' AND char_length(identity_key)<=500),
  CONSTRAINT dental_medications_brand_ck CHECK (btrim(brand_name)<>'' AND char_length(btrim(brand_name))<=300),
  CONSTRAINT dental_medications_generic_ck CHECK (generic_name IS NULL OR char_length(btrim(generic_name))<=500),
  CONSTRAINT dental_medications_strength_ck CHECK (btrim(strength)<>'' AND char_length(btrim(strength))<=200),
  CONSTRAINT dental_medications_form_ck CHECK (btrim(dosage_form)<>'' AND char_length(btrim(dosage_form))<=200),
  CONSTRAINT dental_medications_route_ck CHECK (btrim(route)<>'' AND char_length(btrim(route))<=200),
  CONSTRAINT dental_medications_category_ck CHECK (category IS NULL OR char_length(btrim(category))<=300),
  CONSTRAINT dental_medications_manufacturer_ck CHECK (manufacturer IS NULL OR char_length(btrim(manufacturer))<=300),
  CONSTRAINT dental_medications_market_ck CHECK (btrim(market)<>'' AND char_length(btrim(market))<=100),
  CONSTRAINT dental_medications_source_ck CHECK (
    btrim(source_type)<>'' AND char_length(source_type)<=100
    AND btrim(source_name)<>'' AND char_length(source_name)<=300),
  CONSTRAINT dental_medications_verification_ck CHECK (
    verification_status IN ('pending','verified','unverified','deprecated')),
  CONSTRAINT dental_medications_licensing_ck CHECK (
    licensing_status IN ('pending','approved','restricted','rejected')),
  CONSTRAINT dental_medications_authority_ck CHECK (
    (catalog_scope='clinic' AND created_by IS NOT NULL AND source_type='clinic_custom'
      AND verification_status='unverified' AND licensing_status='pending'
      AND imported_at IS NULL AND import_batch_id IS NULL)
    OR
    (catalog_scope='global' AND source_type<>'clinic_custom' AND source_record_id IS NOT NULL
      AND imported_at IS NOT NULL AND import_batch_id IS NOT NULL))
);

CREATE UNIQUE INDEX dental_medications_global_source_identity_uq
  ON public.dental_medications(lower(btrim(source_name)),lower(btrim(market)),identity_key)
  WHERE catalog_scope='global';
CREATE UNIQUE INDEX dental_medications_global_source_record_uq
  ON public.dental_medications(lower(btrim(source_name)),lower(btrim(market)),source_record_id)
  WHERE catalog_scope='global';
CREATE UNIQUE INDEX dental_medications_clinic_identity_uq
  ON public.dental_medications(identity_key) WHERE catalog_scope='clinic';
CREATE INDEX dental_medications_search_gin_idx ON public.dental_medications USING gin(search_document);
CREATE INDEX dental_medications_brand_prefix_idx ON public.dental_medications(lower(brand_name) text_pattern_ops);
CREATE INDEX dental_medications_generic_prefix_idx ON public.dental_medications(lower(generic_name) text_pattern_ops);
CREATE INDEX dental_medications_visible_idx
  ON public.dental_medications(catalog_scope,verification_status,licensing_status,lower(brand_name),id)
  WHERE is_active;
CREATE INDEX dental_medications_created_by_idx ON public.dental_medications(created_by) WHERE created_by IS NOT NULL;
CREATE INDEX dental_medications_import_batch_idx ON public.dental_medications(import_batch_id) WHERE import_batch_id IS NOT NULL;
CREATE INDEX medication_import_batches_started_idx ON public.medication_import_batches(started_at DESC,id DESC);
CREATE INDEX medication_import_rejections_batch_idx ON public.medication_import_rejections(batch_id,row_number);

CREATE TABLE public.medication_clinical_presets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  medication_id uuid NOT NULL,
  default_dose text NULL,
  default_frequency text NULL,
  default_duration text NULL,
  default_instructions text NULL,
  clinical_context text NOT NULL DEFAULT 'general_dental',
  source text NOT NULL,
  source_reference text NULL,
  source_version text NULL,
  reviewed_by uuid NULL,
  reviewed_at timestamptz NULL,
  preset_version integer NOT NULL DEFAULT 1,
  review_status text NOT NULL DEFAULT 'pending',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT medication_clinical_presets_medication_fk FOREIGN KEY (medication_id)
    REFERENCES public.dental_medications(id) ON DELETE RESTRICT,
  CONSTRAINT medication_clinical_presets_reviewed_by_fk FOREIGN KEY (reviewed_by)
    REFERENCES public.users(id) ON DELETE RESTRICT,
  CONSTRAINT medication_clinical_presets_context_ck CHECK (btrim(clinical_context)<>'' AND char_length(clinical_context)<=300),
  CONSTRAINT medication_clinical_presets_source_ck CHECK (btrim(source)<>'' AND char_length(source)<=500),
  CONSTRAINT medication_clinical_presets_lengths_ck CHECK (
    (default_dose IS NULL OR char_length(default_dose)<=300)
    AND (default_frequency IS NULL OR char_length(default_frequency)<=300)
    AND (default_duration IS NULL OR char_length(default_duration)<=300)
    AND (default_instructions IS NULL OR char_length(default_instructions)<=4000)),
  CONSTRAINT medication_clinical_presets_version_ck CHECK (preset_version>=1),
  CONSTRAINT medication_clinical_presets_review_status_ck CHECK (review_status IN ('pending','approved','rejected','deprecated')),
  CONSTRAINT medication_clinical_presets_review_ck CHECK (
    (review_status='approved' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
    OR review_status<>'approved')
);
CREATE UNIQUE INDEX medication_clinical_presets_active_context_uq
  ON public.medication_clinical_presets(medication_id,lower(clinical_context)) WHERE is_active;
CREATE INDEX medication_clinical_presets_review_idx
  ON public.medication_clinical_presets(review_status,is_active,medication_id);

CREATE TABLE public.doctor_medication_presets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doctor_id uuid NOT NULL,
  medication_id uuid NOT NULL,
  default_dose text NULL,
  default_frequency text NULL,
  default_duration text NULL,
  default_instructions text NULL,
  doctor_notes text NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT doctor_medication_presets_doctor_fk FOREIGN KEY (doctor_id)
    REFERENCES public.users(id) ON DELETE RESTRICT,
  CONSTRAINT doctor_medication_presets_medication_fk FOREIGN KEY (medication_id)
    REFERENCES public.dental_medications(id) ON DELETE RESTRICT,
  CONSTRAINT doctor_medication_presets_lengths_ck CHECK (
    (default_dose IS NULL OR char_length(default_dose)<=300)
    AND (default_frequency IS NULL OR char_length(default_frequency)<=300)
    AND (default_duration IS NULL OR char_length(default_duration)<=300)
    AND (default_instructions IS NULL OR char_length(default_instructions)<=4000)
    AND (doctor_notes IS NULL OR char_length(doctor_notes)<=4000)),
  CONSTRAINT doctor_medication_presets_doctor_medication_uq UNIQUE (doctor_id,medication_id)
);
CREATE INDEX doctor_medication_presets_medication_idx ON public.doctor_medication_presets(medication_id);

CREATE TABLE public.prescriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  doctor_id uuid NOT NULL,
  appointment_id uuid NULL,
  status text NOT NULL DEFAULT 'draft',
  version integer NOT NULL DEFAULT 1,
  approved_by uuid NULL,
  approved_at timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT prescriptions_consultation_fk FOREIGN KEY (consultation_id)
    REFERENCES public.consultations(id) ON DELETE RESTRICT,
  CONSTRAINT prescriptions_patient_fk FOREIGN KEY (patient_id)
    REFERENCES public.patients(id) ON DELETE RESTRICT,
  CONSTRAINT prescriptions_doctor_fk FOREIGN KEY (doctor_id)
    REFERENCES public.users(id) ON DELETE RESTRICT,
  CONSTRAINT prescriptions_appointment_fk FOREIGN KEY (appointment_id)
    REFERENCES public.appointments(id) ON DELETE RESTRICT,
  CONSTRAINT prescriptions_approved_by_fk FOREIGN KEY (approved_by)
    REFERENCES public.users(id) ON DELETE RESTRICT,
  CONSTRAINT prescriptions_consultation_uq UNIQUE (consultation_id),
  CONSTRAINT prescriptions_status_ck CHECK (status IN ('draft','approved')),
  CONSTRAINT prescriptions_version_ck CHECK (version>=1),
  CONSTRAINT prescriptions_approval_state_ck CHECK (
    (status='draft' AND approved_by IS NULL AND approved_at IS NULL)
    OR (status='approved' AND approved_by IS NOT NULL AND approved_at IS NOT NULL))
);
CREATE INDEX prescriptions_patient_idx ON public.prescriptions(patient_id,created_at DESC,id DESC);
CREATE INDEX prescriptions_doctor_idx ON public.prescriptions(doctor_id,created_at DESC,id DESC);
CREATE INDEX prescriptions_appointment_idx ON public.prescriptions(appointment_id) WHERE appointment_id IS NOT NULL;
CREATE INDEX prescriptions_status_idx ON public.prescriptions(status,updated_at DESC,id DESC);

CREATE TABLE public.prescription_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  prescription_id uuid NOT NULL,
  medication_id uuid NULL,
  clinical_preset_id uuid NULL,
  doctor_preset_id uuid NULL,
  position integer NOT NULL,
  brand_name_snapshot text NOT NULL,
  generic_name_snapshot text NULL,
  strength_snapshot text NOT NULL,
  dosage_form_snapshot text NOT NULL,
  route_snapshot text NOT NULL,
  dose_snapshot text NOT NULL,
  frequency_snapshot text NOT NULL,
  duration_snapshot text NOT NULL,
  instructions_snapshot text NULL,
  doctor_notes_snapshot text NULL,
  source_type_snapshot text NULL,
  source_name_snapshot text NULL,
  source_reference_snapshot text NULL,
  source_version_snapshot text NULL,
  source_record_id_snapshot text NULL,
  verification_status_snapshot text NULL,
  licensing_status_snapshot text NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT prescription_items_prescription_fk FOREIGN KEY (prescription_id)
    REFERENCES public.prescriptions(id) ON DELETE RESTRICT,
  CONSTRAINT prescription_items_medication_fk FOREIGN KEY (medication_id)
    REFERENCES public.dental_medications(id) ON DELETE RESTRICT,
  CONSTRAINT prescription_items_clinical_preset_fk FOREIGN KEY (clinical_preset_id)
    REFERENCES public.medication_clinical_presets(id) ON DELETE RESTRICT,
  CONSTRAINT prescription_items_doctor_preset_fk FOREIGN KEY (doctor_preset_id)
    REFERENCES public.doctor_medication_presets(id) ON DELETE RESTRICT,
  CONSTRAINT prescription_items_position_ck CHECK (position BETWEEN 1 AND 50),
  CONSTRAINT prescription_items_required_snapshot_ck CHECK (
    btrim(brand_name_snapshot)<>'' AND char_length(brand_name_snapshot)<=300
    AND btrim(strength_snapshot)<>'' AND char_length(strength_snapshot)<=200
    AND btrim(dosage_form_snapshot)<>'' AND char_length(dosage_form_snapshot)<=200
    AND btrim(route_snapshot)<>'' AND char_length(route_snapshot)<=200
    AND btrim(dose_snapshot)<>'' AND char_length(dose_snapshot)<=300
    AND btrim(frequency_snapshot)<>'' AND char_length(frequency_snapshot)<=300
    AND btrim(duration_snapshot)<>'' AND char_length(duration_snapshot)<=300),
  CONSTRAINT prescription_items_optional_snapshot_ck CHECK (
    (generic_name_snapshot IS NULL OR char_length(generic_name_snapshot)<=500)
    AND (instructions_snapshot IS NULL OR char_length(instructions_snapshot)<=4000)
    AND (doctor_notes_snapshot IS NULL OR char_length(doctor_notes_snapshot)<=4000)),
  CONSTRAINT prescription_items_position_uq UNIQUE (prescription_id,position),
  CONSTRAINT prescription_items_medication_uq UNIQUE (prescription_id,medication_id)
);
CREATE INDEX prescription_items_prescription_idx ON public.prescription_items(prescription_id,position,id);
CREATE INDEX prescription_items_medication_idx ON public.prescription_items(medication_id) WHERE medication_id IS NOT NULL;

ALTER TABLE public.medication_import_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.medication_import_rejections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dental_medications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.medication_clinical_presets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.doctor_medication_presets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prescriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prescription_items ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.medication_import_batches,public.medication_import_rejections,
  public.dental_medications,public.medication_clinical_presets,public.doctor_medication_presets,
  public.prescriptions,public.prescription_items FROM PUBLIC,anon,authenticated;

CREATE FUNCTION security.medication_prescription_actor()
RETURNS TABLE(id uuid,role text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $function$
  SELECT app_user.id,app_user.role::text FROM public.users app_user
   WHERE app_user.supabase_user_id=auth.uid() AND app_user.is_active=true
     AND app_user.approved_at IS NOT NULL AND app_user.role::text IN ('doctor','admin')
   LIMIT 1
$function$;

CREATE FUNCTION security.prescription_projection(p_prescription_id uuid)
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
      'verificationStatus',item.verification_status_snapshot,
      'licensingStatus',item.licensing_status_snapshot
    ) ORDER BY item.position,item.id) FROM public.prescription_items item
      WHERE item.prescription_id=prescription.id),'[]'::jsonb))
  FROM public.prescriptions prescription WHERE prescription.id=p_prescription_id
$function$;

CREATE FUNCTION public.search_dental_medications(p_query text,p_limit integer DEFAULT 20)
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
          'verificationStatus',medication.verification_status,'licensingStatus',medication.licensing_status,
          'sourceType',medication.source_type,'sourceName',medication.source_name
        ) payload
      FROM public.dental_medications medication
      WHERE medication.is_active
        AND ((medication.catalog_scope='clinic' AND medication.verification_status='unverified')
          OR (medication.catalog_scope='global' AND medication.verification_status='verified'
              AND medication.licensing_status='approved'))
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

CREATE FUNCTION public.create_custom_medication(
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
      licensing_status,is_active,created_by)
    VALUES('clinic',v_identity,btrim(p_brand_name),nullif(btrim(p_generic_name),''),btrim(p_strength),
      btrim(p_dosage_form),btrim(p_route),nullif(btrim(p_category),''),nullif(btrim(p_manufacturer),''),
      'clinic','clinic','clinic_custom','Clinician-entered custom medication','unverified','pending',true,v_actor_id)
    RETURNING * INTO v_medication;
  ELSIF NOT v_medication.is_active THEN
    UPDATE public.dental_medications SET is_active=true,updated_at=clock_timestamp()
     WHERE id=v_medication.id RETURNING * INTO v_medication;
  END IF;
  RETURN jsonb_build_object('id',v_medication.id,'brandName',v_medication.brand_name,
    'genericName',v_medication.generic_name,'strength',v_medication.strength,
    'dosageForm',v_medication.dosage_form,'route',v_medication.route,'category',v_medication.category,
    'manufacturer',v_medication.manufacturer,'market',v_medication.market,'catalogScope','clinic',
    'isCustom',true,'verificationStatus','unverified','licensingStatus','pending',
    'sourceType','clinic_custom','sourceName',v_medication.source_name);
END
$function$;

CREATE FUNCTION public.get_effective_medication_preset(p_medication_id uuid)
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
       OR (medication.catalog_scope='global' AND medication.verification_status='verified'
         AND medication.licensing_status='approved'));
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
      'sourceRecordId',v_medication.source_record_id,'verificationStatus',v_medication.verification_status,
      'licensingStatus',v_medication.licensing_status),
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

CREATE FUNCTION public.upsert_doctor_medication_preset(
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
        OR (medication.catalog_scope='global' AND medication.verification_status='verified'
          AND medication.licensing_status='approved')))
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

CREATE FUNCTION public.delete_doctor_medication_preset(p_medication_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text; v_count integer;
BEGIN
  SELECT actor.id,actor.role INTO v_actor_id,v_actor_role FROM security.medication_prescription_actor() actor;
  IF v_actor_id IS NULL OR v_actor_role<>'doctor' THEN RAISE EXCEPTION 'DOCTOR_PRESET_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  DELETE FROM public.doctor_medication_presets WHERE doctor_id=v_actor_id AND medication_id=p_medication_id;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  RETURN jsonb_build_object('deleted',v_count=1,'medicationId',p_medication_id);
END
$function$;

CREATE FUNCTION public.get_consultation_prescription(p_consultation_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text; v_prescription_id uuid;
BEGIN
  SELECT actor.id,actor.role INTO v_actor_id,v_actor_role FROM security.medication_prescription_actor() actor;
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'PRESCRIPTION_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
  SELECT prescription.id INTO v_prescription_id FROM public.prescriptions prescription
   JOIN public.consultations consultation ON consultation.id=prescription.consultation_id
   WHERE prescription.consultation_id=p_consultation_id
     AND (v_actor_role='admin' OR (prescription.doctor_id=v_actor_id AND consultation.doctor_id=v_actor_id));
  IF v_prescription_id IS NULL THEN
    IF NOT EXISTS(SELECT 1 FROM public.consultations consultation WHERE consultation.id=p_consultation_id
      AND (v_actor_role='admin' OR consultation.doctor_id=v_actor_id)) THEN
      RAISE EXCEPTION 'PRESCRIPTION_AUTHORIZATION_DENIED' USING ERRCODE='42501';
    END IF;
    RETURN NULL;
  END IF;
  RETURN security.prescription_projection(v_prescription_id);
END
$function$;

CREATE FUNCTION public.save_prescription_draft(p_consultation_id uuid,p_expected_version integer,p_items jsonb)
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
      (v_medication.catalog_scope='global' AND v_medication.verification_status='verified'
        AND v_medication.licensing_status='approved')
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
      source_record_id_snapshot,verification_status_snapshot,licensing_status_snapshot)
    VALUES(v_prescription.id,v_medication_id,v_clinical_preset_id,v_doctor_preset_id,v_position,
      btrim(v_item->>'brandName'),nullif(btrim(v_item->>'genericName'),''),btrim(v_item->>'strength'),
      btrim(v_item->>'dosageForm'),btrim(v_item->>'route'),btrim(v_item->>'dose'),
      btrim(v_item->>'frequency'),btrim(v_item->>'duration'),nullif(btrim(v_item->>'instructions'),''),
      nullif(btrim(v_item->>'doctorNotes'),''),v_medication.source_type,v_medication.source_name,
      v_medication.source_reference,v_medication.source_version,v_medication.source_record_id,
      v_medication.verification_status,v_medication.licensing_status);
  END LOOP;

  RETURN security.prescription_projection(v_prescription.id);
END
$function$;

CREATE FUNCTION public.approve_prescription(p_prescription_id uuid,p_expected_version integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text; v_prescription public.prescriptions%ROWTYPE;
BEGIN
  SELECT actor.id,actor.role INTO v_actor_id,v_actor_role
    FROM security.medication_prescription_actor() actor;
  IF v_actor_id IS NULL OR v_actor_role<>'doctor' THEN
    RAISE EXCEPTION 'PRESCRIPTION_AUTHORIZATION_DENIED' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_prescription
    FROM public.prescriptions prescription
   WHERE prescription.id=p_prescription_id
   FOR UPDATE;
  IF v_prescription.id IS NULL THEN
    RAISE EXCEPTION 'PRESCRIPTION_NOT_FOUND' USING ERRCODE='P3404';
  END IF;
  IF v_prescription.status<>'draft' THEN
    RAISE EXCEPTION 'APPROVED_PRESCRIPTION_IMMUTABLE' USING ERRCODE='P3405';
  END IF;
  IF v_prescription.doctor_id<>v_actor_id THEN
    RAISE EXCEPTION 'PRESCRIPTION_AUTHORIZATION_DENIED' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.consultations consultation
     WHERE consultation.id=v_prescription.consultation_id
       AND consultation.patient_id=v_prescription.patient_id
       AND consultation.doctor_id=v_actor_id
       AND consultation.appointment_id IS NOT DISTINCT FROM v_prescription.appointment_id
  ) THEN
    RAISE EXCEPTION 'PRESCRIPTION_AUTHORIZATION_DENIED' USING ERRCODE='42501';
  END IF;
  IF p_expected_version IS NULL OR p_expected_version<>v_prescription.version THEN
    RAISE EXCEPTION 'PRESCRIPTION_VERSION_CONFLICT' USING ERRCODE='40001';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.prescription_items item
     WHERE item.prescription_id=v_prescription.id
  ) THEN
    RAISE EXCEPTION 'PRESCRIPTION_EMPTY' USING ERRCODE='22023';
  END IF;

  UPDATE public.prescriptions
     SET status='approved',
         approved_by=v_actor_id,
         approved_at=clock_timestamp(),
         version=version+1,
         updated_at=clock_timestamp()
   WHERE id=v_prescription.id
   RETURNING * INTO v_prescription;

  RETURN security.prescription_projection(v_prescription.id);
END
$function$;

CREATE FUNCTION security.prevent_approved_prescription_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp
AS $function$
BEGIN
  IF TG_OP='DELETE' AND OLD.status='approved' THEN
    RAISE EXCEPTION 'APPROVED_PRESCRIPTION_IMMUTABLE' USING ERRCODE='P3405';
  ELSIF TG_OP='UPDATE' AND OLD.status='approved' THEN
    RAISE EXCEPTION 'APPROVED_PRESCRIPTION_IMMUTABLE' USING ERRCODE='P3405';
  ELSIF TG_OP='UPDATE' AND (NEW.status<>OLD.status AND NOT (OLD.status='draft' AND NEW.status='approved')) THEN
    RAISE EXCEPTION 'PRESCRIPTION_STATUS_TRANSITION_INVALID' USING ERRCODE='22023';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END
$function$;
CREATE TRIGGER prescriptions_approved_immutability
BEFORE UPDATE OR DELETE ON public.prescriptions FOR EACH ROW
EXECUTE FUNCTION security.prevent_approved_prescription_mutation();

CREATE FUNCTION security.prevent_approved_prescription_item_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp
AS $function$
BEGIN
  IF TG_OP='INSERT' THEN
    IF EXISTS(
      SELECT 1 FROM public.prescriptions prescription
       WHERE prescription.id=NEW.prescription_id
         AND prescription.status='approved'
    ) THEN
      RAISE EXCEPTION 'APPROVED_PRESCRIPTION_IMMUTABLE' USING ERRCODE='P3405';
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP='DELETE' THEN
    IF EXISTS(
      SELECT 1 FROM public.prescriptions prescription
       WHERE prescription.id=OLD.prescription_id
         AND prescription.status='approved'
    ) THEN
      RAISE EXCEPTION 'APPROVED_PRESCRIPTION_IMMUTABLE' USING ERRCODE='P3405';
    END IF;
    RETURN OLD;
  END IF;

  IF EXISTS(
    SELECT 1 FROM public.prescriptions prescription
     WHERE prescription.id=OLD.prescription_id
       AND prescription.status='approved'
  ) OR EXISTS(
    SELECT 1 FROM public.prescriptions prescription
     WHERE prescription.id=NEW.prescription_id
       AND prescription.status='approved'
  ) THEN
    RAISE EXCEPTION 'APPROVED_PRESCRIPTION_IMMUTABLE' USING ERRCODE='P3405';
  END IF;

  RETURN NEW;
END
$function$;
CREATE TRIGGER prescription_items_approved_immutability
BEFORE INSERT OR UPDATE OR DELETE ON public.prescription_items FOR EACH ROW
EXECUTE FUNCTION security.prevent_approved_prescription_item_mutation();

-- Enrich existing history projections from stored snapshots only.
CREATE OR REPLACE FUNCTION public.get_patient_consultation_history(p_patient_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_base jsonb; v_result jsonb;
BEGIN
  v_base:=security.get_patient_consultation_history_base(p_patient_id);
  SELECT coalesce(jsonb_agg(item.value||jsonb_build_object(
    'clinicalFindings',consultation.clinical_findings_snapshot,
    'prescription',CASE WHEN prescription.status='approved'
      THEN security.prescription_projection(prescription.id) ELSE NULL END
  ) ORDER BY item.ordinality),'[]'::jsonb) INTO v_result
  FROM jsonb_array_elements(v_base) WITH ORDINALITY item(value,ordinality)
  LEFT JOIN public.consultations consultation
    ON consultation.id=nullif(item.value->>'consultationId','')::uuid
  LEFT JOIN public.prescriptions prescription
    ON prescription.consultation_id=consultation.id;
  RETURN v_result;
END
$function$;

CREATE OR REPLACE FUNCTION public.list_doctor_consultation_history()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_base jsonb; v_result jsonb;
BEGIN
  v_base:=security.list_doctor_consultation_history_base();
  SELECT coalesce(jsonb_agg(item.value||jsonb_build_object(
    'clinicalFindings',consultation.clinical_findings_snapshot,
    'reportSnapshot',report.report_snapshot,'snapshotVersion',report.snapshot_version,
    'reviewedAt',report.reviewed_at,'finalizedAt',report.finalized_at,
    'labNote',consultation.lab_note,'labItems',coalesce(lab_snapshot.items,'[]'::jsonb),
    'prescription',CASE WHEN prescription.status='approved'
      THEN security.prescription_projection(prescription.id) ELSE NULL END
  ) ORDER BY item.ordinality),'[]'::jsonb) INTO v_result
  FROM jsonb_array_elements(v_base) WITH ORDINALITY item(value,ordinality)
  LEFT JOIN public.consultations consultation
    ON consultation.id=nullif(item.value->>'consultationId','')::uuid
  LEFT JOIN public.clinical_reports report
    ON report.id=nullif(item.value->>'reportId','')::uuid
  LEFT JOIN public.prescriptions prescription ON prescription.consultation_id=consultation.id
  LEFT JOIN LATERAL(
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'labId',lab_item.lab_id,'labProductId',lab_item.lab_product_id,
      'labName',lab_item.lab_name_snapshot,'productName',lab_item.product_name_snapshot,
      'unitPrice',lab_item.unit_price_snapshot,'quantity',lab_item.quantity,
      'totalAmount',lab_item.total_amount
    ) ORDER BY lab_item.created_at,lower(lab_item.lab_name_snapshot),
      lower(lab_item.product_name_snapshot),lab_item.id),'[]'::jsonb) items
    FROM public.consultation_lab_items lab_item WHERE lab_item.consultation_id=consultation.id
  ) lab_snapshot ON true;
  RETURN v_result;
END
$function$;

-- A draft blocks completion. Approved prescriptions and consultations without a prescription remain valid.
CREATE OR REPLACE FUNCTION public.finish_appointment_by_patient(
  p_patient_id uuid,p_appointment_id uuid DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_caller_id uuid; v_caller_role text; v_appointment_id uuid; v_consultation_id uuid;
BEGIN
  v_caller_id:=security.current_app_user_id(); v_caller_role:=security.current_app_role();
  IF v_caller_id IS NULL OR v_caller_role NOT IN ('doctor','admin') THEN
    RAISE EXCEPTION 'Insufficient permissions' USING ERRCODE='42501';
  END IF;
  SELECT appointment.id INTO v_appointment_id FROM public.appointments appointment
   WHERE appointment.patient_id=p_patient_id
     AND (p_appointment_id IS NULL OR appointment.id=p_appointment_id)
     AND appointment.date=current_date AND appointment.status::text IN ('pending','confirmed')
     AND appointment.doctor_id IS NOT NULL
     AND (v_caller_role='admin' OR appointment.doctor_id=v_caller_id)
   ORDER BY appointment.appointment_time NULLS LAST,appointment.time,appointment.id
   LIMIT 1 FOR UPDATE;
  IF v_appointment_id IS NULL THEN
    RAISE EXCEPTION 'No active appointment found for this patient today' USING ERRCODE='P0002';
  END IF;
  SELECT consultation.id INTO v_consultation_id FROM public.consultations consultation
   WHERE consultation.appointment_id=v_appointment_id AND consultation.patient_id=p_patient_id
     AND (v_caller_role='admin' OR consultation.doctor_id=v_caller_id)
   ORDER BY consultation.last_updated DESC NULLS LAST,consultation.id DESC LIMIT 1 FOR UPDATE;
  IF EXISTS(SELECT 1 FROM public.prescriptions prescription
    WHERE prescription.consultation_id=v_consultation_id AND prescription.status='draft') THEN
    RAISE EXCEPTION 'PRESCRIPTION_REVIEW_REQUIRED' USING ERRCODE='P3406';
  END IF;
  UPDATE public.appointments SET status='completed' WHERE id=v_appointment_id;
  INSERT INTO public.logs(id,message,doctor_id,patient_id,created_at)
  VALUES(gen_random_uuid(),format('Clinical session finished for patient %s',p_patient_id),
    v_caller_id,p_patient_id,clock_timestamp());
  RETURN jsonb_build_object('status','success','appointment_id',v_appointment_id);
END
$function$;

-- Keep the existing Admin clinic reset compatible with the new restrictive FKs.
CREATE OR REPLACE FUNCTION public.format_clinic_data()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_actor_id uuid;
BEGIN
  v_actor_id:=security.admin_user_actor();
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'FORMAT_CLINIC_AUTHORIZATION_DENIED' USING ERRCODE='42501';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('smart-clinic:destructive-operations',0)
  );
  TRUNCATE TABLE
    public.notifications,
    public.financial_payment_allocations,
    public.financial_charge_adjustments,
    public.financial_payment_records,
    public.consultation_procedures,
    public.lab_payments,
    public.consultation_lab_items,
    public.prescription_items,
    public.prescriptions,
    public.clinical_reports,
    public.patient_dental_state,
    public.records,
    public.logs,
    public.consultations,
    public.appointments,
    public.patients,
    public.lab_products,
    public.labs;
  RETURN jsonb_build_object('formatted',true);
END
$function$;

REVOKE ALL ON FUNCTION security.medication_prescription_actor() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION security.prescription_projection(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION security.prevent_approved_prescription_mutation() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION security.prevent_approved_prescription_item_mutation() FROM PUBLIC,anon,authenticated;

REVOKE ALL ON FUNCTION public.search_dental_medications(text,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_custom_medication(text,text,text,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_effective_medication_preset(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.upsert_doctor_medication_preset(uuid,text,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_doctor_medication_preset(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_consultation_prescription(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.save_prescription_draft(uuid,integer,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.approve_prescription(uuid,integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.search_dental_medications(text,integer),
  public.create_custom_medication(text,text,text,text,text,text,text),
  public.get_effective_medication_preset(uuid),
  public.upsert_doctor_medication_preset(uuid,text,text,text,text,text),
  public.delete_doctor_medication_preset(uuid),public.get_consultation_prescription(uuid),
  public.save_prescription_draft(uuid,integer,jsonb),public.approve_prescription(uuid,integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.search_dental_medications(text,integer),
  public.create_custom_medication(text,text,text,text,text,text,text),
  public.get_effective_medication_preset(uuid),
  public.upsert_doctor_medication_preset(uuid,text,text,text,text,text),
  public.delete_doctor_medication_preset(uuid),public.get_consultation_prescription(uuid),
  public.save_prescription_draft(uuid,integer,jsonb),public.approve_prescription(uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.get_patient_consultation_history(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_patient_consultation_history(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_patient_consultation_history(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.list_doctor_consultation_history() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_doctor_consultation_history() FROM anon;
GRANT EXECUTE ON FUNCTION public.list_doctor_consultation_history() TO authenticated;
REVOKE ALL ON FUNCTION public.finish_appointment_by_patient(uuid,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.finish_appointment_by_patient(uuid,uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.finish_appointment_by_patient(uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.format_clinic_data() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.format_clinic_data() FROM anon;
GRANT EXECUTE ON FUNCTION public.format_clinic_data() TO authenticated;

COMMIT;