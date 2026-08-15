-- Migration 019: authoritative structured per-tooth clinical findings.
-- No legacy rows are backfilled; NULL retains its explicit legacy meaning.

BEGIN;

CREATE OR REPLACE FUNCTION security.clinical_findings_snapshot_valid(p_findings jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT CASE
      WHEN p_findings IS NULL THEN true
      WHEN jsonb_typeof(p_findings) <> 'array' THEN false
      ELSE (
        jsonb_array_length(p_findings) <= 32
        AND NOT EXISTS (
            SELECT 1
              FROM jsonb_array_elements(p_findings) AS finding(value)
             WHERE jsonb_typeof(finding.value) <> 'object'
                OR NOT (finding.value ?& ARRAY['toothId','toothStatus','symptoms','toothNote'])
                OR EXISTS (
                    SELECT 1 FROM jsonb_object_keys(finding.value) AS key(value)
                     WHERE key.value <> ALL(ARRAY['toothId','toothStatus','symptoms','toothNote'])
                )
                OR jsonb_typeof(finding.value -> 'toothId') <> 'string'
                OR (finding.value ->> 'toothId') !~ '^[1-4][1-8]$'
                OR jsonb_typeof(finding.value -> 'toothStatus') <> 'string'
                OR (finding.value ->> 'toothStatus') NOT IN ('healthy','problem','treated','missing')
                OR jsonb_typeof(finding.value -> 'symptoms') <> 'array'
                OR jsonb_array_length(finding.value -> 'symptoms') > 100
                OR EXISTS (
                    SELECT 1 FROM jsonb_array_elements(finding.value -> 'symptoms') AS symptom(value)
                     WHERE jsonb_typeof(symptom.value) <> 'string'
                        OR btrim(symptom.value #>> '{}') = ''
                        OR length(symptom.value #>> '{}') > 250
                )
                OR (SELECT count(*) FROM jsonb_array_elements(finding.value -> 'symptoms')) <>
                   (SELECT count(DISTINCT lower(btrim(symptom.value #>> '{}')))
                      FROM jsonb_array_elements(finding.value -> 'symptoms') AS symptom(value))
                OR jsonb_typeof(finding.value -> 'toothNote') <> 'string'
                OR length(finding.value ->> 'toothNote') > 10000
        )
        AND (SELECT count(*) FROM jsonb_array_elements(p_findings)) =
            (SELECT count(DISTINCT finding.value ->> 'toothId')
               FROM jsonb_array_elements(p_findings) AS finding(value))
      )
    END
$function$;

REVOKE ALL ON FUNCTION security.clinical_findings_snapshot_valid(jsonb) FROM PUBLIC, anon, authenticated;

ALTER TABLE public.consultations
    ADD COLUMN clinical_findings_snapshot jsonb NULL;

ALTER TABLE public.consultations
    ADD CONSTRAINT consultations_clinical_findings_snapshot_ck
    CHECK (security.clinical_findings_snapshot_valid(clinical_findings_snapshot));

CREATE OR REPLACE FUNCTION public.save_current_consultation(
    p_patient_id uuid,
    p_tooth_data jsonb,
    p_version integer,
    p_dental_state_version integer,
    p_session_note text,
    p_session_note_supplied boolean,
    p_symptoms_snapshot jsonb,
    p_symptoms_supplied boolean,
    p_clinical_findings_snapshot jsonb,
    p_clinical_findings_supplied boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_result jsonb;
    v_consultation_id uuid;
    v_effective_symptoms jsonb := p_symptoms_snapshot;
    v_effective_symptoms_supplied boolean := p_symptoms_supplied;
    v_saved_findings jsonb;
BEGIN
    IF p_clinical_findings_supplied THEN
        IF p_clinical_findings_snapshot IS NULL
           OR NOT security.clinical_findings_snapshot_valid(p_clinical_findings_snapshot) THEN
            RAISE EXCEPTION 'CONSULTATION_CLINICAL_FINDINGS_INVALID' USING ERRCODE = '22023';
        END IF;

        IF p_tooth_data IS NULL OR jsonb_typeof(p_tooth_data) <> 'object'
           OR EXISTS (
               SELECT 1
                 FROM jsonb_array_elements(p_clinical_findings_snapshot) AS finding(value)
                WHERE NOT (p_tooth_data ? (finding.value ->> 'toothId'))
                   OR jsonb_typeof(p_tooth_data -> (finding.value ->> 'toothId')) <> 'object'
                   OR jsonb_typeof(p_tooth_data -> (finding.value ->> 'toothId') -> 'status') <> 'string'
                   OR jsonb_typeof(p_tooth_data -> (finding.value ->> 'toothId') -> 'notes') <> 'string'
                   OR (p_tooth_data -> (finding.value ->> 'toothId') ->> 'status')
                      IS DISTINCT FROM (finding.value ->> 'toothStatus')
                   OR (p_tooth_data -> (finding.value ->> 'toothId') ->> 'notes')
                      IS DISTINCT FROM (finding.value ->> 'toothNote')
           ) THEN
            RAISE EXCEPTION 'CONSULTATION_CLINICAL_FINDINGS_TOOTH_DATA_MISMATCH'
                USING ERRCODE = '22023';
        END IF;

        SELECT coalesce(jsonb_agg(to_jsonb(union_symptom.value)
                                  ORDER BY lower(union_symptom.value), union_symptom.value), '[]'::jsonb)
          INTO v_effective_symptoms
          FROM (
              SELECT DISTINCT ON (lower(btrim(symptom.value #>> '{}')))
                     btrim(symptom.value #>> '{}') AS value
                FROM jsonb_array_elements(p_clinical_findings_snapshot) AS finding(value)
                CROSS JOIN LATERAL jsonb_array_elements(finding.value -> 'symptoms') AS symptom(value)
               ORDER BY lower(btrim(symptom.value #>> '{}')), btrim(symptom.value #>> '{}')
          ) AS union_symptom;
        v_effective_symptoms_supplied := true;
    END IF;

    -- Migration 018 remains the single authority for appointment ownership,
    -- row locks, both versions, dental state, note, flat symptom validation and audit.
    v_result := public.save_current_consultation(
        p_patient_id, p_tooth_data, p_version, p_dental_state_version,
        p_session_note, p_session_note_supplied,
        v_effective_symptoms, v_effective_symptoms_supplied
    );
    v_consultation_id := (v_result ->> 'consultationId')::uuid;

    IF p_clinical_findings_supplied THEN
        UPDATE public.consultations AS consultation
           SET clinical_findings_snapshot = p_clinical_findings_snapshot
         WHERE consultation.id = v_consultation_id;
    END IF;

    SELECT consultation.clinical_findings_snapshot
      INTO v_saved_findings
      FROM public.consultations AS consultation
     WHERE consultation.id = v_consultation_id;

    RETURN v_result || jsonb_build_object('clinicalFindings', v_saved_findings);
END
$function$;

-- The 8-parameter implementation is retained only for the new wrapper's internal call.
REVOKE ALL ON FUNCTION public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean) FROM authenticated;
REVOKE ALL ON FUNCTION public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean) FROM authenticated;

REVOKE ALL ON FUNCTION public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean) TO authenticated;

-- Preserve deployed history algorithms privately; public wrappers only enrich output.
ALTER FUNCTION public.get_patient_consultation_history(uuid)
    RENAME TO get_patient_consultation_history_base;
ALTER FUNCTION public.get_patient_consultation_history_base(uuid)
    SET SCHEMA security;
REVOKE ALL ON FUNCTION security.get_patient_consultation_history_base(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_patient_consultation_history(p_patient_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_base jsonb;
    v_result jsonb;
BEGIN
    v_base := security.get_patient_consultation_history_base(p_patient_id);
    SELECT coalesce(jsonb_agg(item.value || jsonb_build_object(
               'clinicalFindings', consultation.clinical_findings_snapshot
           ) ORDER BY item.ordinality), '[]'::jsonb)
      INTO v_result
      FROM jsonb_array_elements(v_base) WITH ORDINALITY AS item(value, ordinality)
      LEFT JOIN public.consultations AS consultation
        ON consultation.id = NULLIF(item.value ->> 'consultationId', '')::uuid;
    RETURN v_result;
END
$function$;

ALTER FUNCTION public.list_doctor_consultation_history()
    RENAME TO list_doctor_consultation_history_base;
ALTER FUNCTION public.list_doctor_consultation_history_base()
    SET SCHEMA security;
REVOKE ALL ON FUNCTION security.list_doctor_consultation_history_base() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.list_doctor_consultation_history()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_base jsonb;
    v_result jsonb;
BEGIN
    v_base := security.list_doctor_consultation_history_base();
    SELECT coalesce(jsonb_agg(item.value || jsonb_build_object(
               'clinicalFindings', consultation.clinical_findings_snapshot
           ) ORDER BY item.ordinality), '[]'::jsonb)
      INTO v_result
      FROM jsonb_array_elements(v_base) WITH ORDINALITY AS item(value, ordinality)
      LEFT JOIN public.consultations AS consultation
        ON consultation.id = NULLIF(item.value ->> 'consultationId', '')::uuid;
    RETURN v_result;
END
$function$;

REVOKE ALL ON FUNCTION public.get_patient_consultation_history(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_patient_consultation_history(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_patient_consultation_history(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.list_doctor_consultation_history() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_doctor_consultation_history() FROM anon;
GRANT EXECUTE ON FUNCTION public.list_doctor_consultation_history() TO authenticated;

COMMIT;
