-- Migration 036: immutable human-readable sequential display IDs.
-- New-row assignment uses clock_timestamp(), the database server's wall-clock
-- timestamp, and stores that same value in created_at before deriving Cairo MMYY.
-- UUID primary/foreign keys remain canonical. Display IDs are presentation metadata only.
BEGIN;

DO $precondition$
DECLARE v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['patients','appointments','consultations'] LOOP
    IF to_regclass('public.'||v_table) IS NULL THEN
      RAISE EXCEPTION 'MIGRATION_036_REQUIRED_TABLE_MISSING: public.%',v_table;
    END IF;
    IF NOT EXISTS(
      SELECT 1 FROM information_schema.columns
       WHERE table_schema='public' AND table_name=v_table AND column_name='id' AND data_type='uuid'
    ) THEN RAISE EXCEPTION 'MIGRATION_036_UUID_PRIMARY_ID_REQUIRED: public.%',v_table; END IF;
    IF NOT EXISTS(
      SELECT 1 FROM information_schema.columns
       WHERE table_schema='public' AND table_name=v_table AND column_name='created_at'
         AND data_type='timestamp with time zone'
    ) THEN RAISE EXCEPTION 'MIGRATION_036_CREATED_AT_REQUIRED: public.%',v_table; END IF;
    IF EXISTS(
      SELECT 1 FROM information_schema.columns
       WHERE table_schema='public' AND table_name=v_table AND column_name='display_id'
    ) THEN RAISE EXCEPTION 'MIGRATION_036_DISPLAY_ID_ALREADY_EXISTS: public.%',v_table; END IF;
  END LOOP;
  IF to_regclass('public.display_id_counters') IS NOT NULL
     OR to_regprocedure('security.allocate_display_id(text,timestamp with time zone)') IS NOT NULL
     OR to_regprocedure('security.assign_display_id()') IS NOT NULL
     OR to_regprocedure('security.reject_display_id_change()') IS NOT NULL
     OR to_regprocedure('security.appointment_projection_036_base(uuid)') IS NOT NULL
     OR to_regprocedure('security.get_appointments_036_base()') IS NOT NULL
     OR to_regprocedure('security.get_or_initialize_consultation_036_base(uuid)') IS NOT NULL
     OR to_regprocedure('security.save_current_consultation_036_base(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)') IS NOT NULL
     OR to_regprocedure('security.get_patient_consultation_history_036_base(uuid)') IS NOT NULL
     OR to_regprocedure('security.list_doctor_consultation_history_036_base()') IS NOT NULL
     OR to_regprocedure('security.financial_billing_projection_036_base(uuid)') IS NOT NULL
     OR to_regprocedure('security.list_lab_transactions_036_base(uuid,timestamp with time zone,timestamp with time zone)') IS NOT NULL THEN
    RAISE EXCEPTION 'MIGRATION_036_TARGET_OBJECT_CONFLICT';
  END IF;
  IF EXISTS(
    SELECT 1 FROM public.patients WHERE created_at IS NULL
    UNION ALL SELECT 1 FROM public.appointments WHERE created_at IS NULL
    UNION ALL SELECT 1 FROM public.consultations WHERE created_at IS NULL
  ) THEN RAISE EXCEPTION 'MIGRATION_036_NULL_CREATED_AT_CONFLICT'; END IF;

  IF to_regprocedure('security.appointment_projection(uuid)') IS NULL
     OR to_regprocedure('public.get_appointments()') IS NULL
     OR to_regprocedure('public.get_or_initialize_consultation(uuid)') IS NULL
     OR to_regprocedure('public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)') IS NULL
     OR to_regprocedure('public.get_patient_consultation_history(uuid)') IS NULL
     OR to_regprocedure('public.list_doctor_consultation_history()') IS NULL
     OR to_regprocedure('security.financial_billing_projection(uuid)') IS NULL
     OR to_regprocedure('public.list_lab_transactions(uuid,timestamp with time zone,timestamp with time zone)') IS NULL THEN
    RAISE EXCEPTION 'MIGRATION_036_EXPECTED_RPC_SIGNATURE_MISSING';
  END IF;

  IF EXISTS(
    SELECT 1 FROM pg_proc procedure
    WHERE procedure.oid IN(
      'security.appointment_projection(uuid)'::regprocedure,
      'public.get_appointments()'::regprocedure,
      'public.get_or_initialize_consultation(uuid)'::regprocedure,
      'public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)'::regprocedure,
      'public.get_patient_consultation_history(uuid)'::regprocedure,
      'public.list_doctor_consultation_history()'::regprocedure,
      'security.financial_billing_projection(uuid)'::regprocedure,
      'public.list_lab_transactions(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure
    ) AND (NOT procedure.prosecdef OR NOT coalesce(procedure.proconfig,'{}') @> ARRAY['search_path=pg_catalog, pg_temp'])
  ) THEN RAISE EXCEPTION 'MIGRATION_036_RPC_SECURITY_CONTRACT_MISMATCH'; END IF;

  IF EXISTS(
    SELECT 1 FROM (VALUES
      ('security.appointment_projection(uuid)'::regprocedure::oid,'s'::"char"),
      ('public.get_appointments()'::regprocedure::oid,'s'::"char"),
      ('public.get_or_initialize_consultation(uuid)'::regprocedure::oid,'s'::"char"),
      ('public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)'::regprocedure::oid,'v'::"char"),
      ('public.get_patient_consultation_history(uuid)'::regprocedure::oid,'s'::"char"),
      ('public.list_doctor_consultation_history()'::regprocedure::oid,'s'::"char"),
      ('security.financial_billing_projection(uuid)'::regprocedure::oid,'s'::"char"),
      ('public.list_lab_transactions(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure::oid,'s'::"char")
    ) expected(oid,volatility) JOIN pg_proc procedure ON procedure.oid=expected.oid
    WHERE procedure.provolatile<>expected.volatility
  ) THEN RAISE EXCEPTION 'MIGRATION_036_RPC_VOLATILITY_CONTRACT_MISMATCH'; END IF;

  IF replace(pg_get_function_result('public.get_appointments()'::regprocedure),'"','') IS DISTINCT FROM
     'TABLE(id uuid, patient_id uuid, patient text, doctor_id uuid, doctor text, date date, time text, type text, status text, condition text, notes text)'
     OR NOT has_function_privilege('authenticated','public.get_appointments()','EXECUTE')
     OR has_function_privilege('anon','public.get_appointments()','EXECUTE')
     OR has_function_privilege('PUBLIC','public.get_appointments()','EXECUTE') THEN
    RAISE EXCEPTION 'MIGRATION_036_GET_APPOINTMENTS_CONTRACT_MISMATCH';
  END IF;

  IF EXISTS(SELECT 1 FROM unnest(ARRAY[
      'public.get_or_initialize_consultation(uuid)'::regprocedure::oid,
      'public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)'::regprocedure::oid,
      'public.get_patient_consultation_history(uuid)'::regprocedure::oid,
      'public.list_doctor_consultation_history()'::regprocedure::oid,
      'public.list_lab_transactions(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure::oid
    ]) expected(oid)
    WHERE NOT has_function_privilege('authenticated',expected.oid,'EXECUTE')
       OR has_function_privilege('anon',expected.oid,'EXECUTE')
       OR has_function_privilege('PUBLIC',expected.oid,'EXECUTE')) THEN
    RAISE EXCEPTION 'MIGRATION_036_PUBLIC_RPC_GRANT_CONTRACT_MISMATCH';
  END IF;

END
$precondition$;

-- Consistent order; held until COMMIT so backfill, seed, and trigger installation are one cutover.
LOCK TABLE public.patients IN ACCESS EXCLUSIVE MODE;
LOCK TABLE public.appointments IN ACCESS EXCLUSIVE MODE;
LOCK TABLE public.consultations IN ACCESS EXCLUSIVE MODE;

-- The five-digit namespace is finite. Check under the cutover locks so the
-- count cannot change between validation and deterministic backfill.
DO $capacity$
DECLARE v_conflict text;
BEGIN
  SELECT string_agg(entity_type||'/'||year_month||'='||row_count,', ' ORDER BY entity_type,year_month)
    INTO v_conflict
  FROM (
    SELECT entity_type,year_month,count(*) row_count FROM (
      SELECT 'patients'::text entity_type,to_char(created_at AT TIME ZONE 'Africa/Cairo','YYYYMM') year_month FROM public.patients
      UNION ALL SELECT 'appointments',to_char(created_at AT TIME ZONE 'Africa/Cairo','YYYYMM') FROM public.appointments
      UNION ALL SELECT 'consultations',to_char(created_at AT TIME ZONE 'Africa/Cairo','YYYYMM') FROM public.consultations
    ) rows GROUP BY entity_type,year_month HAVING count(*)>99999
  ) over_capacity;
  IF v_conflict IS NOT NULL THEN
    RAISE EXCEPTION 'MIGRATION_036_MONTHLY_CAPACITY_EXCEEDED: %',v_conflict USING ERRCODE='22023';
  END IF;
END
$capacity$;

CREATE TABLE public.display_id_counters(
  entity_type text NOT NULL,
  year_month text NOT NULL,
  current_value integer NOT NULL,
  CONSTRAINT display_id_counters_pk PRIMARY KEY(entity_type,year_month),
  CONSTRAINT display_id_counters_entity_ck CHECK(entity_type IN ('patients','appointments','consultations')),
  CONSTRAINT display_id_counters_month_ck CHECK(year_month ~ '^[0-9]{6}$'),
  CONSTRAINT display_id_counters_value_ck CHECK(current_value BETWEEN 1 AND 99999)
);
ALTER TABLE public.display_id_counters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.display_id_counters FROM PUBLIC,anon,authenticated;

ALTER TABLE public.patients ADD COLUMN display_id text NULL;
ALTER TABLE public.appointments ADD COLUMN display_id text NULL;
ALTER TABLE public.consultations ADD COLUMN display_id text NULL;

CREATE FUNCTION security.allocate_display_id(p_entity_type text,p_created_at timestamptz)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE
  v_year_month text;
  v_visible_month text;
  v_prefix text;
  v_value integer;
BEGIN
  IF p_created_at IS NULL THEN RAISE EXCEPTION 'DISPLAY_ID_CREATED_AT_REQUIRED' USING ERRCODE='22023'; END IF;
  v_prefix:=CASE p_entity_type WHEN 'patients' THEN 'P' WHEN 'appointments' THEN 'A'
    WHEN 'consultations' THEN 'C' ELSE NULL END;
  IF v_prefix IS NULL THEN RAISE EXCEPTION 'DISPLAY_ID_ENTITY_UNSUPPORTED' USING ERRCODE='22023'; END IF;
  v_year_month:=to_char(p_created_at AT TIME ZONE 'Africa/Cairo','YYYYMM');
  v_visible_month:=to_char(p_created_at AT TIME ZONE 'Africa/Cairo','MMYY');

  INSERT INTO public.display_id_counters(entity_type,year_month,current_value)
  VALUES(p_entity_type,v_year_month,1)
  ON CONFLICT(entity_type,year_month) DO UPDATE
    SET current_value=public.display_id_counters.current_value+1
    WHERE public.display_id_counters.current_value<99999
  RETURNING current_value INTO v_value;

  IF v_value IS NULL THEN
    RAISE EXCEPTION 'DISPLAY_ID_MONTHLY_SEQUENCE_EXHAUSTED: %/%',p_entity_type,v_year_month
      USING ERRCODE='22023';
  END IF;
  RETURN v_prefix||'-'||v_visible_month||'-'||lpad(v_value::text,5,'0');
END
$function$;
REVOKE ALL ON FUNCTION security.allocate_display_id(text,timestamptz) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION security.assign_display_id()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_assigned_at timestamptz;
BEGIN
  IF NEW.display_id IS NOT NULL THEN
    RAISE EXCEPTION 'DISPLAY_ID_CLIENT_ASSIGNMENT_FORBIDDEN' USING ERRCODE='42501';
  END IF;
  -- clock_timestamp() is server-authoritative and reflects the actual wall-clock
  -- instant at this insert (unlike a client value or transaction-start now()).
  v_assigned_at:=clock_timestamp();
  NEW.created_at:=v_assigned_at;
  NEW.display_id:=security.allocate_display_id(TG_TABLE_NAME,v_assigned_at);
  RETURN NEW;
END
$function$;
REVOKE ALL ON FUNCTION security.assign_display_id() FROM PUBLIC,anon,authenticated;

-- Deterministic historical assignment within each Cairo-local creation month.
WITH ranked AS(
  SELECT id,to_char(created_at AT TIME ZONE 'Africa/Cairo','MMYY') visible_month,
         row_number() OVER(PARTITION BY to_char(created_at AT TIME ZONE 'Africa/Cairo','YYYYMM')
                           ORDER BY created_at,id) serial
  FROM public.patients
)
UPDATE public.patients target SET display_id='P-'||ranked.visible_month||'-'||lpad(ranked.serial::text,5,'0')
FROM ranked WHERE target.id=ranked.id;

WITH ranked AS(
  SELECT id,to_char(created_at AT TIME ZONE 'Africa/Cairo','MMYY') visible_month,
         row_number() OVER(PARTITION BY to_char(created_at AT TIME ZONE 'Africa/Cairo','YYYYMM')
                           ORDER BY created_at,id) serial
  FROM public.appointments
)
UPDATE public.appointments target SET display_id='A-'||ranked.visible_month||'-'||lpad(ranked.serial::text,5,'0')
FROM ranked WHERE target.id=ranked.id;

WITH ranked AS(
  SELECT id,to_char(created_at AT TIME ZONE 'Africa/Cairo','MMYY') visible_month,
         row_number() OVER(PARTITION BY to_char(created_at AT TIME ZONE 'Africa/Cairo','YYYYMM')
                           ORDER BY created_at,id) serial
  FROM public.consultations
)
UPDATE public.consultations target SET display_id='C-'||ranked.visible_month||'-'||lpad(ranked.serial::text,5,'0')
FROM ranked WHERE target.id=ranked.id;

INSERT INTO public.display_id_counters(entity_type,year_month,current_value)
SELECT entity_type,year_month,count(*)::integer FROM(
  SELECT 'patients'::text entity_type,to_char(created_at AT TIME ZONE 'Africa/Cairo','YYYYMM') year_month FROM public.patients
  UNION ALL SELECT 'appointments',to_char(created_at AT TIME ZONE 'Africa/Cairo','YYYYMM') FROM public.appointments
  UNION ALL SELECT 'consultations',to_char(created_at AT TIME ZONE 'Africa/Cairo','YYYYMM') FROM public.consultations
) rows GROUP BY entity_type,year_month;

ALTER TABLE public.patients ALTER COLUMN display_id SET NOT NULL;
ALTER TABLE public.appointments ALTER COLUMN display_id SET NOT NULL;
ALTER TABLE public.consultations ALTER COLUMN display_id SET NOT NULL;
ALTER TABLE public.patients ADD CONSTRAINT patients_display_id_uq UNIQUE(display_id),
  ADD CONSTRAINT patients_display_id_format_ck CHECK(display_id~'^P-[0-9]{4}-[0-9]{5}$');
ALTER TABLE public.appointments ADD CONSTRAINT appointments_display_id_uq UNIQUE(display_id),
  ADD CONSTRAINT appointments_display_id_format_ck CHECK(display_id~'^A-[0-9]{4}-[0-9]{5}$');
ALTER TABLE public.consultations ADD CONSTRAINT consultations_display_id_uq UNIQUE(display_id),
  ADD CONSTRAINT consultations_display_id_format_ck CHECK(display_id~'^C-[0-9]{4}-[0-9]{5}$');

CREATE TRIGGER patients_assign_display_id BEFORE INSERT ON public.patients FOR EACH ROW EXECUTE FUNCTION security.assign_display_id();
CREATE TRIGGER appointments_assign_display_id BEFORE INSERT ON public.appointments FOR EACH ROW EXECUTE FUNCTION security.assign_display_id();
CREATE TRIGGER consultations_assign_display_id BEFORE INSERT ON public.consultations FOR EACH ROW EXECUTE FUNCTION security.assign_display_id();

CREATE FUNCTION security.reject_display_id_change()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp
AS $function$
BEGIN
  IF NEW.display_id IS DISTINCT FROM OLD.display_id OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'DISPLAY_ID_AND_CREATED_AT_IMMUTABLE' USING ERRCODE='22023';
  END IF;
  RETURN NEW;
END
$function$;
REVOKE ALL ON FUNCTION security.reject_display_id_change() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER patients_display_id_immutable BEFORE UPDATE OF display_id,created_at ON public.patients FOR EACH ROW EXECUTE FUNCTION security.reject_display_id_change();
CREATE TRIGGER appointments_display_id_immutable BEFORE UPDATE OF display_id,created_at ON public.appointments FOR EACH ROW EXECUTE FUNCTION security.reject_display_id_change();
CREATE TRIGGER consultations_display_id_immutable BEFORE UPDATE OF display_id,created_at ON public.consultations FOR EACH ROW EXECUTE FUNCTION security.reject_display_id_change();

-- Preserve both appointment implementations; wrappers add display_id only.
ALTER FUNCTION security.appointment_projection(uuid) RENAME TO appointment_projection_036_base;
REVOKE ALL ON FUNCTION security.appointment_projection_036_base(uuid) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION security.appointment_projection(p_appointment_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_base jsonb;v_display_id text;
BEGIN
  v_base:=security.appointment_projection_036_base(p_appointment_id);
  SELECT appointment.display_id INTO v_display_id FROM public.appointments appointment
   WHERE appointment.id=p_appointment_id;
  IF v_base IS NULL THEN RETURN NULL; END IF;
  RETURN v_base||jsonb_build_object('display_id',v_display_id);
END
$function$;
REVOKE ALL ON FUNCTION security.appointment_projection(uuid) FROM PUBLIC,anon,authenticated;

ALTER FUNCTION public.get_appointments() RENAME TO get_appointments_036_base;
ALTER FUNCTION public.get_appointments_036_base() SET SCHEMA security;
REVOKE ALL ON FUNCTION security.get_appointments_036_base() FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.get_appointments()
RETURNS TABLE(id uuid,display_id text,patient_id uuid,patient text,doctor_id uuid,doctor text,
  "date" date,"time" text,"type" text,"status" text,"condition" text,notes text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
SELECT base.id,appointment.display_id,base.patient_id,base.patient,base.doctor_id,base.doctor,
  base."date",base."time",base."type",base."status",base."condition",base.notes
FROM security.get_appointments_036_base() WITH ORDINALITY AS base(
  id,patient_id,patient,doctor_id,doctor,"date","time","type","status","condition",notes,ordinality)
LEFT JOIN public.appointments appointment ON appointment.id=base.id
ORDER BY base.ordinality
$function$;
REVOKE ALL ON FUNCTION public.get_appointments() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_appointments() TO authenticated;

-- Preserve the complete pre-036 implementation and enrich only its JSON result.
ALTER FUNCTION public.get_or_initialize_consultation(uuid) RENAME TO get_or_initialize_consultation_036_base;
ALTER FUNCTION public.get_or_initialize_consultation_036_base(uuid) SET SCHEMA security;
REVOKE ALL ON FUNCTION security.get_or_initialize_consultation_036_base(uuid) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.get_or_initialize_consultation(p_patient_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_result jsonb;v_display_id text;
BEGIN
  v_result:=security.get_or_initialize_consultation_036_base(p_patient_id);
  IF v_result->>'consultationId' IS NOT NULL THEN
    SELECT display_id INTO v_display_id FROM public.consultations WHERE id=(v_result->>'consultationId')::uuid;
  END IF;
  RETURN v_result||jsonb_build_object('displayId',v_display_id);
END
$function$;
REVOKE ALL ON FUNCTION public.get_or_initialize_consultation(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_or_initialize_consultation(uuid) TO authenticated;

ALTER FUNCTION public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)
  RENAME TO save_current_consultation_036_base;
ALTER FUNCTION public.save_current_consultation_036_base(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)
  SET SCHEMA security;
REVOKE ALL ON FUNCTION security.save_current_consultation_036_base(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)
  FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.save_current_consultation(p_patient_id uuid,p_tooth_data jsonb,p_version integer,
  p_dental_state_version integer,p_session_note text,p_session_note_supplied boolean,
  p_symptoms_snapshot jsonb,p_symptoms_supplied boolean,p_clinical_findings_snapshot jsonb,
  p_clinical_findings_supplied boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_result jsonb;v_display_id text;
BEGIN
  v_result:=security.save_current_consultation_036_base(p_patient_id,p_tooth_data,p_version,
    p_dental_state_version,p_session_note,p_session_note_supplied,p_symptoms_snapshot,p_symptoms_supplied,
    p_clinical_findings_snapshot,p_clinical_findings_supplied);
  SELECT display_id INTO v_display_id FROM public.consultations WHERE id=(v_result->>'consultationId')::uuid;
  RETURN v_result||jsonb_build_object('displayId',v_display_id);
END
$function$;
REVOKE ALL ON FUNCTION public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean) TO authenticated;

-- ALTER FUNCTION preserves the base function OID, so existing stored callers
-- would otherwise remain bound to the base. Recreate only those callers from
-- PostgreSQL's own canonical definitions so name resolution binds them to the
-- new public wrapper without changing their bodies, properties, or grants.
DO $rebind_save_dependents$
DECLARE dependent_function regprocedure;v_definition text;
BEGIN
  FOR dependent_function IN
    SELECT dependent.oid::regprocedure
    FROM pg_depend dependency JOIN pg_proc dependent ON dependent.oid=dependency.objid
    WHERE dependency.classid='pg_proc'::regclass
      AND dependency.refobjid='security.save_current_consultation_036_base(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)'::regprocedure
      AND dependent.oid<>'public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)'::regprocedure
      AND dependency.deptype='n'
  LOOP
    v_definition:=pg_get_functiondef(dependent_function);
    EXECUTE v_definition;
  END LOOP;
  IF EXISTS(
    SELECT 1 FROM pg_depend dependency JOIN pg_proc dependent ON dependent.oid=dependency.objid
    WHERE dependency.classid='pg_proc'::regclass
      AND dependency.refobjid='security.save_current_consultation_036_base(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)'::regprocedure
      AND dependent.oid<>'public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)'::regprocedure
      AND dependency.deptype='n'
  ) THEN RAISE EXCEPTION 'MIGRATION_036_SAVE_DEPENDENT_REBIND_FAILED'; END IF;
END
$rebind_save_dependents$;

-- Preserve final pre-036 history wrappers (including all clinical/report/lab/
-- prescription enrichment) and add only stored display-ID keys.
ALTER FUNCTION public.get_patient_consultation_history(uuid) RENAME TO get_patient_consultation_history_036_base;
ALTER FUNCTION public.get_patient_consultation_history_036_base(uuid) SET SCHEMA security;
REVOKE ALL ON FUNCTION security.get_patient_consultation_history_036_base(uuid) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.get_patient_consultation_history(p_patient_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_base jsonb;v_result jsonb;
BEGIN
  v_base:=security.get_patient_consultation_history_036_base(p_patient_id);
  SELECT coalesce(jsonb_agg(item.value||jsonb_build_object(
    'patientDisplayId',patient.display_id,'consultationDisplayId',consultation.display_id
  ) ORDER BY item.ordinality),'[]'::jsonb) INTO v_result
  FROM jsonb_array_elements(v_base) WITH ORDINALITY item(value,ordinality)
  LEFT JOIN public.consultations consultation ON consultation.id=nullif(item.value->>'consultationId','')::uuid
  LEFT JOIN public.patients patient ON patient.id=consultation.patient_id;
  RETURN v_result;
END
$function$;
REVOKE ALL ON FUNCTION public.get_patient_consultation_history(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_patient_consultation_history(uuid) TO authenticated;

ALTER FUNCTION public.list_doctor_consultation_history() RENAME TO list_doctor_consultation_history_036_base;
ALTER FUNCTION public.list_doctor_consultation_history_036_base() SET SCHEMA security;
REVOKE ALL ON FUNCTION security.list_doctor_consultation_history_036_base() FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.list_doctor_consultation_history()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_base jsonb;v_result jsonb;
BEGIN
  v_base:=security.list_doctor_consultation_history_036_base();
  SELECT coalesce(jsonb_agg(item.value||jsonb_build_object(
    'patientDisplayId',patient.display_id,'consultationDisplayId',consultation.display_id
  ) ORDER BY item.ordinality),'[]'::jsonb) INTO v_result
  FROM jsonb_array_elements(v_base) WITH ORDINALITY item(value,ordinality)
  LEFT JOIN public.consultations consultation ON consultation.id=nullif(item.value->>'consultationId','')::uuid
  LEFT JOIN public.patients patient ON patient.id=consultation.patient_id;
  RETURN v_result;
END
$function$;
REVOKE ALL ON FUNCTION public.list_doctor_consultation_history() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.list_doctor_consultation_history() TO authenticated;

-- Enrich financial projections centrally; all dependent financial RPCs retain their behavior.
ALTER FUNCTION security.financial_billing_projection(uuid) RENAME TO financial_billing_projection_036_base;
REVOKE ALL ON FUNCTION security.financial_billing_projection_036_base(uuid) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION security.financial_billing_projection(p_consultation_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_result jsonb;v_consultation_display text;v_patient_display text;
BEGIN
  v_result:=security.financial_billing_projection_036_base(p_consultation_id);
  SELECT consultation.display_id,patient.display_id INTO v_consultation_display,v_patient_display
  FROM public.consultations consultation JOIN public.patients patient ON patient.id=consultation.patient_id
  WHERE consultation.id=p_consultation_id;
  IF v_result IS NULL THEN RETURN NULL; END IF;
  RETURN v_result||jsonb_build_object('consultationDisplayId',v_consultation_display,
    'patient',(v_result->'patient')||jsonb_build_object('displayId',v_patient_display));
END
$function$;
REVOKE ALL ON FUNCTION security.financial_billing_projection(uuid) FROM PUBLIC,anon,authenticated;

DO $rebind_financial_dependents$
DECLARE dependent_function regprocedure;v_definition text;
BEGIN
  FOR dependent_function IN
    SELECT dependent.oid::regprocedure
    FROM pg_depend dependency JOIN pg_proc dependent ON dependent.oid=dependency.objid
    WHERE dependency.classid='pg_proc'::regclass
      AND dependency.refobjid='security.financial_billing_projection_036_base(uuid)'::regprocedure
      AND dependent.oid<>'security.financial_billing_projection(uuid)'::regprocedure
      AND dependency.deptype='n'
  LOOP
    v_definition:=pg_get_functiondef(dependent_function);
    EXECUTE v_definition;
  END LOOP;
  IF EXISTS(
    SELECT 1 FROM pg_depend dependency JOIN pg_proc dependent ON dependent.oid=dependency.objid
    WHERE dependency.classid='pg_proc'::regclass
      AND dependency.refobjid='security.financial_billing_projection_036_base(uuid)'::regprocedure
      AND dependent.oid<>'security.financial_billing_projection(uuid)'::regprocedure
      AND dependency.deptype='n'
  ) THEN RAISE EXCEPTION 'MIGRATION_036_FINANCIAL_DEPENDENT_REBIND_FAILED'; END IF;
END
$rebind_financial_dependents$;

-- Preserve lab authorization, validation, filters, ordering, money formatting,
-- and item shape; enrich each returned transaction by its canonical UUID.
ALTER FUNCTION public.list_lab_transactions(uuid,timestamptz,timestamptz) RENAME TO list_lab_transactions_036_base;
ALTER FUNCTION public.list_lab_transactions_036_base(uuid,timestamptz,timestamptz) SET SCHEMA security;
REVOKE ALL ON FUNCTION security.list_lab_transactions_036_base(uuid,timestamptz,timestamptz) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.list_lab_transactions(p_lab_id uuid,p_date_from timestamptz,p_date_to timestamptz)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $function$
DECLARE v_base jsonb;v_result jsonb;
BEGIN
  v_base:=security.list_lab_transactions_036_base(p_lab_id,p_date_from,p_date_to);
  SELECT coalesce(jsonb_agg(item.value||jsonb_build_object(
    'consultationDisplayId',consultation.display_id) ORDER BY item.ordinality),'[]'::jsonb) INTO v_result
  FROM jsonb_array_elements(v_base) WITH ORDINALITY item(value,ordinality)
  LEFT JOIN public.consultations consultation ON consultation.id=nullif(item.value->>'consultationId','')::uuid;
  RETURN v_result;
END
$function$;
REVOKE ALL ON FUNCTION public.list_lab_transactions(uuid,timestamptz,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.list_lab_transactions(uuid,timestamptz,timestamptz) TO authenticated;

-- Rebind any stored SQL-function dependencies left on renamed JSON bases.
-- PL/pgSQL callers resolve their schema-qualified textual call at execution and
-- therefore select the new wrapper; SQL functions may carry catalog dependencies.
DO $rebind_json_dependents$
DECLARE v_base oid;v_wrapper oid;v_dependent oid;v_pair text[];
BEGIN
  FOREACH v_pair SLICE 1 IN ARRAY ARRAY[
    ARRAY['security.appointment_projection_036_base(uuid)','security.appointment_projection(uuid)'],
    ARRAY['security.get_appointments_036_base()','public.get_appointments()'],
    ARRAY['security.get_or_initialize_consultation_036_base(uuid)','public.get_or_initialize_consultation(uuid)'],
    ARRAY['security.get_patient_consultation_history_036_base(uuid)','public.get_patient_consultation_history(uuid)'],
    ARRAY['security.list_doctor_consultation_history_036_base()','public.list_doctor_consultation_history()'],
    ARRAY['security.list_lab_transactions_036_base(uuid,timestamp with time zone,timestamp with time zone)',
          'public.list_lab_transactions(uuid,timestamp with time zone,timestamp with time zone)']
  ] LOOP
    v_base:=to_regprocedure(v_pair[1]);v_wrapper:=to_regprocedure(v_pair[2]);
    FOR v_dependent IN SELECT p.oid FROM pg_depend d JOIN pg_proc p ON p.oid=d.objid
      WHERE d.classid='pg_proc'::regclass AND d.refobjid=v_base AND d.deptype='n' AND p.oid<>v_wrapper
    LOOP EXECUTE pg_get_functiondef(v_dependent); END LOOP;
    IF EXISTS(SELECT 1 FROM pg_depend d JOIN pg_proc p ON p.oid=d.objid
      WHERE d.classid='pg_proc'::regclass AND d.refobjid=v_base AND d.deptype='n' AND p.oid<>v_wrapper) THEN
      RAISE EXCEPTION 'MIGRATION_036_JSON_DEPENDENT_REBIND_FAILED: %',v_pair[1];
    END IF;
  END LOOP;
END
$rebind_json_dependents$;

COMMIT;
