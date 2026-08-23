from datetime import date
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from tests.support import (
    TestingSessionLocal, active_main, add_patient, add_user, bearer_token, models,
    reset_database,
)


DOCTOR_ID = "10000000-0000-0000-0000-000000000001"
OTHER_DOCTOR_ID = "10000000-0000-0000-0000-000000000002"
ADMIN_ID = "10000000-0000-0000-0000-000000000003"
PATIENT_ID = "20000000-0000-0000-0000-000000000001"
APPOINTMENT_ID = "30000000-0000-0000-0000-000000000001"


class MedicationPrescriptionWorkflowTests(unittest.TestCase):
    def setUp(self):
        reset_database(); self.client = TestClient(active_main.app)
        add_user(user_id=DOCTOR_ID, email="doctor@example.test", role="doctor")
        add_user(user_id=OTHER_DOCTOR_ID, email="other@example.test", role="doctor")
        add_user(user_id=ADMIN_ID, email="admin@example.test", role="admin")
        add_patient(patient_id=PATIENT_ID)
        db = TestingSessionLocal()
        try:
            db.add(models.Appointment(
                id=APPOINTMENT_ID, patient_id=PATIENT_ID, doctor_id=DOCTOR_ID,
                date=date.today(), time="09:00", type="consultation", status="pending",
            ))
            db.commit()
        finally:
            db.close()
        self.headers = bearer_token("doctor@example.test")

    def _consultation_id(self):
        response = self.client.post(f"/api/consultations/{PATIENT_ID}",
            json={"toothData": {}, "version": 0}, headers=self.headers)
        self.assertEqual(200, response.status_code, response.text)
        return response.json()["consultationId"]

    def _custom_medication(self):
        response = self.client.post("/api/medications/custom", json={
            "brand_name": "SYNTH Fixture", "generic_name": "Synthetic ingredient",
            "strength": "1 fake-unit", "dosage_form": "Fixture form",
            "route": "Fixture route", "category": "Test only",
        }, headers=self.headers)
        self.assertEqual(200, response.status_code, response.text)
        medication = response.json()
        self.assertEqual({
            "id", "brandName", "genericName", "strength", "dosageForm", "route",
            "category", "manufacturer", "market", "catalogScope", "isCustom",
            "verificationStatus", "sourceType", "sourceName", "sourceReference",
            "sourceVersion", "sourceRecordId",
        }, set(medication))
        return medication

    @staticmethod
    def _item(medication):
        return {
            "medicationId": medication["id"], "clinicalPresetId": None,
            "doctorPresetId": None, "brandName": medication["brandName"],
            "genericName": medication["genericName"], "strength": medication["strength"],
            "dosageForm": medication["dosageForm"], "route": medication["route"],
            "dose": "Doctor-entered synthetic dose", "frequency": "Doctor-entered frequency",
            "duration": "Doctor-entered duration", "instructions": "Synthetic instructions",
            "doctorNotes": "Test-only note",
        }

    def test_unauthenticated_medication_access_is_denied(self):
        self.assertEqual(401, self.client.get("/api/medications?q=test").status_code)

    def test_invalid_custom_medication_is_rejected(self):
        response = self.client.post("/api/medications/custom", json={
            "brand_name": "", "strength": "", "dosage_form": "", "route": "",
        }, headers=self.headers)
        self.assertEqual(422, response.status_code)

    def test_draft_review_ownership_approval_and_snapshot_preservation(self):
        consultation_id = self._consultation_id(); medication = self._custom_medication()
        draft = self.client.put(f"/api/consultations/{consultation_id}/prescription/draft",
            json={"expectedVersion": 0, "items": [self._item(medication)]}, headers=self.headers)
        self.assertEqual(200, draft.status_code, draft.text)
        self.assertEqual("draft", draft.json()["status"])

        blocked_finish = self.client.post(f"/api/appointments/finish-by-patient/{PATIENT_ID}", headers=self.headers)
        self.assertEqual(409, blocked_finish.status_code)
        self.assertEqual("PRESCRIPTION_REVIEW_REQUIRED", blocked_finish.json()["detail"])

        unauthorized = self.client.post(
            f"/api/prescriptions/{draft.json()['id']}/approve",
            json={"expectedVersion": draft.json()["version"]},
            headers=bearer_token("other@example.test"),
        )
        self.assertEqual(403, unauthorized.status_code)

        approved = self.client.post(f"/api/prescriptions/{draft.json()['id']}/approve",
            json={"expectedVersion": draft.json()["version"]}, headers=self.headers)
        self.assertEqual(200, approved.status_code, approved.text)
        self.assertEqual("approved", approved.json()["status"])
        original_brand = approved.json()["items"][0]["brandName"]

        db = TestingSessionLocal()
        try:
            db.query(models.DentalMedication).filter(models.DentalMedication.id == medication["id"]).update({"brand_name": "Catalog renamed later"})
            db.commit()
        finally:
            db.close()
        historical = self.client.get(f"/api/consultations/{PATIENT_ID}/history", headers=self.headers)
        self.assertEqual(original_brand, historical.json()[0]["prescription"]["items"][0]["brandName"])

        captured = {}
        async def capture_report(payload):
            captured.update(payload)
            return "synthetic report"
        with patch.object(active_main, "generate_clinical_report", new=capture_report):
            report = self.client.post("/api/ai/generate-report", json={
                "consultationId": consultation_id,
                "approvedPrescription": {"status": "approved", "items": [{"brandName": "ATTACKER VALUE"}]},
            }, headers=self.headers)
        self.assertEqual(200, report.status_code, report.text)
        self.assertEqual(original_brand, captured["approvedPrescription"]["items"][0]["brandName"])
        self.assertNotIn("ATTACKER VALUE", str(captured))

    def test_normalized_search_and_details_hide_non_authoritative_imports(self):
        custom = self._custom_medication()
        response = self.client.get("/api/medications?q=synth%20%20fixture", headers=self.headers)
        self.assertEqual(200, response.status_code, response.text)
        self.assertEqual(custom["id"], response.json()[0]["id"])
        details = self.client.get(f"/api/medications/{custom['id']}", headers=self.headers)
        self.assertEqual(200, details.status_code, details.text)
        self.assertEqual("unverified", details.json()["verificationStatus"])

    def test_import_is_admin_only_idempotent_and_reports_rejections(self):
        payload = {
            "source_name": "Synthetic Catalog Fixture", "source_version": "v1",
            "source_reference": "fixture://approved-test", "market": "Test Market",
            "country": "Testland", "input_format": "csv", "preview": False,
            "content": "source_record_id,brand_name,strength,dosage_form,route,verification_status\nfake-1,Fixture,1 unit,Form,Route,verified\nbad-1,Missing,,,Route,pending\n",
        }
        denied = self.client.post("/api/admin/medications/import", json=payload, headers=self.headers)
        self.assertEqual(403, denied.status_code)
        preview_payload = {**payload, "preview": True}
        preview = self.client.post("/api/admin/medications/import", json=preview_payload,
            headers=bearer_token("admin@example.test"))
        self.assertEqual(200, preview.status_code, preview.text)
        self.assertTrue(preview.json()["preview"])
        self.assertEqual(1, preview.json()["inserted"])
        self.assertEqual(1, preview.json()["rejected"])
        db = TestingSessionLocal()
        try:
            self.assertEqual(0, db.query(models.DentalMedication).count())
            self.assertEqual(0, db.query(models.MedicationImportBatch).count())
        finally:
            db.close()
        first = self.client.post("/api/admin/medications/import", json=payload,
            headers=bearer_token("admin@example.test"))
        self.assertEqual(200, first.status_code, first.text)
        self.assertEqual(1, first.json()["inserted"]); self.assertEqual(1, first.json()["rejected"])
        second = self.client.post("/api/admin/medications/import", json=payload,
            headers=bearer_token("admin@example.test"))
        self.assertEqual(200, second.status_code, second.text)
        self.assertEqual(1, second.json()["unchanged"]); self.assertEqual(0, second.json()["inserted"])

        db = TestingSessionLocal()
        try:
            imported = db.query(models.DentalMedication).filter(
                models.DentalMedication.source_record_id == "fake-1"
            ).one()
            self.assertEqual("global", imported.catalog_scope)
            self.assertEqual("structured_import", imported.source_type)
            self.assertEqual("Synthetic Catalog Fixture", imported.source_name)
            self.assertEqual("fixture://approved-test", imported.source_reference)
            self.assertEqual("v1", imported.source_version)
            self.assertEqual("verified", imported.verification_status)
            self.assertIsNotNone(imported.import_batch_id)
            self.assertIsNotNone(imported.imported_at)
        finally:
            db.close()

        searchable = self.client.get("/api/medications?q=fixture", headers=self.headers)
        self.assertEqual(200, searchable.status_code, searchable.text)
        self.assertEqual("fake-1", searchable.json()[0]["sourceRecordId"])
        self.assertEqual("verified", searchable.json()[0]["verificationStatus"])

        changed = dict(payload)
        changed["content"] = payload["content"].replace("Fixture,1 unit", "Fixture,2 units")
        third = self.client.post("/api/admin/medications/import", json=changed,
            headers=bearer_token("admin@example.test"))
        self.assertEqual(200, third.status_code, third.text)
        self.assertEqual(1, third.json()["updated"])
        db = TestingSessionLocal()
        try:
            rows = db.query(models.DentalMedication).filter(
                models.DentalMedication.source_record_id == "fake-1"
            ).all()
            self.assertEqual(1, len(rows))
            self.assertEqual("2 units", rows[0].strength)
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
