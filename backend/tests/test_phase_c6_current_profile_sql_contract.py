from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / "backend" / "migrations" / "008_current_app_profile_rpc.sql"


class CurrentApplicationProfileSqlContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.normalized = " ".join(cls.sql.lower().split())

    def test_identity_and_approval_are_server_authoritative(self):
        self.assertIn("u.supabase_user_id = auth.uid()", self.normalized)
        self.assertIn("u.is_active = true", self.normalized)
        self.assertIn("u.approved_at is not null", self.normalized)

    def test_only_safe_profile_fields_are_returned(self):
        returned_columns = self.normalized.split("returns table (", 1)[1].split(") language sql", 1)[0]
        for forbidden in ("personal_email", "hashed_password", "password"):
            self.assertNotIn(forbidden, returned_columns)

    def test_rpc_is_hardened_and_not_a_broad_table_grant(self):
        self.assertIn("security definer", self.normalized)
        self.assertIn("set search_path = pg_catalog, pg_temp", self.normalized)
        self.assertIn("revoke all on function public.get_current_app_profile() from public", self.normalized)
        self.assertIn("revoke execute on function public.get_current_app_profile() from anon", self.normalized)
        self.assertIn("grant execute on function public.get_current_app_profile() to authenticated", self.normalized)
        self.assertNotIn("grant select on table public.users", self.normalized)


if __name__ == "__main__":
    unittest.main()
