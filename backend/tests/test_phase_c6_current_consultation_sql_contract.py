import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "migrations" / "012_current_consultation_supabase_vertical_slice.sql"
VERIFY = ROOT / "migrations" / "012_current_consultation_supabase_vertical_slice_verify.sql"
PREFLIGHT = ROOT / "migrations" / "012_current_consultation_production_preflight.sql"


class CurrentConsultationSqlContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text()
        cls.normalized = re.sub(r"\s+", " ", cls.sql.lower())
        cls.verify = VERIFY.read_text().lower()
        cls.preflight = PREFLIGHT.read_text().lower()

    def function_body(self, name):
        match = re.search(
            rf"create or replace function public\.{name}\([\s\S]*?\$function\$;",
            self.sql,
            re.IGNORECASE,
        )
        self.assertIsNotNone(match, f"missing {name}")
        return re.sub(r"\s+", " ", match.group(0).lower())

    def test_caller_is_auth_uid_derived_active_approved_doctor_or_admin(self):
        for name in ("get_or_initialize_consultation", "save_current_consultation"):
            body = self.function_body(name)
            self.assertIn("app_user.supabase_user_id = auth.uid()", body)
            self.assertIn("app_user.is_active = true", body)
            self.assertIn("app_user.approved_at is not null", body)
            self.assertIn("app_user.role in ('doctor', 'admin')", body)
            self.assertNotIn("p_doctor_id", body)

    def test_patient_and_current_appointment_are_validated_deterministically(self):
        for name in ("get_or_initialize_consultation", "save_current_consultation"):
            body = self.function_body(name)
            self.assertIn("consultation_patient_not_found", body)
            self.assertIn("consultation_no_current_appointment", body)
            self.assertIn("appointment.status::text in ('pending', 'confirmed')", body)
            self.assertIn("appointment.doctor_id = v_caller_id", body)
            self.assertIn("appointment.appointment_time asc nulls last", body)
            self.assertIn("appointment.id asc", body)
            self.assertNotIn("latest_by_patient", body)

    def test_ownership_locks_versions_atomic_writes_and_audit_are_present(self):
        body = self.function_body("save_current_consultation")
        self.assertIn("consultation_ownership_mismatch", body)
        self.assertGreaterEqual(body.count("for update"), 3)
        self.assertIn("consultation_version_conflict", body)
        self.assertIn("consultation_dental_state_version_conflict", body)
        self.assertIn("update public.consultations", body)
        self.assertIn("insert into public.consultations", body)
        self.assertIn("update public.patient_dental_state", body)
        self.assertIn("insert into public.patient_dental_state", body)
        self.assertIn("insert into public.logs", body)
        self.assertIn("version = consultation.version + 1", body)
        self.assertIn("version = dental_state.version + 1", body)

    def test_read_preserves_virtual_initialization_and_dental_inheritance(self):
        body = self.function_body("get_or_initialize_consultation")
        self.assertIn("'version', coalesce(v_consultation.version, 0)", body)
        self.assertIn("'dentalstateversion', coalesce(v_dental_state.version, 0)", body)
        self.assertIn("v_dental_state.data::jsonb", body)
        self.assertIn("'{}'::jsonb", body)
        self.assertIn("'lastconsultationnote'", body)

    def test_direct_table_access_is_contained_and_rpc_execution_is_minimal(self):
        self.assertIn(
            'drop policy if exists "allow clinic staff full access" on public.consultations',
            self.normalized,
        )
        for table in ("consultations", "patient_dental_state"):
            self.assertIn(f"revoke all on table public.{table} from public", self.normalized)
            self.assertIn(f"revoke all on table public.{table} from anon", self.normalized)
            self.assertIn(f"revoke all on table public.{table} from authenticated", self.normalized)
            self.assertIn(f"alter table public.{table} enable row level security", self.normalized)
        self.assertNotIn("grant select", self.normalized)
        self.assertNotIn("grant insert", self.normalized)
        self.assertNotIn("grant update", self.normalized)
        self.assertIn("security definer", self.normalized)
        self.assertIn("set search_path = pg_catalog, pg_temp", self.normalized)
        self.assertIn("grant execute on function public.get_or_initialize_consultation(uuid) to authenticated", self.normalized)
        self.assertIn("grant execute on function public.save_current_consultation(uuid, jsonb, integer, integer, text, boolean) to authenticated", self.normalized)

    def test_scope_excludes_history_reports_procedures_billing_and_service_role(self):
        self.assertNotIn("clinical_reports", self.normalized)
        self.assertNotIn("consultation_procedures", self.normalized)
        self.assertNotIn("financial_", self.normalized)
        self.assertNotIn("service_role", self.normalized)
        self.assertNotIn("alter type", self.normalized)

    def test_verifier_and_read_only_preflight_cover_production_risks(self):
        self.assertIn("relrowsecurity", self.verify)
        self.assertIn("has_table_privilege", self.verify)
        self.assertIn("has_function_privilege", self.verify)
        for marker in ("information_schema.columns", "pg_constraint", "pg_policies", "role_table_grants", "information_schema.triggers", "pg_enum"):
            self.assertIn(marker, self.preflight)
        self.assertNotRegex(self.preflight, r"\b(insert|update|delete|alter|drop|create|grant|revoke)\b")


if __name__ == "__main__":
    unittest.main()
