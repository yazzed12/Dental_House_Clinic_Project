from __future__ import annotations

from datetime import datetime
import json
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient
from sqlalchemy import text

from tests.support import (
    TestingSessionLocal,
    active_main,
    add_patient,
    add_user,
    bearer_token,
    models,
    reset_database,
)


CONSULTATION_FIELDS = {
    "consultationId", "patientId", "doctorId", "appointmentId", "toothData",
    "sessionNote", "version", "dentalStateVersion", "createdAt", "lastUpdated",
    "lastConsultationNote",
}
HISTORY_FIELDS = {
    "id",
    "patient_id",
    "patient_name",
    "doctor_id",
    "tooth_id",
    "tooth_status",
    "symptoms",
    "doctor_notes",
    "ai_draft_report",
    "final_medical_report",
    "humanized_report",
    "status",
    "created_at",
    "updated_at",
    "consultationId",
    "sessionNote",
    "procedures",
}


class Phase8ConsultationTests(unittest.TestCase):
    def setUp(self):
        reset_database()
        self.client = TestClient(active_main.app)
        add_user(user_id="1", email="admin@admin.com", role="admin")
        add_user(user_id="2", email="doctor@doctor.com", role="doctor")
        add_user(user_id="3", email="other@doctor.com", role="doctor")
        add_user(
            user_id="4", email="desk@receptionist.com", role="receptionist"
        )
        add_user(user_id="5", email="patient@example.test", role="patient")
        add_patient(patient_id="123")
        self.admin_headers = bearer_token("admin@admin.com")
        self.doctor_headers = bearer_token("doctor@doctor.com")
        self.other_doctor_headers = bearer_token("other@doctor.com")
        self.reception_headers = bearer_token("desk@receptionist.com")
        self.patient_headers = bearer_token("patient@example.test")
        report_task_patcher = patch.object(
            active_main, "generate_clinical_report_task", return_value=None
        )
        self.report_task = report_task_patcher.start()
        self.addCleanup(report_task_patcher.stop)

    def test_all_consultation_routes_require_authentication(self):
        responses = (
            self.client.get("/api/consultations/123"),
            self.client.post(
                "/api/consultations/123",
                json={"toothData": {}, "version": 0},
            ),
            self.client.get("/api/doctor/consultations/history"),
        )
        self.assertTrue(all(response.status_code == 401 for response in responses))

    def test_doctor_and_admin_authorization_is_unchanged(self):
        for headers in (self.reception_headers, self.patient_headers):
            responses = (
                self.client.get("/api/consultations/123", headers=headers),
                self.client.post(
                    "/api/consultations/123",
                    json={"toothData": {}, "version": 0},
                    headers=headers,
                ),
                self.client.get(
                    "/api/doctor/consultations/history", headers=headers
                ),
            )
            for response in responses:
                self.assertEqual(403, response.status_code)
                self.assertEqual("Insufficient permissions", response.json()["detail"])

        admin_created = self.client.post(
            "/api/consultations/123",
            json={"toothData": {"11": {"tooth_status": "healthy"}}, "version": 9},
            headers=self.admin_headers,
        )
        self.assertEqual(200, admin_created.status_code, admin_created.text)
        self.assertEqual("success", admin_created.json()["status"])
        self.assertEqual(1, admin_created.json()["version"])
        self.assertEqual(
            200,
            self.client.get(
                "/api/consultations/123", headers=self.admin_headers
            ).status_code,
        )
        self.assertEqual(
            200,
            self.client.get(
                "/api/doctor/consultations/history", headers=self.admin_headers
            ).status_code,
        )

    def test_missing_consultation_contract_and_numeric_string_id_compatibility(self):
        missing = self.client.get(
            "/api/consultations/999", headers=self.doctor_headers
        )
        self.assertEqual(404, missing.status_code)
        self.assertEqual("Consultation not found", missing.json()["detail"])

        created = self.client.post(
            "/api/consultations/123",
            json={"toothData": {"21": {"tooth_status": "caries"}}, "version": 0},
            headers=self.doctor_headers,
        )
        self.assertEqual(200, created.status_code, created.text)
        fetched = self.client.get(
            "/api/consultations/123", headers=self.doctor_headers
        )
        self.assertEqual(200, fetched.status_code)
        self.assertEqual(CONSULTATION_FIELDS, set(fetched.json()))
        self.assertEqual("123", fetched.json()["patientId"])
        self.assertEqual(
            {"21": {"tooth_status": "caries"}}, fetched.json()["toothData"]
        )
        self.assertEqual(1, fetched.json()["version"])
        self.assertTrue(fetched.json()["lastUpdated"].endswith("Z"))

    def test_missing_patient_keeps_current_foreign_key_failure_contract(self):
        db = TestingSessionLocal()
        try:
            db.execute(text("PRAGMA foreign_keys=ON"))
            db.commit()
        finally:
            db.close()

        try:
            response = self.client.post(
                "/api/consultations/999",
                json={"toothData": {"11": {"tooth_status": "healthy"}}, "version": 0},
                headers=self.doctor_headers,
            )
            self.assertEqual(500, response.status_code)
            self.assertEqual("Internal server error", response.json()["detail"])
            self.assertEqual(0, self.report_task.call_count)
        finally:
            db = TestingSessionLocal()
            try:
                db.execute(text("PRAGMA foreign_keys=OFF"))
                db.commit()
            finally:
                db.close()

    def test_initial_version_increment_and_two_reader_stale_conflict(self):
        created = self.client.post(
            "/api/consultations/123",
            json={"toothData": {"11": {"tooth_status": "healthy"}}, "version": 0},
            headers=self.doctor_headers,
        )
        self.assertEqual("success", created.json()["status"])
        self.assertEqual(1, created.json()["version"])

        first_reader = self.client.get(
            "/api/consultations/123", headers=self.doctor_headers
        ).json()
        second_reader = self.client.get(
            "/api/consultations/123", headers=self.other_doctor_headers
        ).json()
        self.assertEqual(1, first_reader["version"])
        self.assertEqual(1, second_reader["version"])

        winner = self.client.post(
            "/api/consultations/123",
            json={
                "toothData": {"11": {"tooth_status": "treated"}},
                "version": first_reader["version"],
                "dentalStateVersion": first_reader["dentalStateVersion"],
            },
            headers=self.doctor_headers,
        )
        self.assertEqual("success", winner.json()["status"])
        self.assertEqual(2, winner.json()["version"])

        stale = self.client.post(
            "/api/consultations/123",
            json={
                "toothData": {"11": {"tooth_status": "extracted"}},
                "version": second_reader["version"],
                "dentalStateVersion": second_reader["dentalStateVersion"],
            },
            headers=self.other_doctor_headers,
        )
        self.assertEqual(409, stale.status_code)
        self.assertEqual(
            "Version conflict. Please refresh.", stale.json()["detail"]
        )

        final_state = self.client.get(
            "/api/consultations/123", headers=self.doctor_headers
        ).json()
        self.assertEqual(2, final_state["version"])
        self.assertEqual(
            {"11": {"tooth_status": "treated"}}, final_state["toothData"]
        )

    def test_save_preserves_audit_before_after_and_background_report_trigger(self):
        initial_tooth_data = {
            "11": {"tooth_status": "caries", "symptoms": ["Sharp Pain"]}
        }
        updated_tooth_data = {
            "11": {"tooth_status": "treated", "symptoms": []}
        }
        self.client.post(
            "/api/consultations/123",
            json={"toothData": initial_tooth_data, "version": 0},
            headers=self.doctor_headers,
        )
        self.client.post(
            "/api/consultations/123",
            json={
                "toothData": updated_tooth_data,
                "version": 1,
                "dentalStateVersion": 1,
            },
            headers=self.doctor_headers,
        )

        db = TestingSessionLocal()
        try:
            logs = db.query(models.Log).order_by(models.Log.created_at.asc()).all()
            self.assertEqual(2, len(logs))
            self.assertEqual("2", logs[0].doctor_id)
            self.assertEqual("123", logs[0].patient_id)
            self.assertEqual("Consultation updated for patient 123", logs[0].message)
            self.assertIsNone(logs[0].before_state)
            self.assertEqual(initial_tooth_data, json.loads(logs[0].after_state))
            self.assertEqual(initial_tooth_data, json.loads(logs[1].before_state))
            self.assertEqual(updated_tooth_data, json.loads(logs[1].after_state))
        finally:
            db.close()

        self.assertEqual(2, self.report_task.call_count)
        self.report_task.assert_called_with("123")

    def test_history_contract_filtering_order_and_tooth_status(self):
        db = TestingSessionLocal()
        try:
            db.add_all(
                [
                    models.ClinicalReport(
                        id="older",
                        patient_id="123",
                        doctor_id="2",
                        tooth_id="11",
                        tooth_status="caries",
                        symptoms='["Sharp Pain"]',
                        doctor_notes="Initial note",
                        ai_draft_report="Draft",
                        final_medical_report="Final",
                        humanized_report="Humanized",
                        status="finalized",
                        created_at=datetime(2026, 8, 1, 9, 0),
                        updated_at=datetime(2026, 8, 1, 9, 30),
                    ),
                    models.ClinicalReport(
                        id="newer",
                        patient_id="123",
                        doctor_id="2",
                        tooth_id="21",
                        tooth_status="treated",
                        symptoms=None,
                        status="approved",
                        created_at=datetime(2026, 8, 2, 10, 0),
                        updated_at=datetime(2026, 8, 2, 10, 30),
                    ),
                    models.ClinicalReport(
                        id="other-doctor",
                        patient_id="123",
                        doctor_id="3",
                        tooth_status="healthy",
                        created_at=datetime(2026, 8, 3, 10, 0),
                    ),
                ]
            )
            db.commit()
        finally:
            db.close()

        response = self.client.get(
            "/api/doctor/consultations/history", headers=self.doctor_headers
        )
        self.assertEqual(200, response.status_code, response.text)
        history = response.json()
        self.assertEqual(["newer", "older"], [report["id"] for report in history])
        self.assertTrue(all(set(report) == HISTORY_FIELDS for report in history))
        self.assertEqual("Characterization Patient", history[0]["patient_name"])
        self.assertEqual("treated", history[0]["tooth_status"])
        self.assertEqual([], history[0]["symptoms"])
        self.assertEqual(["Sharp Pain"], history[1]["symptoms"])
        self.assertTrue(history[0]["created_at"].endswith("Z"))


if __name__ == "__main__":
    unittest.main()
