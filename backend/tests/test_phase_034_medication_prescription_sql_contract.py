from pathlib import Path
import unittest


MIGRATIONS = Path(__file__).resolve().parents[1] / "migrations"


class MedicationPrescriptionSqlContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.preflight = (MIGRATIONS / "034_medication_prescription_foundation_preflight.sql").read_text()
        cls.migration = (MIGRATIONS / "034_medication_prescription_foundation.sql").read_text()
        cls.verify = (MIGRATIONS / "034_medication_prescription_foundation_verify.sql").read_text()
        cls.lower = cls.migration.lower()

    def test_preflight_and_verify_are_read_only(self):
        for source in (self.preflight, self.verify):
            lowered = source.lower()
            self.assertNotIn("create table", lowered)
            self.assertNotIn("alter table", lowered)
            self.assertNotIn("insert into", lowered)
            self.assertNotIn("update public.", lowered)
            self.assertNotIn("delete from", lowered)
            self.assertNotIn("drop table", lowered)
        self.assertIn("CLEAN", self.preflight)
        self.assertIn("CONFLICT", self.preflight)
        self.assertIn("'PASS'", self.verify)
        self.assertIn("'FAIL'", self.verify)

    def test_required_tables_snapshot_and_provenance_fields_exist(self):
        for table in (
            "dental_medications", "medication_clinical_presets",
            "doctor_medication_presets", "medication_import_batches",
            "medication_import_rejections", "prescriptions", "prescription_items",
        ):
            self.assertIn(f"create table public.{table}", self.lower)
        for field in (
            "brand_name_snapshot", "generic_name_snapshot", "strength_snapshot",
            "dosage_form_snapshot", "route_snapshot", "dose_snapshot",
            "frequency_snapshot", "duration_snapshot", "instructions_snapshot",
            "source_name_snapshot", "source_reference_snapshot", "source_version_snapshot",
            "source_record_id", "verification_status", "licensing_status", "import_batch_id",
        ):
            self.assertIn(field, self.lower)

    def test_search_index_visibility_and_authority_boundaries_exist(self):
        self.assertIn("using gin(search_document)", self.lower)
        self.assertIn("text_pattern_ops", self.lower)
        self.assertIn("dental_medications_authority_ck", self.lower)
        self.assertIn("catalog_scope='global'", self.lower)
        self.assertIn("licensing_status='approved'", self.lower)
        self.assertIn("verification_status='verified'", self.lower)
        self.assertNotIn("create extension", self.lower)

    def test_rls_acl_and_secure_rpc_contract(self):
        for table in (
            "medication_import_batches", "medication_import_rejections",
            "dental_medications", "medication_clinical_presets",
            "doctor_medication_presets", "prescriptions", "prescription_items",
        ):
            self.assertIn(f"alter table public.{table} enable row level security", self.lower)
        self.assertIn("security definer", self.lower)
        self.assertIn("set search_path=pg_catalog,pg_temp", self.lower)
        self.assertIn("from anon", self.lower)
        self.assertNotIn("using (true)", self.lower)
        for function in (
            "search_dental_medications", "create_custom_medication",
            "get_effective_medication_preset", "save_prescription_draft",
            "approve_prescription",
        ):
            self.assertIn(f"function public.{function}", self.lower)

    def test_lifecycle_immutability_history_and_finish_barrier_exist(self):
        self.assertIn("prescriptions_approved_immutability", self.lower)
        self.assertIn("prescription_items_approved_immutability", self.lower)
        self.assertIn("approved_prescription_immutable", self.lower)
        self.assertIn("prescription_review_required", self.lower)
        self.assertIn("security.prescription_projection", self.lower)
        self.assertIn("public.list_doctor_consultation_history", self.lower)

    def test_no_real_medication_or_clinical_seed_is_present(self):
        schema_section = self.lower.split("create function security.medication_prescription_actor", 1)[0]
        self.assertNotIn("insert into public.dental_medications", schema_section)
        self.assertNotIn("insert into public.medication_clinical_presets", schema_section)


if __name__ == "__main__":
    unittest.main()
