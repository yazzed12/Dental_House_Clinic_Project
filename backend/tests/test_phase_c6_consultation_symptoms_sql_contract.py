import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "migrations" / "013_consultation_symptoms_supabase_vertical_slice.sql"
PREFLIGHT = ROOT / "migrations" / "013_consultation_symptoms_production_preflight.sql"
VERIFY = ROOT / "migrations" / "013_consultation_symptoms_supabase_vertical_slice_verify.sql"


class ConsultationSymptomsSqlContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text()
        cls.normalized = re.sub(r"\s+", " ", cls.sql.lower())
        cls.preflight = PREFLIGHT.read_text().lower()
        cls.verify = VERIFY.read_text().lower()

    def function_body(self, name):
        match = re.search(
            rf"create or replace function public\.{name}\([\s\S]*?\$function\$;",
            self.sql,
            re.IGNORECASE,
        )
        self.assertIsNotNone(match, f"missing {name}")
        return re.sub(r"\s+", " ", match.group(0).lower())

    def test_preflight_is_read_only_and_inventories_required_production_state(self):
        for marker in (
            "to_regclass('public.symptoms')",
            "information_schema.columns",
            "pg_constraint",
            "relrowsecurity",
            "relforcerowsecurity",
            "pg_policies",
            "information_schema.table_privileges",
            "information_schema.triggers",
            "active_count",
            "inactive_count",
            "lower(btrim(name))",
            "creator.id is null",
            "order by lower(btrim(name))",
        ):
            self.assertIn(marker, self.preflight)
        executable = re.sub(r"--[^\n]*", "", self.preflight)
        self.assertNotRegex(
            executable,
            r"\b(insert|update|delete|alter|drop|create|grant|revoke|truncate)\b",
        )

    def test_list_requires_active_approved_doctor_or_admin_from_auth_uid(self):
        body = self.function_body("list_active_symptoms")
        self.assertIn("app_user.supabase_user_id = auth.uid()", body)
        self.assertIn("app_user.is_active = true", body)
        self.assertIn("app_user.approved_at is not null", body)
        self.assertIn("app_user.role in ('doctor', 'admin')", body)
        self.assertNotIn("receptionist", body)
        self.assertIn("using errcode = '42501'", body)

    def test_list_returns_only_active_id_name_in_deterministic_order(self):
        body = self.function_body("list_active_symptoms")
        self.assertIn("returns table ( id text, name text )", body)
        self.assertIn("symptom.is_active <> 0", body)
        self.assertIn("select symptom.id::text, btrim(symptom.name)::text", body)
        self.assertIn("order by lower(btrim(symptom.name)), symptom.id::text", body)
        for unnecessary in ("created_by", "created_at"):
            self.assertNotIn(unnecessary, body)
        self.assertNotIn("insert into public.symptoms", body)
        self.assertNotIn("default_symptoms", body)

    def test_create_trims_validates_and_derives_created_by(self):
        body = self.function_body("create_or_reactivate_symptom")
        self.assertIn("v_trimmed_name text := btrim(p_name)", body)
        self.assertIn("symptom_name_required", body)
        self.assertIn("lower(v_trimmed_name)", body)
        self.assertIn("created_by, is_active", body)
        self.assertIn("v_caller_id, 1", body)
        self.assertNotIn("p_created_by", body)

    def test_create_reuses_active_reactivates_inactive_and_serializes_duplicates(self):
        body = self.function_body("create_or_reactivate_symptom")
        self.assertIn("pg_advisory_xact_lock(hashtextextended(v_normalized_name, 0))", body)
        self.assertIn("lower(btrim(symptom.name)) = v_normalized_name", body)
        self.assertIn("case when symptom.is_active <> 0 then 0 else 1 end", body)
        self.assertIn("symptom.id::text", body)
        self.assertIn("for update", body)
        self.assertIn("set is_active = 1", body)
        self.assertIn("if v_symptom_id is not null", body)
        self.assertEqual(body.count("insert into public.symptoms"), 1)
        self.assertNotIn("unique index", self.normalized)
        self.assertNotIn("unique constraint", self.normalized)

    def test_rpc_only_containment_and_execution_privileges(self):
        self.assertIn("revoke all on table public.symptoms from public", self.normalized)
        self.assertIn("revoke all on table public.symptoms from anon", self.normalized)
        self.assertIn("revoke all on table public.symptoms from authenticated", self.normalized)
        self.assertIn("alter table public.symptoms enable row level security", self.normalized)
        for signature in ("list_active_symptoms()", "create_or_reactivate_symptom(text)"):
            self.assertIn(f"revoke all on function public.{signature} from public", self.normalized)
            self.assertIn(f"revoke execute on function public.{signature} from anon", self.normalized)
            self.assertIn(f"grant execute on function public.{signature} to authenticated", self.normalized)
        self.assertNotIn("service_role", self.normalized)

    def test_no_default_seed_and_verifier_covers_contract(self):
        self.assertNotIn("cold sensitivity", self.normalized)
        self.assertIn("no default data is seeded", self.normalized)
        for marker in (
            "has_table_privilege",
            "has_function_privilege",
            "pg_advisory_xact_lock",
            "symptom.is_active <> 0",
        ):
            self.assertIn(marker, self.verify)


if __name__ == "__main__":
    unittest.main()
