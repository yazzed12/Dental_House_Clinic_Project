from pathlib import Path
import unittest


class TestAuthRlsHelpersContract(unittest.TestCase):
    def setUp(self):
        self.migration_path = (
            Path(__file__).parent.parent / "migrations" / "006_auth_rls_helpers.sql"
        )
        self.verify_path = (
            Path(__file__).parent.parent / "migrations" / "006_auth_rls_helpers_verify.sql"
        )
        self.assertTrue(self.migration_path.exists(), "Migration 006 file missing")
        self.assertTrue(self.verify_path.exists(), "Migration 006 verify file missing")
        self.sql = self.migration_path.read_text(encoding="utf-8")
        self.verify_sql = self.verify_path.read_text(encoding="utf-8")

    def test_creates_and_hardens_trusted_security_schema(self):
        self.assertIn("CREATE SCHEMA IF NOT EXISTS security;", self.sql)
        self.assertIn("REVOKE ALL ON SCHEMA security FROM PUBLIC;", self.sql)
        self.assertIn("REVOKE ALL ON SCHEMA security FROM anon;", self.sql)
        self.assertIn("GRANT USAGE ON SCHEMA security TO authenticated;", self.sql)
        self.assertIn("REVOKE CREATE ON SCHEMA security FROM authenticated;", self.sql)

    def test_contains_exactly_the_five_approved_helpers_in_security_schema(self):
        approved_helpers = [
            "current_app_user_id",
            "current_app_role",
            "is_active_approved_user",
            "is_doctor",
            "is_admin",
        ]
        for func in approved_helpers:
            self.assertIn(f"CREATE OR REPLACE FUNCTION security.{func}", self.sql)
            self.assertNotIn(f"CREATE OR REPLACE FUNCTION public.{func}", self.sql)

        unapproved_helpers = [
            "is_receptionist",
            "has_active_patient_relationship",
            "had_patient_relationship_at",
            "can_read_clinical_event",
        ]
        for func in unapproved_helpers:
            self.assertNotIn(func, self.sql)

    def test_identity_resolution_uses_auth_uid_and_public_users(self):
        self.assertIn("auth.uid()", self.sql)
        self.assertIn("public.users", self.sql)
        self.assertIn("u.supabase_user_id = auth.uid()", self.sql)
        self.assertIn("u.is_active = true", self.sql)
        self.assertIn("u.approved_at IS NOT NULL", self.sql)

    def test_no_jwt_metadata_trust(self):
        self.assertIn("SELECT u.role", self.sql)
        self.assertNotIn("auth.jwt()", self.sql)

    def test_no_unrelated_table_references_or_dynamic_sql(self):
        self.assertNotIn("patient_care_team", self.sql)
        self.assertNotIn("patients", self.sql)
        self.assertNotIn("EXECUTE FORMAT", self.sql.upper())
        self.assertNotIn("EXECUTE IMMEDIATE", self.sql.upper())

    def test_security_definer_and_search_path_hardening(self):
        approved_helpers = [
            "current_app_user_id()",
            "current_app_role()",
            "is_active_approved_user()",
            "is_doctor()",
            "is_admin()",
        ]
        for func in approved_helpers:
            self.assertIn("SECURITY DEFINER", self.sql)
            self.assertIn("SET search_path = pg_catalog, pg_temp", self.sql)

    def test_minimum_privilege_hardening(self):
        all_helpers = [
            "current_app_user_id()",
            "current_app_role()",
            "is_active_approved_user()",
            "is_doctor()",
            "is_admin()",
        ]
        for func in all_helpers:
            self.assertIn(f"REVOKE ALL ON FUNCTION security.{func} FROM PUBLIC;", self.sql)

        internal_helpers = [
            "current_app_user_id()",
            "current_app_role()",
            "is_doctor()",
            "is_admin()",
        ]
        for func in internal_helpers:
            self.assertNotIn(f"GRANT EXECUTE ON FUNCTION security.{func} TO authenticated;", self.sql)

        # ONLY security.is_active_approved_user() is granted EXECUTE to authenticated
        self.assertIn("GRANT EXECUTE ON FUNCTION security.is_active_approved_user() TO authenticated;", self.sql)

    def test_no_table_policy_or_grant_changes(self):
        self.assertNotIn("CREATE POLICY", self.sql)
        self.assertNotIn("DROP POLICY", self.sql)
        self.assertNotIn("GRANT ALL ON TABLE", self.sql)
        self.assertNotIn("REVOKE ALL ON TABLE", self.sql)


if __name__ == "__main__":
    unittest.main()
