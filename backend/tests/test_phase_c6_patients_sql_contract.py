from pathlib import Path
import unittest


class TestPatientsSqlContract(unittest.TestCase):
    def setUp(self):
        self.migration_path = (
            Path(__file__).parent.parent / "migrations" / "007_patients_rls_and_rpc.sql"
        )
        self.verify_path = (
            Path(__file__).parent.parent / "migrations" / "007_patients_rls_and_rpc_verify.sql"
        )
        self.assertTrue(self.migration_path.exists(), "Migration 007 file missing")
        self.assertTrue(self.verify_path.exists(), "Migration 007 verify file missing")
        self.sql = self.migration_path.read_text(encoding="utf-8")
        self.verify_sql = self.verify_path.read_text(encoding="utf-8")

    def test_table_grants_authenticated_only(self):
        self.assertIn("GRANT SELECT, INSERT, UPDATE ON TABLE public.patients TO authenticated;", self.sql)
        self.assertNotIn("DELETE", self.sql.split("GRANT SELECT, INSERT, UPDATE")[1].split("TO authenticated;")[0])
        self.assertNotIn("GRANT ALL ON TABLE public.patients TO anon", self.sql)

    def test_rls_policies_use_security_is_active_approved_user(self):
        self.assertIn("patient_select_policy", self.sql)
        self.assertIn("patient_insert_policy", self.sql)
        self.assertIn("patient_update_policy", self.sql)
        self.assertIn("security.is_active_approved_user()", self.sql)
        self.assertNotIn("CREATE POLICY patient_delete_policy", self.sql)

    def test_rpc_definition_and_security_definer(self):
        self.assertIn("CREATE OR REPLACE FUNCTION public.safe_delete_patient", self.sql)
        self.assertIn("SECURITY DEFINER", self.sql)
        self.assertIn("SET search_path = pg_catalog, pg_temp", self.sql)
        self.assertIn("security.current_app_user_id()", self.sql)
        self.assertIn("security.is_doctor()", self.sql)
        self.assertIn("security.is_admin()", self.sql)

    def test_rpc_history_checks_all_six_verified_tables(self):
        history_tables = [
            "public.appointments",
            "public.records",
            "public.consultations",
            "public.clinical_reports",
            "public.patient_dental_state",
            "public.logs",
        ]
        for tbl in history_tables:
            self.assertIn(tbl, self.sql)

        # Must NOT reference patient_care_team
        self.assertNotIn("patient_care_team", self.sql)

    def test_log_doctor_id_column(self):
        self.assertIn("doctor_id", self.sql)
        self.assertNotIn("logs (id, message, user_id", self.sql)

    def test_rpc_privilege_hardening(self):
        self.assertIn("REVOKE ALL ON FUNCTION public.safe_delete_patient(uuid) FROM PUBLIC;", self.sql)
        self.assertIn("REVOKE EXECUTE ON FUNCTION public.safe_delete_patient(uuid) FROM anon;", self.sql)
        self.assertIn("GRANT EXECUTE ON FUNCTION public.safe_delete_patient(uuid) TO authenticated;", self.sql)


if __name__ == "__main__":
    unittest.main()
