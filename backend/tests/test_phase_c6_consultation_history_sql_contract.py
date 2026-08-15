import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / "backend" / "migrations" / "016_consultation_history_supabase_vertical_slice.sql"
PREFLIGHT = ROOT / "backend" / "migrations" / "016_consultation_history_production_preflight.sql"
VERIFY = ROOT / "backend" / "migrations" / "016_consultation_history_supabase_vertical_slice_verify.sql"


def migration_016_match(report, consultations):
    candidates = []
    for consultation in consultations:
        if consultation["patient_id"] != report["patient_id"]:
            continue
        exact_appointment = (
            report.get("appointment_id") is not None
            and consultation.get("appointment_id") == report["appointment_id"]
            and (
                report.get("doctor_id") is None
                or consultation.get("doctor_id") is None
                or consultation.get("doctor_id") == report["doctor_id"]
            )
        )
        exact_doctor = (
            report.get("doctor_id") is not None
            and consultation.get("doctor_id") == report["doctor_id"]
        )
        legacy_null_doctor = consultation.get("doctor_id") is None
        if not (exact_appointment or exact_doctor or legacy_null_doctor):
            continue
        if not (
            (
                report.get("appointment_id") is not None
                and consultation.get("appointment_id") == report.get("appointment_id")
            )
            or report.get("created_at") is None
            or consultation.get("created_at") <= report["created_at"]
        ):
            continue
        rank = 0 if exact_appointment else 1 if exact_doctor else 2
        candidates.append((
            rank,
            consultation.get("last_updated") or "",
            consultation.get("created_at") or "",
            consultation["id"],
            consultation,
        ))
    candidates.sort(key=lambda item: (item[0], item[1], item[2], item[3]), reverse=False)
    if not candidates:
        return None
    best_rank = candidates[0][0]
    ranked = [item for item in candidates if item[0] == best_rank]
    return max(ranked, key=lambda item: (item[1], item[2], item[3]))[4]


class ConsultationHistorySqlContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = " ".join(MIGRATION.read_text(encoding="utf-8").lower().split())
        cls.preflight = PREFLIGHT.read_text(encoding="utf-8").lower()
        cls.verify = " ".join(VERIFY.read_text(encoding="utf-8").lower().split())

    def body(self, name):
        return self.sql.split(f"create or replace function public.{name}", 1)[1].split("$function$;", 1)[0]

    def test_preflight_is_read_only_and_inventories_history_anomalies(self):
        for table in (
            "consultations", "appointments", "patients", "users",
            "clinical_reports", "consultation_procedures",
        ):
            self.assertIn(table, self.preflight)
        for marker in (
            "null_doctor_id", "null_appointment_id", "duplicate",
            "broken_patient_references", "broken_doctor_references",
            "exact_consultation_matches", "pg_policies", "role_table_grants",
            "pg_indexes", "information_schema.triggers",
        ):
            self.assertIn(marker, self.preflight)
        executable = re.sub(r"--[^\n]*", "", self.preflight)
        self.assertNotRegex(executable, r"\b(insert|update|delete|alter|drop|create|grant|revoke|truncate)\b")

    def test_actor_is_authenticated_active_approved_doctor_or_admin(self):
        self.assertIn("app_user.supabase_user_id = auth.uid()", self.sql)
        self.assertIn("app_user.is_active = true", self.sql)
        self.assertIn("app_user.approved_at is not null", self.sql)
        self.assertIn("app_user.role in ('doctor', 'admin')", self.sql)
        self.assertNotIn("service_role", self.sql)

    def test_patient_history_preserves_exact_frontend_shape_and_all_legacy_rows(self):
        body = self.body("get_patient_consultation_history")
        for field in (
            "consultationid", "patientid", "doctorid", "appointmentid",
            "toothdata", "sessionnote", "version", "createdat", "lastupdated",
        ):
            self.assertIn(f"'{field}'", body)
        self.assertIn("consultation.patient_id = p_patient_id", body)
        self.assertNotIn("consultation.doctor_id is not null", body)
        self.assertNotIn("consultation.appointment_id is not null", body)
        self.assertNotIn("distinct on", body)

    def test_doctor_requires_independent_patient_relationship_before_legacy_visibility(self):
        body = self.body("get_patient_consultation_history")
        self.assertIn("v_caller_role = 'doctor'", body)
        self.assertIn("appointment.doctor_id = v_caller_id", body)
        self.assertIn("owned_consultation.doctor_id = v_caller_id", body)
        self.assertIn("consultation_history_authorization_denied", body)

    def test_history_order_is_deterministic_and_duplicates_are_not_collapsed(self):
        body = self.body("get_patient_consultation_history")
        self.assertIn("consultation.last_updated desc nulls last", body)
        self.assertIn("consultation.created_at desc nulls last", body)
        self.assertIn("consultation.id desc", body)
        self.assertNotIn("limit", body)
        self.assertNotIn("distinct", body)

    def test_report_backed_doctor_projection_is_read_only_and_compatible(self):
        body = self.body("list_doctor_consultation_history")
        for field in (
            "patient_name", "tooth_status", "symptoms", "doctor_notes",
            "ai_draft_report", "final_medical_report", "humanized_report",
            "consultationid", "sessionnote", "procedures",
        ):
            self.assertIn(f"'{field}'", body)
        self.assertIn("v_caller_role = 'admin' or report.doctor_id = v_caller_id", body)
        self.assertIn("left join lateral", body)
        self.assertIn("security.consultation_history_json_array(report.symptoms)", body)
        self.assertIn("report.created_at desc nulls last", body)
        self.assertNotIn("insert into public.clinical_reports", body)
        self.assertNotIn("update public.clinical_reports", body)

    def test_exact_appointment_then_doctor_then_null_doctor_matching(self):
        report = {
            "patient_id": "patient-a", "appointment_id": "appointment-a",
            "doctor_id": "doctor-a", "created_at": "2026-08-10",
        }
        candidates = [
            {"id": "legacy", "patient_id": "patient-a", "appointment_id": None,
             "doctor_id": None, "created_at": "2026-08-09", "last_updated": "2026-08-09"},
            {"id": "doctor", "patient_id": "patient-a", "appointment_id": None,
             "doctor_id": "doctor-a", "created_at": "2026-08-09", "last_updated": "2026-08-10"},
            {"id": "appointment", "patient_id": "patient-a", "appointment_id": "appointment-a",
             "doctor_id": "doctor-a", "created_at": "2026-08-08", "last_updated": "2026-08-08"},
        ]
        self.assertEqual(migration_016_match(report, candidates)["id"], "appointment")
        report["appointment_id"] = None
        self.assertEqual(migration_016_match(report, candidates)["id"], "doctor")
        candidates = [item for item in candidates if item["doctor_id"] != "doctor-a"]
        self.assertEqual(migration_016_match(report, candidates)["id"], "legacy")

    def test_matching_never_crosses_patient_or_explicit_doctor(self):
        report = {
            "patient_id": "patient-a", "appointment_id": "appointment-a",
            "doctor_id": "doctor-a", "created_at": "2026-08-10",
        }
        unsafe = [
            {"id": "other-patient", "patient_id": "patient-b", "appointment_id": "appointment-a",
             "doctor_id": "doctor-a", "created_at": "2026-08-09", "last_updated": "2026-08-09"},
            {"id": "other-doctor", "patient_id": "patient-a", "appointment_id": "appointment-a",
             "doctor_id": "doctor-b", "created_at": "2026-08-09", "last_updated": "2026-08-09"},
        ]
        self.assertIsNone(migration_016_match(report, unsafe))

    def test_multiple_legacy_candidates_are_deterministic(self):
        report = {"patient_id": "patient-a", "appointment_id": None,
                  "doctor_id": None, "created_at": "2026-08-10"}
        candidates = [
            {"id": "a", "patient_id": "patient-a", "appointment_id": None,
             "doctor_id": None, "created_at": "2026-08-08", "last_updated": "2026-08-09"},
            {"id": "b", "patient_id": "patient-a", "appointment_id": None,
             "doctor_id": None, "created_at": "2026-08-09", "last_updated": "2026-08-09"},
            {"id": "c", "patient_id": "patient-a", "appointment_id": None,
             "doctor_id": None, "created_at": "2026-08-09", "last_updated": "2026-08-09"},
        ]
        self.assertEqual(migration_016_match(report, candidates)["id"], "c")

    def test_zero_candidate_report_is_preserved_by_left_join_contract(self):
        report = {"patient_id": "patient-a", "appointment_id": None,
                  "doctor_id": None, "created_at": "2026-08-01"}
        later_legacy = [{"id": "later", "patient_id": "patient-a", "appointment_id": None,
                         "doctor_id": None, "created_at": "2026-08-02", "last_updated": "2026-08-02"}]
        self.assertIsNone(migration_016_match(report, later_legacy))
        body = self.body("list_doctor_consultation_history")
        self.assertIn("left join lateral", body)
        self.assertIn("'consultationid', matched_consultation.id", body)
        self.assertIn("'sessionnote', matched_consultation.session_note", body)
        self.assertIn("'procedures', coalesce(procedures.items, '[]'::jsonb)", body)

    def test_security_definer_and_privileges_are_contained(self):
        for signature in (
            "get_patient_consultation_history(uuid)",
            "list_doctor_consultation_history()",
        ):
            self.assertIn(f"revoke all on function public.{signature} from public", self.sql)
            self.assertIn(f"revoke execute on function public.{signature} from anon", self.sql)
            self.assertIn(f"grant execute on function public.{signature} to authenticated", self.sql)
        self.assertIn("security definer set search_path = pg_catalog, pg_temp", self.sql)
        self.assertIn("revoke all on table public.clinical_reports from authenticated", self.sql)
        self.assertIn("browser roles retain direct clinical_reports privileges", self.verify)

    def test_report_generation_and_persistence_are_not_migrated(self):
        for forbidden in ("ollama", "generate_report", "humanize_report", "update_report"):
            self.assertNotIn(forbidden, self.sql)


if __name__ == "__main__":
    unittest.main()
