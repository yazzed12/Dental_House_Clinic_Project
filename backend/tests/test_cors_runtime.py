from __future__ import annotations

from datetime import date
import unittest
from unittest.mock import patch
from uuid import UUID

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


FRONTEND_ORIGIN = "http://localhost:5173"
PATIENT_ID = "30000000-0000-0000-0000-000000000001"
DOCTOR_ID = "20000000-0000-0000-0000-000000000001"
APPOINTMENT_ID = "40000000-0000-0000-0000-000000000001"


class CorsRuntimeTests(unittest.TestCase):
    def setUp(self):
        reset_database()
        self.client = TestClient(active_main.app, raise_server_exceptions=False)
        add_user(
            user_id=DOCTOR_ID,
            email="cors-doctor@example.test",
            role="doctor",
        )
        add_patient(patient_id=PATIENT_ID)
        self.headers = {
            **bearer_token("cors-doctor@example.test"),
            "Origin": FRONTEND_ORIGIN,
        }
        db = TestingSessionLocal()
        try:
            db.add(
                models.ClinicSettings(
                    id="50000000-0000-0000-0000-000000000001",
                    name="CORS Test Clinic",
                )
            )
            db.add(
                models.Appointment(
                    id=APPOINTMENT_ID,
                    patient_id=PATIENT_ID,
                    doctor_id=DOCTOR_ID,
                    date=date.today(),
                    time="09:00",
                    status="pending",
                    type="consultation",
                )
            )
            db.commit()
        finally:
            db.close()

    def assert_cors(self, response):
        self.assertEqual(
            FRONTEND_ORIGIN,
            response.headers.get("access-control-allow-origin"),
            response.text,
        )

    def test_preflight_allows_bearer_headers_and_required_methods(self):
        for path, method in (
            ("/api/settings/clinic", "GET"),
            ("/api/reports", "POST"),
            (f"/api/consultations/{PATIENT_ID}", "POST"),
            ("/api/auth/me", "GET"),
        ):
            with self.subTest(path=path, method=method):
                response = self.client.options(
                    path,
                    headers={
                        "Origin": FRONTEND_ORIGIN,
                        "Access-Control-Request-Method": method,
                        "Access-Control-Request-Headers": "authorization,content-type",
                    },
                )
                self.assertEqual(200, response.status_code, response.text)
                self.assert_cors(response)
                allowed_headers = response.headers.get(
                    "access-control-allow-headers", ""
                ).lower()
                self.assertIn("authorization", allowed_headers)
                self.assertIn("content-type", allowed_headers)

    def test_success_and_handled_error_responses_keep_cors(self):
        for response in (
            self.client.get("/api/settings/clinic", headers=self.headers),
            self.client.get("/api/auth/me", headers=self.headers),
        ):
            self.assertEqual(200, response.status_code, response.text)
            self.assert_cors(response)

        saved = self.client.post(
            f"/api/consultations/{PATIENT_ID}",
            json={
                "toothData": {"11": {"status": "healthy"}},
                "version": 0,
                "sessionNote": "CORS-safe note",
            },
            headers=self.headers,
        )
        self.assertEqual(200, saved.status_code, saved.text)
        self.assert_cors(saved)

        fetched = self.client.get(
            f"/api/consultations/{PATIENT_ID}", headers=self.headers
        )
        self.assertEqual(200, fetched.status_code, fetched.text)
        self.assert_cors(fetched)

        conflict = self.client.post(
            f"/api/consultations/{PATIENT_ID}",
            json={"toothData": {}, "version": 0, "sessionNote": "stale"},
            headers=self.headers,
        )
        self.assertEqual(409, conflict.status_code, conflict.text)
        self.assert_cors(conflict)

    def test_report_success_and_unhandled_pdf_error_keep_cors(self):
        payload = {
            "patient_id": PATIENT_ID,
            "appointment_id": APPOINTMENT_ID,
            "tooth_id": "11",
            "tooth_status": "treated",
            "symptoms": ["Sensitivity"],
            "final_medical_report": "Final report",
            "status": "approved",
        }
        with patch.object(
            active_main, "generate_pdf_report_file", return_value=None
        ):
            success = self.client.post(
                "/api/reports", json=payload, headers=self.headers
            )
        self.assertEqual(200, success.status_code, success.text)
        self.assert_cors(success)
        UUID(success.json()["id"])
        db = TestingSessionLocal()
        try:
            report = db.get(models.ClinicalReport, success.json()["id"])
            self.assertEqual(PATIENT_ID, report.patient_id)
            self.assertEqual(DOCTOR_ID, report.doctor_id)
            self.assertEqual(APPOINTMENT_ID, report.appointment_id)
        finally:
            db.close()

        with patch.object(
            active_main,
            "generate_pdf_report_file",
            side_effect=RuntimeError("synthetic PDF failure"),
        ):
            failure = self.client.post(
                "/api/reports", json=payload, headers=self.headers
            )
        self.assertEqual(500, failure.status_code, failure.text)
        self.assertEqual("Internal server error", failure.json()["detail"])
        self.assert_cors(failure)


if __name__ == "__main__":
    unittest.main()
