from pathlib import Path
import unittest


class TestSecurityContainmentPatientsContract(unittest.TestCase):
    def setUp(self):
        self.migration_path = (
            Path(__file__).parent.parent / "migrations" / "005_security_containment_patients.sql"
        )
        self.verify_path = (
            Path(__file__).parent.parent / "migrations" / "005_security_containment_patients_verify.sql"
        )
        self.assertTrue(self.migration_path.exists(), "Migration 005 containment file missing")
        self.assertTrue(self.verify_path.exists(), "Migration 005 containment verify file missing")
        self.sql = self.migration_path.read_text(encoding="utf-8")
        self.verify_sql = self.verify_path.read_text(encoding="utf-8")

    def test_touches_only_public_patients(self):
        # Must only reference public.patients, not any other table
        self.assertIn("ON public.patients", self.sql)
        self.assertIn("TABLE public.patients", self.sql)
        self.assertNotIn("ON ALL TABLES", self.sql)

    def test_does_not_contain_schema_wide_revoke(self):
        self.assertNotIn("SCHEMA public", self.sql)
        self.assertNotIn("ON ALL FUNCTIONS", self.sql)
        self.assertNotIn("ON ALL SEQUENCES", self.sql)

    def test_does_not_force_row_level_security(self):
        self.assertNotIn("FORCE ROW LEVEL SECURITY", self.sql)
        self.assertIn("ENABLE ROW LEVEL SECURITY", self.sql)

    def test_does_not_modify_table_data(self):
        # Must contain zero DML data mutation statements
        sql_upper = self.sql.upper()
        self.assertNotIn("INSERT INTO", sql_upper)
        self.assertNotIn("UPDATE public.patients SET", sql_upper)
        self.assertNotIn("DELETE FROM", sql_upper)

    def test_drops_exactly_the_five_verified_policies(self):
        verified_policies = [
            "Allow all",
            "Allow clinic staff to insert patients",
            "Allow clinic staff to read patients",
            "Allow clinic staff to update patients",
            "Allow initial data migration",
        ]
        for policy in verified_policies:
            expected_stmt = f'DROP POLICY IF EXISTS "{policy}" ON public.patients;'
            self.assertIn(expected_stmt, self.sql)

    def test_revokes_privileges_from_public_anon_authenticated(self):
        self.assertIn("REVOKE ALL ON TABLE public.patients FROM PUBLIC;", self.sql)
        self.assertIn("REVOKE ALL ON TABLE public.patients FROM anon;", self.sql)
        self.assertIn("REVOKE ALL ON TABLE public.patients FROM authenticated;", self.sql)

    def test_verify_script_checks(self):
        self.assertIn("relrowsecurity", self.verify_sql)
        self.assertIn("relforcerowsecurity", self.verify_sql)
        self.assertIn("information_schema.role_table_grants", self.verify_sql)


if __name__ == "__main__":
    unittest.main()
