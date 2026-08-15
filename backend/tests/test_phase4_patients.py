from __future__ import annotations

import unittest
from datetime import date

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


PATIENT_FIELDS = {
    "id",
    "name",
    "age",
    "phone",
    "gender",
    "status",
    "condition",
    "lastVisit",
    "bloodType",
}


class Phase4PatientRouteTests(unittest.TestCase):
    def setUp(self):
        reset_database()
        self.client = TestClient(active_main.app)
        add_user(user_id="doctor-1", email="doctor@example.test", role="doctor")
        add_user(
            user_id="reception-1",
            email="reception@example.test",
            role="receptionist",
        )
        add_user(user_id="patient-user", email="patient@example.test", role="patient")
        self.doctor_headers = bearer_token("doctor@example.test")
        self.reception_headers = bearer_token("reception@example.test")
        self.patient_headers = bearer_token("patient@example.test")

    def test_list_and_detail_preserve_camel_case_contract(self):
        add_patient(patient_id="123")

        listed = self.client.get("/api/patients", headers=self.doctor_headers)
        self.assertEqual(200, listed.status_code)
        self.assertEqual(PATIENT_FIELDS, set(listed.json()[0]))
        self.assertEqual("2026-08-01", listed.json()[0]["lastVisit"])
        self.assertEqual("O+", listed.json()[0]["bloodType"])

        detailed = self.client.get("/api/patients/123", headers=self.doctor_headers)
        self.assertEqual(200, detailed.status_code)
        self.assertEqual(PATIENT_FIELDS, set(detailed.json()))
        self.assertEqual("123", detailed.json()["id"])

    def test_create_and_update_contracts(self):
        created = self.client.post(
            "/api/patients",
            json={
                "name": "New Patient",
                "age": 29,
                "last_visit": "2026-08-05",
                "blood_type": "A+",
            },
            headers=self.reception_headers,
        )
        self.assertEqual(200, created.status_code, created.text)
        self.assertEqual(PATIENT_FIELDS, set(created.json()))
        self.assertIsNotNone(created.json()["id"])
        self.assertTrue(created.json()["id"])
        self.assertEqual("2026-08-05", created.json()["lastVisit"])
        self.assertEqual("A+", created.json()["bloodType"])

        updated = self.client.put(
            f"/api/patients/{created.json()['id']}",
            json={"name": "Updated Patient", "blood_type": "AB-"},
            headers=self.reception_headers,
        )
        self.assertEqual(200, updated.status_code)
        self.assertEqual("success", updated.json()["status"])
        self.assertEqual(
            {"id", "name", "age", "phone", "gender", "status", "condition", "bloodType"},
            set(updated.json()["patient"]),
        )
        self.assertEqual("Updated Patient", updated.json()["patient"]["name"])
        self.assertEqual("AB-", updated.json()["patient"]["bloodType"])

    def test_patient_not_found_contracts(self):
        detail = self.client.get("/api/patients/missing", headers=self.doctor_headers)
        update = self.client.put(
            "/api/patients/missing",
            json={"name": "Missing"},
            headers=self.reception_headers,
        )
        delete = self.client.delete(
            "/api/patients/missing", headers=self.doctor_headers
        )
        for response in (detail, update, delete):
            self.assertEqual(404, response.status_code)
            self.assertEqual("Patient not found", response.json()["detail"])

    def test_mutation_role_restrictions_remain_unchanged(self):
        add_patient()
        create = self.client.post(
            "/api/patients", json={"name": "Denied"}, headers=self.patient_headers
        )
        update = self.client.put(
            "/api/patients/patient-1",
            json={"name": "Denied"},
            headers=self.patient_headers,
        )
        delete = self.client.delete(
            "/api/patients/patient-1", headers=self.reception_headers
        )
        self.assertEqual(403, create.status_code)
        self.assertEqual(403, update.status_code)
        self.assertEqual(403, delete.status_code)

    def test_patient_without_history_is_hard_deleted(self):
        add_patient()
        response = self.client.delete(
            "/api/patients/patient-1", headers=self.doctor_headers
        )
        self.assertEqual(200, response.status_code)
        self.assertEqual(
            {
                "status": "success",
                "action": "deleted",
                "message": "Patient deleted successfully from system.",
            },
            response.json(),
        )
        missing = self.client.get(
            "/api/patients/patient-1", headers=self.doctor_headers
        )
        self.assertEqual(404, missing.status_code)

    def test_each_medical_history_type_forces_archive(self):
        history_models = {
            "appointment": lambda: models.Appointment(
                id="history-1", patient_id="patient-1", date=date(2026, 8, 20)
            ),
            "record": lambda: models.Record(
                id="history-1", patient_id="patient-1", tooth="11", diagnosis="Caries"
            ),
            "consultation": lambda: models.Consultation(
                id="history-1", patient_id="patient-1", data="{}", version=1
            ),
            "report": lambda: models.ClinicalReport(
                id="history-1", patient_id="patient-1", status="approved"
            ),
        }

        for history_name, history_factory in history_models.items():
            with self.subTest(history=history_name):
                reset_database()
                add_user(
                    user_id="doctor-1", email="doctor@example.test", role="doctor"
                )
                add_patient()
                db = TestingSessionLocal()
                try:
                    db.add(history_factory())
                    db.commit()
                finally:
                    db.close()

                response = self.client.delete(
                    "/api/patients/patient-1", headers=self.doctor_headers
                )
                self.assertEqual(200, response.status_code, response.text)
                self.assertEqual(
                    {
                        "status": "success",
                        "action": "archived",
                        "message": "Patient archived safely to preserve clinical history.",
                    },
                    response.json(),
                )

                listed = self.client.get(
                    "/api/patients", headers=self.doctor_headers
                )
                self.assertEqual([], listed.json())
                detailed = self.client.get(
                    "/api/patients/patient-1", headers=self.doctor_headers
                )
                self.assertEqual(200, detailed.status_code)
                self.assertEqual("Archived", detailed.json()["status"])


if __name__ == "__main__":
    unittest.main()
