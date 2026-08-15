from __future__ import annotations

from datetime import date
import unittest

from fastapi.testclient import TestClient

from tests.support import (
    TestingSessionLocal,
    active_main,
    add_patient,
    add_user,
    bearer_token,
    models,
    reset_database,
)


class PhaseF1FinanceTests(unittest.TestCase):
    def setUp(self):
        reset_database()
        self.client = TestClient(active_main.app)
        self.doctor_id = "10000000-0000-0000-0000-000000000001"
        self.patient_a = "20000000-0000-0000-0000-000000000001"
        self.patient_b = "20000000-0000-0000-0000-000000000002"
        add_user(user_id=self.doctor_id, email="doctor@example.test", role="doctor")
        add_user(user_id="10000000-0000-0000-0000-000000000002", email="desk@example.test", role="receptionist")
        add_patient(patient_id=self.patient_a)
        add_patient(patient_id=self.patient_b)
        self.headers = bearer_token("doctor@example.test")
        self.desk_headers = bearer_token("desk@example.test")

    def add_appointment(self, appointment_id, patient_id):
        db = TestingSessionLocal()
        try:
            db.add(models.Appointment(id=appointment_id, patient_id=patient_id, doctor_id=self.doctor_id, date=date.today(), time="09:00", status="pending"))
            db.commit()
        finally:
            db.close()

    def create_procedure(self, name="Extraction", price="100.00"):
        response = self.client.post("/api/clinic-procedures", json={"name": name, "price": price}, headers=self.headers)
        self.assertEqual(201, response.status_code, response.text)
        return response.json()

    def test_catalog_create_edit_search_and_inactive_behavior(self):
        extraction = self.create_procedure()
        self.create_procedure("Composite Filling", "80.25")
        names = [row["name"] for row in self.client.get("/api/clinic-procedures", headers=self.headers).json()]
        self.assertEqual(["Composite Filling", "Extraction"], names)
        self.assertEqual(["Extraction"], [name for name in names if "extract" in name.lower()])

        edited = self.client.patch(f"/api/clinic-procedures/{extraction['id']}", json={"name": "Simple Extraction", "price": "150.00"}, headers=self.headers)
        self.assertEqual(200, edited.status_code, edited.text)
        self.assertEqual("150.00", edited.json()["price"])
        inactive = self.client.patch(f"/api/clinic-procedures/{extraction['id']}", json={"is_active": False}, headers=self.headers)
        self.assertFalse(inactive.json()["isActive"])
        active_rows = self.client.get("/api/clinic-procedures?active_only=true", headers=self.headers).json()
        self.assertEqual(["Composite Filling"], [row["name"] for row in active_rows])

    def test_price_validation_and_doctor_authorization(self):
        for value in ("-1", "NaN", "Infinity", "1.001", "abc"):
            response = self.client.post("/api/clinic-procedures", json={"name": f"Invalid {value}", "price": value}, headers=self.headers)
            self.assertEqual(422, response.status_code, (value, response.text))
        self.assertEqual(403, self.client.get("/api/clinic-procedures", headers=self.desk_headers).status_code)

    def test_multiple_quantities_snapshot_history_and_new_consultation_price(self):
        extraction = self.create_procedure("Extraction", "100.00")
        filling = self.create_procedure("Filling", "80.00")
        self.add_appointment("30000000-0000-0000-0000-000000000001", self.patient_a)
        saved_a = self.client.put(f"/api/consultations/{self.patient_a}/procedures", json={"version": 0, "selections": [{"procedureId": extraction["id"], "quantity": 2}, {"procedureId": filling["id"], "quantity": 2}]}, headers=self.headers)
        self.assertEqual(200, saved_a.status_code, saved_a.text)
        self.assertEqual("360.00", saved_a.json()["total"])

        self.client.patch(f"/api/clinic-procedures/{extraction['id']}", json={"price": "150.00"}, headers=self.headers)
        historical_a = self.client.get(f"/api/consultations/{self.patient_a}/procedures", headers=self.headers).json()
        self.assertEqual("100.00", historical_a["items"][0]["unitPrice"])
        self.assertEqual("360.00", historical_a["total"])
        resaved_a = self.client.put(f"/api/consultations/{self.patient_a}/procedures", json={"version": historical_a["version"], "selections": [{"procedureId": extraction["id"], "quantity": 2}, {"procedureId": filling["id"], "quantity": 2}]}, headers=self.headers)
        self.assertEqual("100.00", resaved_a.json()["items"][0]["unitPrice"])

        self.add_appointment("30000000-0000-0000-0000-000000000002", self.patient_b)
        empty_b = self.client.get(f"/api/consultations/{self.patient_b}/procedures", headers=self.headers).json()
        self.assertEqual([], empty_b["items"])
        saved_b = self.client.put(f"/api/consultations/{self.patient_b}/procedures", json={"version": 0, "selections": [{"procedureId": extraction["id"], "quantity": 1}]}, headers=self.headers)
        self.assertEqual("150.00", saved_b.json()["items"][0]["unitPrice"])

        stale = self.client.put(f"/api/consultations/{self.patient_b}/procedures", json={"version": 0, "selections": []}, headers=self.headers)
        self.assertEqual(409, stale.status_code)

        db = TestingSessionLocal()
        try:
            consultations = db.query(models.Consultation).all()
            self.assertEqual(2, len(consultations))
            self.assertNotEqual(consultations[0].appointment_id, consultations[1].appointment_id)
            self.assertEqual("{}", consultations[0].data)
            self.assertIsNone(consultations[0].session_note)
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
