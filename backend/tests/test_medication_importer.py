import json
import unittest

from app.medications.importer import normalize_import_rows, parse_import_content


class MedicationImporterTests(unittest.TestCase):
    def test_synthetic_csv_normalizes_and_preserves_statuses(self):
        csv_text = """source_record_id,brand_name,generic_name,strength,dosage_form,route,category,verification_status,licensing_status,is_active
fake-1,  SYNTH Brand  ,Synthetic ingredient, 10 fake-units , Test Form , Test Route , Test Category ,verified,approved,true
"""
        rows = parse_import_content("csv", csv_text)
        accepted, rejected = normalize_import_rows(rows, market="Synthetic Test Market", country="Testland")
        self.assertEqual([], rejected)
        self.assertEqual(1, len(accepted))
        values = accepted[0].values
        self.assertEqual("SYNTH Brand", values["brand_name"])
        self.assertEqual("10 fake-units", values["strength"])
        self.assertEqual("verified", values["verification_status"])
        self.assertEqual("approved", values["licensing_status"])
        self.assertIn("synth brand|synthetic ingredient", values["identity_key"])

    def test_synthetic_json_supports_aliases_and_derived_source_id(self):
        rows = parse_import_content("json", json.dumps({"medications": [{
            "trade_name": "Fixture Product", "active_ingredient": "Fixture Ingredient",
            "strength": "1 unit", "form": "Fixture Form", "route": "Fixture Route",
        }]}))
        accepted, rejected = normalize_import_rows(rows, market="Fixture Market")
        self.assertEqual([], rejected)
        self.assertTrue(accepted[0].values["source_record_id"].startswith("derived:"))

    def test_duplicates_and_invalid_rows_are_reported_not_silently_dropped(self):
        rows = [
            {"id": "dup", "brand_name": "Fixture", "strength": "1", "dosage_form": "Form", "route": "Route"},
            {"id": "dup", "brand_name": "Fixture 2", "strength": "2", "dosage_form": "Form", "route": "Route"},
            {"id": "bad", "brand_name": "Missing fields"},
            {"id": "status", "brand_name": "Fixture 3", "strength": "3", "dosage_form": "Form", "route": "Route", "licensing_status": "made-up"},
        ]
        accepted, rejected = normalize_import_rows(rows, market="Fixture Market")
        self.assertEqual(1, len(accepted))
        self.assertEqual(3, len(rejected))
        self.assertTrue(rejected[0].duplicate)
        self.assertIn("strength is required", rejected[1].reasons)
        self.assertIn("licensing_status is invalid", rejected[2].reasons)

    def test_inactive_withdrawn_rows_are_retained_as_inactive(self):
        accepted, rejected = normalize_import_rows([{
            "id": "inactive-1", "brand": "Fixture", "strength": "1",
            "form": "Fixture Form", "route": "Fixture Route", "status": "withdrawn",
        }], market="Fixture Market")
        self.assertEqual([], rejected)
        self.assertFalse(accepted[0].values["is_active"])


if __name__ == "__main__":
    unittest.main()
