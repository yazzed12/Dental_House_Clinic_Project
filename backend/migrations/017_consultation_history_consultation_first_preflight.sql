-- READ-ONLY preflight for the consultation-first history hotfix.
-- Execute manually only after separate approval.

SELECT
    count(*) AS consultation_count,
    count(*) FILTER (WHERE doctor_id IS NULL) AS null_doctor_id,
    count(*) FILTER (WHERE appointment_id IS NULL) AS null_appointment_id
FROM public.consultations;

SELECT
    count(*) AS report_count,
    count(*) FILTER (WHERE doctor_id IS NULL) AS null_doctor_id,
    count(*) FILTER (WHERE appointment_id IS NULL) AS null_appointment_id
FROM public.clinical_reports;

SELECT consultation.id AS consultation_id, consultation.patient_id,
       consultation.doctor_id, consultation.appointment_id,
       consultation.created_at, consultation.last_updated,
       count(report.id) AS compatible_report_candidates
FROM public.consultations AS consultation
LEFT JOIN public.clinical_reports AS report
  ON report.patient_id = consultation.patient_id
 AND (report.doctor_id IS NULL OR consultation.doctor_id IS NULL
      OR report.doctor_id = consultation.doctor_id)
 AND (
     (consultation.appointment_id IS NOT NULL
      AND report.appointment_id = consultation.appointment_id)
     OR (consultation.doctor_id IS NOT NULL
         AND report.doctor_id = consultation.doctor_id
         AND (report.created_at IS NULL OR consultation.created_at IS NULL
              OR report.created_at >= consultation.created_at))
     OR ((consultation.doctor_id IS NULL OR report.doctor_id IS NULL)
         AND consultation.appointment_id IS NULL AND report.appointment_id IS NULL
         AND report.created_at::date = coalesce(consultation.last_updated, consultation.created_at)::date)
 )
GROUP BY consultation.id, consultation.patient_id, consultation.doctor_id,
         consultation.appointment_id, consultation.created_at, consultation.last_updated
ORDER BY compatible_report_candidates DESC, consultation.last_updated DESC NULLS LAST,
         consultation.created_at DESC NULLS LAST, consultation.id DESC;

WITH matched_reports AS (
    SELECT DISTINCT matched.report_id
    FROM public.consultations AS consultation
    CROSS JOIN LATERAL (
        SELECT report.id AS report_id
        FROM public.clinical_reports AS report
        WHERE report.patient_id = consultation.patient_id
          AND (report.doctor_id IS NULL OR consultation.doctor_id IS NULL
               OR report.doctor_id = consultation.doctor_id)
          AND (
              (consultation.appointment_id IS NOT NULL
               AND report.appointment_id = consultation.appointment_id)
              OR (consultation.doctor_id IS NOT NULL
                  AND report.doctor_id = consultation.doctor_id
                  AND (report.created_at IS NULL OR consultation.created_at IS NULL
                       OR report.created_at >= consultation.created_at))
              OR ((consultation.doctor_id IS NULL OR report.doctor_id IS NULL)
                  AND consultation.appointment_id IS NULL AND report.appointment_id IS NULL
                  AND report.created_at::date = coalesce(consultation.last_updated, consultation.created_at)::date)
          )
        ORDER BY
          CASE
            WHEN consultation.appointment_id IS NOT NULL
             AND report.appointment_id = consultation.appointment_id THEN 0
            WHEN consultation.doctor_id IS NOT NULL
             AND report.doctor_id = consultation.doctor_id THEN 1
            ELSE 2
          END,
          report.created_at DESC NULLS LAST, report.id DESC
        LIMIT 1
    ) AS matched
)
SELECT report.id, report.patient_id, report.doctor_id, report.appointment_id,
       report.created_at
FROM public.clinical_reports AS report
LEFT JOIN matched_reports AS matched ON matched.report_id = report.id
WHERE matched.report_id IS NULL
ORDER BY report.created_at DESC NULLS LAST, report.id DESC;

SELECT appointment_id, count(*) AS consultation_count,
       array_agg(id ORDER BY last_updated DESC NULLS LAST,
                 created_at DESC NULLS LAST, id DESC) AS consultation_ids
FROM public.consultations
WHERE appointment_id IS NOT NULL
GROUP BY appointment_id
HAVING count(*) > 1
ORDER BY consultation_count DESC, appointment_id;

SELECT consultation_id, count(*) AS procedure_count
FROM public.consultation_procedures
GROUP BY consultation_id
ORDER BY procedure_count DESC, consultation_id;

SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('consultations', 'clinical_reports', 'consultation_procedures')
ORDER BY tablename, indexname;
