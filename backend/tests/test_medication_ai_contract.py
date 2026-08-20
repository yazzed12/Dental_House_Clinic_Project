from pathlib import Path
import unittest


BACKEND = Path(__file__).resolve().parents[1]


class MedicationAiContractTests(unittest.TestCase):
    def test_prompt_treats_approved_prescription_as_immutable(self):
        prompt = (BACKEND / "ai_service.py").read_text().lower()
        for rule in (
            "approvedprescription value is immutable clinician-approved source data",
            "do not add or remove a medication",
            "do not change or infer brand, generic, strength, dosage form, route, dose, frequency, duration, or instructions",
            "do not add interactions, contraindications, side effects, pharmacological rationale, dosage advice, or postoperative medication advice",
            "do not fabricate any prescription",
        ):
            self.assertIn(rule, prompt)

    def test_server_replaces_browser_prescription_with_stored_approved_snapshot(self):
        service = (BACKEND / "app/services/report_service.py").read_text()
        self.assertIn('authoritative_payload = dict(payload)', service)
        self.assertIn('authoritative_payload["approvedPrescription"]', service)
        self.assertIn("get_approved_prescription", service)


if __name__ == "__main__":
    unittest.main()
