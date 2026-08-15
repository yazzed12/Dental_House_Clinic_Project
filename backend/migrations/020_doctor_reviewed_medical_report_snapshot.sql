-- Migration 020: immutable doctor-reviewed structured medical report snapshots.
-- Legacy reports remain NULL and are not backfilled.

BEGIN;

ALTER TABLE public.clinical_reports
    ADD COLUMN report_snapshot jsonb NULL,
    ADD COLUMN snapshot_version integer NULL,
    ADD COLUMN reviewed_by uuid NULL,
    ADD COLUMN reviewed_at timestamptz NULL,
    ADD COLUMN finalized_at timestamptz NULL;

ALTER TABLE public.clinical_reports
    ADD CONSTRAINT clinical_reports_reviewed_by_fk
    FOREIGN KEY (reviewed_by) REFERENCES public.users(id);

CREATE OR REPLACE FUNCTION security.medical_report_nullable_bounded_string(
    p_value jsonb, p_max_length integer
)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT jsonb_typeof(p_value) = 'null'
        OR (jsonb_typeof(p_value) = 'string' AND length(p_value #>> '{}') <= p_max_length)
$function$;

CREATE OR REPLACE FUNCTION security.medical_report_icd10_valid(p_value jsonb)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT jsonb_typeof(p_value) = 'null' OR (
        jsonb_typeof(p_value) = 'object'
        AND p_value ?& ARRAY['code','display']
        AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p_value) AS key(value)
                         WHERE key.value <> ALL(ARRAY['code','display']))
        AND jsonb_typeof(p_value -> 'code') = 'string'
        AND btrim(p_value ->> 'code') <> '' AND length(p_value ->> 'code') <= 100
        AND jsonb_typeof(p_value -> 'display') = 'string'
        AND btrim(p_value ->> 'display') <> '' AND length(p_value ->> 'display') <= 1000
    )
$function$;

CREATE OR REPLACE FUNCTION security.medical_report_doctor_valid(p_value jsonb)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT jsonb_typeof(p_value) = 'object'
       AND p_value ?& ARRAY['id','name','specialty','licenseNumber']
       AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p_value) AS key(value)
                        WHERE key.value <> ALL(ARRAY['id','name','specialty','licenseNumber']))
       AND jsonb_typeof(p_value -> 'id') = 'string'
       AND pg_input_is_valid(p_value ->> 'id', 'uuid')
       AND jsonb_typeof(p_value -> 'name') = 'string'
       AND btrim(p_value ->> 'name') <> '' AND length(p_value ->> 'name') <= 500
       AND security.medical_report_nullable_bounded_string(p_value -> 'specialty', 500)
       AND security.medical_report_nullable_bounded_string(p_value -> 'licenseNumber', 500)
$function$;

CREATE OR REPLACE FUNCTION security.medical_report_clinic_valid(p_value jsonb)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT jsonb_typeof(p_value) = 'object'
       AND p_value ?& ARRAY['name','contact']
       AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p_value) AS key(value)
                        WHERE key.value <> ALL(ARRAY['name','contact']))
       AND security.medical_report_nullable_bounded_string(p_value -> 'name', 500)
       AND jsonb_typeof(p_value -> 'contact') = 'object'
       AND length((p_value -> 'contact')::text) <= 10000
$function$;

CREATE OR REPLACE FUNCTION security.medical_report_review_valid(p_value jsonb)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT jsonb_typeof(p_value) = 'object'
       AND p_value ?& ARRAY['reviewedBy','reviewedAt','electronicSignatureDisplay']
       AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p_value) AS key(value)
                        WHERE key.value <> ALL(ARRAY['reviewedBy','reviewedAt','electronicSignatureDisplay']))
       AND jsonb_typeof(p_value -> 'reviewedBy') = 'string'
       AND pg_input_is_valid(p_value ->> 'reviewedBy', 'uuid')
       AND jsonb_typeof(p_value -> 'reviewedAt') = 'string'
       AND pg_input_is_valid(p_value ->> 'reviewedAt', 'timestamp with time zone')
       AND security.medical_report_nullable_bounded_string(
           p_value -> 'electronicSignatureDisplay', 2000)
$function$;

CREATE OR REPLACE FUNCTION security.medical_report_snapshot_valid(p_snapshot jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT CASE
      WHEN p_snapshot IS NULL THEN true
      WHEN jsonb_typeof(p_snapshot) <> 'object'
        OR NOT (p_snapshot ?& ARRAY[
            'schemaVersion','patient','consultation','clinicalAssessments',
            'performedProcedures','clinicalSummary','doctor','clinic','review','finalNarrative'
        ])
        OR EXISTS (
            SELECT 1 FROM jsonb_object_keys(p_snapshot) AS key(value)
             WHERE key.value <> ALL(ARRAY[
                'schemaVersion','patient','consultation','clinicalAssessments',
                'performedProcedures','clinicalSummary','doctor','clinic','review','finalNarrative'
             ])
        )
        OR p_snapshot -> 'schemaVersion' <> '1'::jsonb
        OR jsonb_typeof(p_snapshot -> 'patient') <> 'object'
        OR jsonb_typeof(p_snapshot -> 'consultation') <> 'object'
        OR jsonb_typeof(p_snapshot -> 'clinicalAssessments') <> 'array'
        OR jsonb_typeof(p_snapshot -> 'performedProcedures') <> 'array'
        OR jsonb_typeof(p_snapshot -> 'doctor') <> 'object'
        OR jsonb_typeof(p_snapshot -> 'clinic') <> 'object'
        OR jsonb_typeof(p_snapshot -> 'review') <> 'object'
        OR jsonb_typeof(p_snapshot -> 'clinicalSummary') <> 'string'
        OR length(p_snapshot ->> 'clinicalSummary') > 50000
        OR jsonb_typeof(p_snapshot -> 'finalNarrative') <> 'string'
        OR btrim(p_snapshot ->> 'finalNarrative') = ''
        OR length(p_snapshot ->> 'finalNarrative') > 200000
      THEN false
      ELSE
        -- Patient snapshot.
        (p_snapshot -> 'patient') ?& ARRAY['id','name','dateOfBirth','ageAtExamination','gender']
        AND NOT EXISTS (
            SELECT 1 FROM jsonb_object_keys(p_snapshot -> 'patient') AS key(value)
             WHERE key.value <> ALL(ARRAY['id','name','dateOfBirth','ageAtExamination','gender'])
        )
        AND jsonb_typeof(p_snapshot -> 'patient' -> 'id') = 'string'
        AND pg_input_is_valid(p_snapshot -> 'patient' ->> 'id', 'uuid')
        AND jsonb_typeof(p_snapshot -> 'patient' -> 'name') = 'string'
        AND btrim(p_snapshot -> 'patient' ->> 'name') <> ''
        AND length(p_snapshot -> 'patient' ->> 'name') <= 500
        AND (
            jsonb_typeof(p_snapshot -> 'patient' -> 'dateOfBirth') = 'null'
            OR (jsonb_typeof(p_snapshot -> 'patient' -> 'dateOfBirth') = 'string'
                AND pg_input_is_valid(p_snapshot -> 'patient' ->> 'dateOfBirth', 'date'))
        )
        AND (
            jsonb_typeof(p_snapshot -> 'patient' -> 'ageAtExamination') = 'null'
            OR (jsonb_typeof(p_snapshot -> 'patient' -> 'ageAtExamination') = 'number'
                AND (p_snapshot -> 'patient' ->> 'ageAtExamination') ~ '^[0-9]+$'
                AND (p_snapshot -> 'patient' ->> 'ageAtExamination')::numeric <= 150)
        )
        AND (
            jsonb_typeof(p_snapshot -> 'patient' -> 'gender') = 'null'
            OR (jsonb_typeof(p_snapshot -> 'patient' -> 'gender') = 'string'
                AND length(p_snapshot -> 'patient' ->> 'gender') <= 100)
        )
        -- Consultation snapshot.
        AND (p_snapshot -> 'consultation') ?& ARRAY['id','appointmentId','examinationDate']
        AND NOT EXISTS (
            SELECT 1 FROM jsonb_object_keys(p_snapshot -> 'consultation') AS key(value)
             WHERE key.value <> ALL(ARRAY['id','appointmentId','examinationDate'])
        )
        AND jsonb_typeof(p_snapshot -> 'consultation' -> 'id') = 'string'
        AND pg_input_is_valid(p_snapshot -> 'consultation' ->> 'id', 'uuid')
        AND (
            jsonb_typeof(p_snapshot -> 'consultation' -> 'appointmentId') = 'null'
            OR (jsonb_typeof(p_snapshot -> 'consultation' -> 'appointmentId') = 'string'
                AND pg_input_is_valid(p_snapshot -> 'consultation' ->> 'appointmentId', 'uuid'))
        )
        AND jsonb_typeof(p_snapshot -> 'consultation' -> 'examinationDate') = 'string'
        AND pg_input_is_valid(p_snapshot -> 'consultation' ->> 'examinationDate', 'timestamp with time zone')
        -- Per-tooth facts and confirmed assessments.
        AND jsonb_array_length(p_snapshot -> 'clinicalAssessments') <= 32
        AND (SELECT count(*) FROM jsonb_array_elements(p_snapshot -> 'clinicalAssessments')) =
            (SELECT count(DISTINCT item.value ->> 'toothId')
               FROM jsonb_array_elements(p_snapshot -> 'clinicalAssessments') AS item(value))
        AND NOT EXISTS (
            SELECT 1
              FROM jsonb_array_elements(p_snapshot -> 'clinicalAssessments') AS item(value)
             WHERE jsonb_typeof(item.value) <> 'object'
                OR NOT (item.value ?& ARRAY['toothId','facts','confirmedAssessment'])
                OR EXISTS (SELECT 1 FROM jsonb_object_keys(item.value) AS key(value)
                            WHERE key.value <> ALL(ARRAY['toothId','facts','confirmedAssessment']))
                OR jsonb_typeof(item.value -> 'toothId') <> 'string'
                OR (item.value ->> 'toothId') !~ '^[1-4][1-8]$'
                OR jsonb_typeof(item.value -> 'facts') <> 'object'
                OR NOT ((item.value -> 'facts') ?& ARRAY['toothStatus','symptoms','toothNote'])
                OR EXISTS (SELECT 1 FROM jsonb_object_keys(item.value -> 'facts') AS key(value)
                            WHERE key.value <> ALL(ARRAY['toothStatus','symptoms','toothNote']))
                OR jsonb_typeof(item.value -> 'facts' -> 'toothStatus') <> 'string'
                OR item.value -> 'facts' ->> 'toothStatus' NOT IN ('healthy','problem','treated','missing')
                OR jsonb_typeof(item.value -> 'facts' -> 'symptoms') <> 'array'
                OR jsonb_array_length(item.value -> 'facts' -> 'symptoms') > 100
                OR EXISTS (
                    SELECT 1 FROM jsonb_array_elements(item.value -> 'facts' -> 'symptoms') AS symptom(value)
                     WHERE jsonb_typeof(symptom.value) <> 'string'
                        OR btrim(symptom.value #>> '{}') = ''
                        OR length(symptom.value #>> '{}') > 250
                )
                OR jsonb_typeof(item.value -> 'facts' -> 'toothNote') <> 'string'
                OR length(item.value -> 'facts' ->> 'toothNote') > 10000
                OR jsonb_typeof(item.value -> 'confirmedAssessment') <> 'object'
                OR NOT ((item.value -> 'confirmedAssessment') ?& ARRAY[
                    'clinicalDescription','diagnosis','icd10','treatmentPlan'
                ])
                OR EXISTS (
                    SELECT 1 FROM jsonb_object_keys(item.value -> 'confirmedAssessment') AS key(value)
                     WHERE key.value <> ALL(ARRAY[
                        'clinicalDescription','diagnosis','icd10','treatmentPlan'
                     ])
                )
                OR NOT security.medical_report_nullable_bounded_string(
                    item.value -> 'confirmedAssessment' -> 'clinicalDescription', 20000)
                OR NOT security.medical_report_nullable_bounded_string(
                    item.value -> 'confirmedAssessment' -> 'diagnosis', 5000)
                OR NOT security.medical_report_nullable_bounded_string(
                    item.value -> 'confirmedAssessment' -> 'treatmentPlan', 20000)
                OR NOT security.medical_report_icd10_valid(
                    item.value -> 'confirmedAssessment' -> 'icd10')
        )
        -- Authoritative procedures have no fabricated tooth association.
        AND jsonb_array_length(p_snapshot -> 'performedProcedures') <= 1000
        AND NOT EXISTS (
            SELECT 1 FROM jsonb_array_elements(p_snapshot -> 'performedProcedures') AS item(value)
             WHERE jsonb_typeof(item.value) <> 'object'
                OR NOT (item.value ?& ARRAY['id','procedureId','name','quantity'])
                OR EXISTS (SELECT 1 FROM jsonb_object_keys(item.value) AS key(value)
                            WHERE key.value <> ALL(ARRAY['id','procedureId','name','quantity']))
                OR jsonb_typeof(item.value -> 'id') <> 'string'
                OR NOT pg_input_is_valid(item.value ->> 'id', 'uuid')
                OR jsonb_typeof(item.value -> 'procedureId') <> 'string'
                OR NOT pg_input_is_valid(item.value ->> 'procedureId', 'uuid')
                OR jsonb_typeof(item.value -> 'name') <> 'string'
                OR btrim(item.value ->> 'name') = ''
                OR length(item.value ->> 'name') > 1000
                OR jsonb_typeof(item.value -> 'quantity') <> 'number'
                OR (item.value ->> 'quantity') !~ '^[1-9][0-9]*$'
                OR (item.value ->> 'quantity')::numeric > 999
        )
        -- Doctor, clinic and review snapshots.
        AND security.medical_report_doctor_valid(p_snapshot -> 'doctor')
        AND security.medical_report_clinic_valid(p_snapshot -> 'clinic')
        AND security.medical_report_review_valid(p_snapshot -> 'review')
      END
$function$;


ALTER TABLE public.clinical_reports
    ADD CONSTRAINT clinical_reports_snapshot_valid_ck
    CHECK (security.medical_report_snapshot_valid(report_snapshot)),
    ADD CONSTRAINT clinical_reports_snapshot_state_ck
    CHECK (
        (report_snapshot IS NULL AND snapshot_version IS NULL
         AND reviewed_by IS NULL AND reviewed_at IS NULL AND finalized_at IS NULL)
        OR
        (report_snapshot IS NOT NULL AND snapshot_version = 1
         AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL AND finalized_at IS NOT NULL)
    );

REVOKE ALL ON FUNCTION security.medical_report_nullable_bounded_string(jsonb,integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION security.medical_report_icd10_valid(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION security.medical_report_doctor_valid(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION security.medical_report_clinic_valid(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION security.medical_report_review_valid(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION security.medical_report_snapshot_valid(jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION security.prevent_finalized_report_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $function$
BEGIN
    IF OLD.finalized_at IS NOT NULL AND (
        NEW.report_snapshot IS DISTINCT FROM OLD.report_snapshot
        OR NEW.snapshot_version IS DISTINCT FROM OLD.snapshot_version
        OR NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by
        OR NEW.reviewed_at IS DISTINCT FROM OLD.reviewed_at
        OR NEW.finalized_at IS DISTINCT FROM OLD.finalized_at
        OR NEW.patient_id IS DISTINCT FROM OLD.patient_id
        OR NEW.doctor_id IS DISTINCT FROM OLD.doctor_id
        OR NEW.appointment_id IS DISTINCT FROM OLD.appointment_id
        OR NEW.consultation_id IS DISTINCT FROM OLD.consultation_id
        OR NEW.tooth_id IS DISTINCT FROM OLD.tooth_id
        OR NEW.tooth_status IS DISTINCT FROM OLD.tooth_status
        OR NEW.symptoms IS DISTINCT FROM OLD.symptoms
        OR NEW.doctor_notes IS DISTINCT FROM OLD.doctor_notes
        OR NEW.ai_draft_report IS DISTINCT FROM OLD.ai_draft_report
        OR NEW.final_medical_report IS DISTINCT FROM OLD.final_medical_report
        OR NEW.status IS DISTINCT FROM OLD.status
    ) THEN
        RAISE EXCEPTION 'FINALIZED_REPORT_IMMUTABLE' USING ERRCODE = 'P2205';
    END IF;
    RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION security.prevent_finalized_report_mutation() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER clinical_reports_finalized_immutability
BEFORE UPDATE ON public.clinical_reports
FOR EACH ROW EXECUTE FUNCTION security.prevent_finalized_report_mutation();

CREATE OR REPLACE FUNCTION public.finalize_clinical_report(
    p_report_id uuid,
    p_assessments jsonb,
    p_clinical_summary text,
    p_final_narrative text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_actor_id uuid;
    v_actor_role text;
    v_report public.clinical_reports%ROWTYPE;
    v_consultation public.consultations%ROWTYPE;
    v_patient public.patients%ROWTYPE;
    v_doctor public.users%ROWTYPE;
    v_appointment public.appointments%ROWTYPE;
    v_clinic public.clinic_settings%ROWTYPE;
    v_assessments jsonb;
    v_procedures jsonb;
    v_snapshot jsonb;
    v_now timestamptz := now();
    v_examination_date timestamptz;
BEGIN
    SELECT actor.id, actor.role INTO v_actor_id, v_actor_role
      FROM security.clinical_report_actor() AS actor;
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'REPORT_AUTHORIZATION_DENIED' USING ERRCODE = '42501';
    END IF;

    SELECT report.* INTO v_report
      FROM public.clinical_reports AS report
     WHERE report.id = p_report_id
     FOR UPDATE;
    IF v_report.id IS NULL THEN
        RAISE EXCEPTION 'REPORT_NOT_FOUND' USING ERRCODE = 'P2203';
    END IF;
    IF v_report.doctor_id IS NULL
       OR (v_actor_role = 'doctor' AND v_report.doctor_id <> v_actor_id) THEN
        RAISE EXCEPTION 'REPORT_AUTHORIZATION_DENIED' USING ERRCODE = '42501';
    END IF;
    IF v_report.finalized_at IS NOT NULL OR v_report.report_snapshot IS NOT NULL THEN
        RAISE EXCEPTION 'FINALIZED_REPORT_IMMUTABLE' USING ERRCODE = 'P2205';
    END IF;
    IF v_report.consultation_id IS NULL THEN
        RAISE EXCEPTION 'REPORT_CONSULTATION_NOT_FOUND' USING ERRCODE = 'P2202';
    END IF;

    SELECT consultation.* INTO v_consultation
      FROM public.consultations AS consultation
     WHERE consultation.id = v_report.consultation_id
     FOR SHARE;
    IF v_consultation.id IS NULL
       OR v_consultation.patient_id IS DISTINCT FROM v_report.patient_id
       OR v_consultation.appointment_id IS DISTINCT FROM v_report.appointment_id
       OR v_consultation.doctor_id IS DISTINCT FROM v_report.doctor_id THEN
        RAISE EXCEPTION 'REPORT_LINKAGE_MISMATCH' USING ERRCODE = 'P2204';
    END IF;
    IF v_consultation.clinical_findings_snapshot IS NULL
       OR NOT security.clinical_findings_snapshot_valid(v_consultation.clinical_findings_snapshot) THEN
        RAISE EXCEPTION 'REPORT_STRUCTURED_FINDINGS_REQUIRED' USING ERRCODE = '22023';
    END IF;

    IF p_assessments IS NULL OR jsonb_typeof(p_assessments) <> 'array'
       OR jsonb_array_length(p_assessments) > 32
       OR jsonb_array_length(p_assessments) <>
          jsonb_array_length(v_consultation.clinical_findings_snapshot)
       OR (SELECT count(*) FROM jsonb_array_elements(p_assessments)) <>
          (SELECT count(DISTINCT assessment.value ->> 'toothId')
             FROM jsonb_array_elements(p_assessments) AS assessment(value))
       OR EXISTS (
           SELECT 1 FROM jsonb_array_elements(p_assessments) AS assessment(value)
            WHERE jsonb_typeof(assessment.value) <> 'object'
               OR NOT (assessment.value ?& ARRAY[
                   'toothId','clinicalDescription','diagnosis','icd10','treatmentPlan'
               ])
               OR EXISTS (
                   SELECT 1 FROM jsonb_object_keys(assessment.value) AS key(value)
                    WHERE key.value <> ALL(ARRAY[
                        'toothId','clinicalDescription','diagnosis','icd10','treatmentPlan'
                    ])
               )
               OR jsonb_typeof(assessment.value -> 'toothId') <> 'string'
               OR NOT EXISTS (
                   SELECT 1
                     FROM jsonb_array_elements(v_consultation.clinical_findings_snapshot) AS finding(value)
                    WHERE finding.value ->> 'toothId' = assessment.value ->> 'toothId'
               )
               OR NOT security.medical_report_nullable_bounded_string(
                   assessment.value -> 'clinicalDescription', 20000)
               OR NOT security.medical_report_nullable_bounded_string(
                   assessment.value -> 'diagnosis', 5000)
               OR NOT security.medical_report_icd10_valid(assessment.value -> 'icd10')
               OR NOT security.medical_report_nullable_bounded_string(
                   assessment.value -> 'treatmentPlan', 20000)
       )
       OR p_clinical_summary IS NULL OR length(p_clinical_summary) > 50000
       OR p_final_narrative IS NULL OR btrim(p_final_narrative) = ''
       OR length(p_final_narrative) > 200000 THEN
        RAISE EXCEPTION 'REPORT_ASSESSMENTS_INVALID' USING ERRCODE = '22023';
    END IF;

    SELECT patient.* INTO v_patient FROM public.patients AS patient
     WHERE patient.id = v_report.patient_id;
    SELECT doctor.* INTO v_doctor FROM public.users AS doctor
     WHERE doctor.id = v_report.doctor_id;
    IF v_patient.id IS NULL OR v_doctor.id IS NULL THEN
        RAISE EXCEPTION 'REPORT_LINKAGE_MISMATCH' USING ERRCODE = 'P2204';
    END IF;
    IF v_report.appointment_id IS NOT NULL THEN
        SELECT appointment.* INTO v_appointment FROM public.appointments AS appointment
         WHERE appointment.id = v_report.appointment_id;
        IF v_appointment.id IS NULL THEN
            RAISE EXCEPTION 'REPORT_LINKAGE_MISMATCH' USING ERRCODE = 'P2204';
        END IF;
    END IF;
    SELECT settings.* INTO v_clinic FROM public.clinic_settings AS settings
     ORDER BY settings.id LIMIT 1;

    SELECT coalesce(jsonb_agg(jsonb_build_object(
               'toothId', finding.value ->> 'toothId',
               'facts', jsonb_build_object(
                   'toothStatus', finding.value ->> 'toothStatus',
                   'symptoms', finding.value -> 'symptoms',
                   'toothNote', finding.value ->> 'toothNote'
               ),
               'confirmedAssessment', assessment.value - 'toothId'
           ) ORDER BY (finding.value ->> 'toothId')::integer), '[]'::jsonb)
      INTO v_assessments
      FROM jsonb_array_elements(v_consultation.clinical_findings_snapshot) AS finding(value)
      JOIN jsonb_array_elements(p_assessments) AS assessment(value)
        ON assessment.value ->> 'toothId' = finding.value ->> 'toothId';

    SELECT coalesce(jsonb_agg(jsonb_build_object(
               'id', item.value ->> 'id',
               'procedureId', item.value ->> 'procedureId',
               'name', item.value ->> 'name',
               'quantity', (item.value ->> 'quantity')::integer
           ) ORDER BY item.ordinality), '[]'::jsonb)
      INTO v_procedures
      FROM jsonb_array_elements(security.financial_effective_items(v_consultation.id))
           WITH ORDINALITY AS item(value, ordinality);

    v_examination_date := coalesce(
        v_appointment.appointment_date::timestamptz,
        v_appointment.date::timestamptz,
        v_consultation.created_at::timestamptz
    );
    v_snapshot := jsonb_build_object(
        'schemaVersion', 1,
        'patient', jsonb_build_object(
            'id', v_patient.id, 'name', v_patient.name,
            'dateOfBirth', NULL, 'ageAtExamination', v_patient.age,
            'gender', v_patient.gender
        ),
        'consultation', jsonb_build_object(
            'id', v_consultation.id, 'appointmentId', v_consultation.appointment_id,
            'examinationDate', v_examination_date
        ),
        'clinicalAssessments', v_assessments,
        'performedProcedures', v_procedures,
        'clinicalSummary', p_clinical_summary,
        'doctor', jsonb_build_object(
            'id', v_doctor.id,
            'name', coalesce(nullif(btrim(v_doctor.full_name), ''), v_doctor.username),
            'specialty', v_doctor.specialization,
            'licenseNumber', NULL
        ),
        'clinic', jsonb_build_object(
            'name', v_clinic.name,
            'contact', jsonb_build_object(
                'email', v_clinic.email, 'phone', v_clinic.phone, 'address', v_clinic.address
            )
        ),
        'review', jsonb_build_object(
            'reviewedBy', v_actor_id, 'reviewedAt', v_now,
            'electronicSignatureDisplay', NULL
        ),
        'finalNarrative', p_final_narrative
    );
    IF NOT security.medical_report_snapshot_valid(v_snapshot) THEN
        RAISE EXCEPTION 'REPORT_SNAPSHOT_INVALID' USING ERRCODE = '22023';
    END IF;

    UPDATE public.clinical_reports AS report
       SET report_snapshot = v_snapshot,
           snapshot_version = 1,
           reviewed_by = v_actor_id,
           reviewed_at = v_now,
           finalized_at = v_now,
           final_medical_report = p_final_narrative,
           status = 'finalized',
           updated_at = v_now
     WHERE report.id = v_report.id;

    INSERT INTO public.logs (id, message, doctor_id, patient_id, created_at)
    VALUES (gen_random_uuid(),
            format('Clinical report %s finalized for patient %s', v_report.id, v_report.patient_id),
            v_actor_id, v_report.patient_id, v_now);

    RETURN jsonb_build_object(
        'id', v_report.id, 'status', 'finalized',
        'snapshotVersion', 1, 'reviewedBy', v_actor_id,
        'reviewedAt', v_now, 'finalizedAt', v_now,
        'reportSnapshot', v_snapshot
    );
END
$function$;

-- Retain the deployed legacy implementation privately. The public wrapper
-- permits legacy editing only while report_snapshot remains NULL.
ALTER FUNCTION public.update_clinical_report(uuid,jsonb)
    RENAME TO update_clinical_report_legacy;
ALTER FUNCTION public.update_clinical_report_legacy(uuid,jsonb)
    SET SCHEMA security;
REVOKE ALL ON FUNCTION security.update_clinical_report_legacy(uuid,jsonb)
FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.update_clinical_report(p_report_id uuid, p_updates jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_actor_id uuid;
    v_actor_role text;
    v_report public.clinical_reports%ROWTYPE;
    v_finalized boolean;
BEGIN
    SELECT actor.id, actor.role INTO v_actor_id, v_actor_role
      FROM security.clinical_report_actor() AS actor;
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'REPORT_AUTHORIZATION_DENIED' USING ERRCODE = '42501';
    END IF;
    SELECT report.* INTO v_report
      FROM public.clinical_reports AS report
     WHERE report.id = p_report_id;
    IF v_report.id IS NULL THEN
        RAISE EXCEPTION 'REPORT_NOT_FOUND' USING ERRCODE = 'P2203';
    END IF;
    IF v_report.doctor_id IS NULL
       OR (v_actor_role = 'doctor' AND v_report.doctor_id <> v_actor_id) THEN
        RAISE EXCEPTION 'REPORT_AUTHORIZATION_DENIED' USING ERRCODE = '42501';
    END IF;
    v_finalized := v_report.report_snapshot IS NOT NULL OR v_report.finalized_at IS NOT NULL;
    IF v_finalized THEN
        RAISE EXCEPTION 'FINALIZED_REPORT_IMMUTABLE' USING ERRCODE = 'P2205';
    END IF;
    RETURN security.update_clinical_report_legacy(p_report_id, p_updates);
END
$function$;

-- Enrich the hardened deployed read projection without rebuilding snapshots.
ALTER FUNCTION public.get_patient_clinical_reports(uuid)
    RENAME TO get_patient_clinical_reports_legacy;
ALTER FUNCTION public.get_patient_clinical_reports_legacy(uuid)
    SET SCHEMA security;
REVOKE ALL ON FUNCTION security.get_patient_clinical_reports_legacy(uuid)
FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_patient_clinical_reports(p_patient_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_legacy jsonb;
    v_result jsonb;
BEGIN
    v_legacy := security.get_patient_clinical_reports_legacy(p_patient_id);
    SELECT coalesce(jsonb_agg(item.value || jsonb_build_object(
               'reportSnapshot', report.report_snapshot,
               'snapshotVersion', report.snapshot_version,
               'reviewedBy', report.reviewed_by,
               'reviewedAt', report.reviewed_at,
               'finalizedAt', report.finalized_at
           ) ORDER BY item.ordinality), '[]'::jsonb)
      INTO v_result
      FROM jsonb_array_elements(v_legacy) WITH ORDINALITY AS item(value, ordinality)
      JOIN public.clinical_reports AS report
        ON report.id = (item.value ->> 'id')::uuid;
    RETURN v_result;
END
$function$;

REVOKE ALL ON FUNCTION public.finalize_clinical_report(uuid,jsonb,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.finalize_clinical_report(uuid,jsonb,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.finalize_clinical_report(uuid,jsonb,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.update_clinical_report(uuid,jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_clinical_report(uuid,jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_clinical_report(uuid,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.get_patient_clinical_reports(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_patient_clinical_reports(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_patient_clinical_reports(uuid) TO authenticated;

COMMIT;
