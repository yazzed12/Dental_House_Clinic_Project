import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / "backend" / "migrations" / "017_consultation_history_consultation_first_hotfix.sql"
VERIFY = ROOT / "backend" / "migrations" / "017_consultation_history_consultation_first_hotfix_verify.sql"
PREFLIGHT = ROOT / "backend" / "migrations" / "017_consultation_history_consultation_first_preflight.sql"


def compatible_report(consultation, reports):
    candidates = []
    for report in reports:
        if report["patient_id"] != consultation["patient_id"]:
            continue
        if (report.get("doctor_id") is not None
                and consultation.get("doctor_id") is not None
                and report["doctor_id"] != consultation["doctor_id"]):
            continue
        exact_appointment = (
            consultation.get("appointment_id") is not None
            and report.get("appointment_id") == consultation["appointment_id"]
        )
        exact_doctor = (
            consultation.get("doctor_id") is not None
            and report.get("doctor_id") == consultation["doctor_id"]
            and (report.get("appointment_id") is None
                 or consultation.get("appointment_id") is None)
            and (report.get("created_at") is None
                 or consultation.get("created_at") is None
                 or report["created_at"] >= consultation["created_at"])
        )
        legacy = (
            (report.get("doctor_id") is None or consultation.get("doctor_id") is None)
            and report.get("appointment_id") is None
            and consultation.get("appointment_id") is None
            and report.get("created_date") == consultation.get("effective_date")
        )
        if not (exact_appointment or exact_doctor or legacy):
            continue
        rank = 0 if exact_appointment else 1 if exact_doctor else 2
        candidates.append((rank, report.get("created_at") or "", report["id"], report))
    if not candidates:
        return None
    best_rank = min(item[0] for item in candidates)
    return max((item for item in candidates if item[0] == best_rank),
               key=lambda item: (item[1], item[2]))[3]


class ConsultationFirstHistoryHotfixTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = " ".join(MIGRATION.read_text(encoding="utf-8").lower().split())
        cls.verify = " ".join(VERIFY.read_text(encoding="utf-8").lower().split())
        cls.preflight = PREFLIGHT.read_text(encoding="utf-8").lower()

    def test_preflight_is_read_only_and_measures_candidates_and_unmatched_reports(self):
        for marker in (
            "compatible_report_candidates", "matched_reports", "clinical_reports",
            "consultations", "consultation_procedures", "pg_indexes",
        ):
            self.assertIn(marker, self.preflight)
        executable = re.sub(r"--[^\n]*", "", self.preflight)
        self.assertNotRegex(executable, r"\b(insert|update|delete|alter|drop|create|grant|revoke|truncate)\b")

    def test_consultations_are_authoritative_and_report_is_lateral_optional(self):
        self.assertIn("eligible_consultations as", self.sql)
        self.assertIn("from public.consultations as consultation", self.sql)
        self.assertIn("left join lateral ( select candidate.* from public.clinical_reports as candidate", self.sql)
        self.assertIn("'reportid', item.report_id", self.sql)
        self.assertIn("coalesce(item.report_id::text, 'consultation:' || item.consultation_id::text)", self.sql)
        self.assertIn("'reportonly', false", self.sql)

    def test_consultation_without_report_remains_one_history_row(self):
        self.assertIn("item.consultation_id::text as stable_id", self.sql)
        self.assertIn("report.id as report_id", self.sql)
        self.assertIn("limit 1", self.sql)
        self.assertNotIn("cross join lateral ( select candidate", self.sql)

    def test_multiple_reports_cannot_duplicate_a_consultation_row(self):
        reports = [
            {"id": "report-a", "patient_id": "patient-a", "doctor_id": "doctor-a",
             "appointment_id": "appointment-a", "created_at": "2026-08-10"},
            {"id": "report-b", "patient_id": "patient-a", "doctor_id": "doctor-a",
             "appointment_id": "appointment-a", "created_at": "2026-08-11"},
        ]
        consultation = {"patient_id": "patient-a", "doctor_id": "doctor-a",
                        "appointment_id": "appointment-a", "created_at": "2026-08-09"}
        self.assertEqual(compatible_report(consultation, reports)["id"], "report-b")
        self.assertIn("candidate.created_at desc nulls last, candidate.id desc limit 1", self.sql)

    def test_duplicate_consultations_for_one_appointment_remain_distinct(self):
        self.assertNotIn("distinct on (consultation.appointment_id)", self.sql)
        self.assertNotIn("group by consultation.appointment_id", self.sql)
        self.assertIn("'consultationid', item.consultation_id", self.sql)

    def test_report_matching_priority_and_identity_containment(self):
        consultation = {"patient_id": "patient-a", "doctor_id": "doctor-a",
                        "appointment_id": "appointment-a", "created_at": "2026-08-01",
                        "effective_date": "2026-08-01"}
        reports = [
            {"id": "doctor", "patient_id": "patient-a", "doctor_id": "doctor-a",
             "appointment_id": None, "created_at": "2026-08-03"},
            {"id": "appointment", "patient_id": "patient-a", "doctor_id": "doctor-a",
             "appointment_id": "appointment-a", "created_at": "2026-08-02"},
            {"id": "wrong-doctor", "patient_id": "patient-a", "doctor_id": "doctor-b",
             "appointment_id": "appointment-a", "created_at": "2026-08-04"},
            {"id": "wrong-patient", "patient_id": "patient-b", "doctor_id": "doctor-a",
             "appointment_id": "appointment-a", "created_at": "2026-08-05"},
        ]
        self.assertEqual(compatible_report(consultation, reports)["id"], "appointment")

    def test_safe_null_legacy_fallback_is_same_day_only(self):
        consultation = {"patient_id": "patient-a", "doctor_id": None,
                        "appointment_id": None, "created_at": "2026-08-01",
                        "effective_date": "2026-08-01"}
        reports = [
            {"id": "future", "patient_id": "patient-a", "doctor_id": None,
             "appointment_id": None, "created_at": "2026-08-03", "created_date": "2026-08-03"},
            {"id": "same-day", "patient_id": "patient-a", "doctor_id": None,
             "appointment_id": None, "created_at": "2026-08-01T12:00", "created_date": "2026-08-01"},
        ]
        self.assertEqual(compatible_report(consultation, reports)["id"], "same-day")

    def test_authorization_and_procedure_session_projection_are_consultation_owned(self):
        for marker in (
            "consultation.doctor_id = v_caller_id",
            "consultation.doctor_id is null",
            "relationship_appointment.doctor_id = v_caller_id",
            "owned_consultation.doctor_id = v_caller_id",
            "selection.consultation_id = consultation.id",
            "'sessionnote', item.session_note",
        ):
            self.assertIn(marker, self.sql)

    def test_unmatched_reports_are_explicitly_preserved_without_fake_consultation(self):
        self.assertIn("union all", self.sql)
        self.assertIn("not exists ( select 1 from matched_report_ids", self.sql)
        self.assertIn("'consultationid', null", self.sql)
        self.assertIn("'procedures', '[]'::jsonb", self.sql)
        self.assertIn("'reportonly', true", self.sql)

    def test_history_is_read_only_hardened_and_verified(self):
        function_body = self.sql.split("as $function$", 1)[1].split("$function$;", 1)[0]
        self.assertNotRegex(function_body, r"\b(insert|update|delete)\s+(into|public|from)")
        self.assertIn("security definer set search_path = pg_catalog, pg_temp", self.sql)
        self.assertIn("revoke all on function public.list_doctor_consultation_history() from public", self.sql)
        self.assertIn("verification successful: consultation history is consultation-first", self.verify)


if __name__ == "__main__":
    unittest.main()
