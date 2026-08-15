from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / "backend" / "migrations" / "009_eligible_doctors_rpc.sql"


class EligibleDoctorsSqlContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.normalized = " ".join(cls.sql.lower().split())

    def test_caller_identity_and_approval_are_server_authoritative(self):
        self.assertIn("caller.supabase_user_id = auth.uid()", self.normalized)
        self.assertIn("caller.is_active = true", self.normalized)
        self.assertIn("caller.approved_at is not null", self.normalized)
        self.assertIn("raise exception 'application access denied'", self.normalized)
        self.assertIn("errcode = '42501'", self.normalized)

    def test_only_eligible_linked_doctors_are_returned(self):
        self.assertIn("doctor.role = 'doctor'", self.normalized)
        self.assertIn("doctor.is_active = true", self.normalized)
        self.assertIn("doctor.approved_at is not null", self.normalized)
        self.assertIn("doctor.supabase_user_id is not null", self.normalized)

    def test_return_contract_contains_only_safe_selector_fields(self):
        returned_columns = self.normalized.split("returns table (", 1)[1].split(") language", 1)[0]
        self.assertEqual(
            "id uuid, full_name text, specialization text",
            returned_columns.strip(),
        )
        for forbidden in ("personal_email", "hashed_password", "password", "supabase_user_id"):
            self.assertNotIn(forbidden, returned_columns)

    def test_rpc_is_hardened_without_a_broad_users_grant(self):
        self.assertIn("security definer", self.normalized)
        self.assertIn("set search_path = pg_catalog, pg_temp", self.normalized)
        self.assertIn("revoke all on function public.get_eligible_doctors() from public", self.normalized)
        self.assertIn("revoke execute on function public.get_eligible_doctors() from anon", self.normalized)
        self.assertIn("grant execute on function public.get_eligible_doctors() to authenticated", self.normalized)
        self.assertNotIn("grant select on table public.users", self.normalized)
        self.assertNotIn("execute format", self.normalized)


if __name__ == "__main__":
    unittest.main()
