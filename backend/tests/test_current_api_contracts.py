from __future__ import annotations

import json
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

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


CONTRACT = json.loads(
    (Path(__file__).resolve().parent / "contracts" / "frontend_contracts.json").read_text()
)


class CurrentApiContractTests(unittest.TestCase):
    def setUp(self):
        reset_database()
        self.client = TestClient(active_main.app)

    def test_login_success_failure_and_me_contract(self):
        add_user(user_id="doctor-1", email="doctor@example.test", role="doctor")

        success = self.client.post(
            "/api/auth/login",
            json={"email": "doctor@example.test", "password": "CorrectPassword!"},
        )
        self.assertEqual(200, success.status_code)
        self.assertEqual({"access_token", "token_type"}, set(success.json()))

        failure = self.client.post(
            "/api/auth/login",
            json={"email": "doctor@example.test", "password": "incorrect"},
        )
        self.assertEqual(400, failure.status_code)
        self.assertEqual("Invalid credentials", failure.json()["detail"])

        me = self.client.get(
            "/api/auth/me",
            headers={"Authorization": f"Bearer {success.json()['access_token']}"},
        )
        self.assertEqual(200, me.status_code)
        self.assertEqual(
            {"id", "username", "role", "full_name", "email", "phone", "specialization"},
            set(me.json()),
        )

    def test_role_authorization_for_patient_writes(self):
        add_user(user_id="patient-user", email="patient@example.test", role="patient")
        add_user(user_id="reception-1", email="reception@example.test", role="receptionist")
        payload = {"name": "New Patient", "blood_type": "A+"}

        denied = self.client.post(
            "/api/patients", json=payload, headers=bearer_token("patient@example.test")
        )
        self.assertEqual(403, denied.status_code)

        allowed = self.client.post(
            "/api/patients", json=payload, headers=bearer_token("reception@example.test")
        )
        self.assertEqual(200, allowed.status_code)

    def test_patient_response_keeps_frontend_camel_case_fields(self):
        add_user(user_id="doctor-1", email="doctor@example.test", role="doctor")
        add_patient()
        response = self.client.get(
            "/api/patients", headers=bearer_token("doctor@example.test")
        )
        self.assertEqual(200, response.status_code)
        patient = response.json()[0]
        self.assertEqual(set(CONTRACT["patient_response_fields"]), set(patient))
        self.assertEqual("2026-08-01", patient["lastVisit"])
        self.assertEqual("O+", patient["bloodType"])

    @patch.object(active_main, "send_appointment_reminder_task", return_value=None)
    def test_appointment_shape_and_normalization(self, _reminder):
        add_user(user_id="reception-1", email="reception@example.test", role="receptionist")
        add_patient()
        response = self.client.post(
            "/api/appointments",
            json={
                "patient_id": "patient-1",
                "date": "2026-08-15",
                "time": "09:30",
                "type": "Emergency Visit",
                "status": "unexpected-status",
            },
            headers=bearer_token("reception@example.test"),
        )
        self.assertEqual(200, response.status_code, response.text)
        body = response.json()
        self.assertEqual(set(CONTRACT["appointment_response_fields"]), set(body))
        self.assertEqual("urgent", body["type"])
        self.assertEqual("pending", body["status"])

        invalid_date = self.client.post(
            "/api/appointments",
            json={"patient_id": "patient-1", "date": "15/08/2026", "time": "09:30"},
            headers=bearer_token("reception@example.test"),
        )
        self.assertEqual(400, invalid_date.status_code)
        self.assertEqual(
            "Invalid date format, use YYYY-MM-DD", invalid_date.json()["detail"]
        )

    def test_normalization_function_snapshot(self):
        type_cases = {
            None: "consultation",
            "normal check": "normal",
            "emergency": "urgent",
            "follow-up": "follow_up",
            "consult": "consultation",
            "unknown": "consultation",
        }
        status_cases = {
            None: "pending",
            "No Show": "no_show",
            "completed": "completed",
            "unknown": "pending",
        }
        for raw, expected in type_cases.items():
            self.assertEqual(expected, active_main.normalize_appointment_type(raw))
        for raw, expected in status_cases.items():
            self.assertEqual(expected, active_main.normalize_appointment_status(raw))

    @patch.object(active_main, "generate_pdf_report_file", return_value=None)
    def test_report_workflow_payload_and_response_shapes(self, _pdf):
        add_user(user_id="doctor-1", email="doctor@example.test", role="doctor")
        add_patient()
        headers = bearer_token("doctor@example.test")

        with patch.object(
            active_main, "generate_clinical_report", new=AsyncMock(return_value="AI draft")
        ):
            draft = self.client.post(
                "/api/ai/generate-report", json={"patient_id": "patient-1"}, headers=headers
            )
        self.assertEqual(200, draft.status_code)
        self.assertEqual({"status", "report"}, set(draft.json()))

        with patch.object(
            active_main, "humanize_report_ai", new=AsyncMock(return_value="Humanized draft")
        ):
            humanized = self.client.post(
                "/api/ai/humanize-report",
                json={"report": draft.json()["report"], "patient_name": "Patient"},
                headers=headers,
            )
        self.assertEqual(200, humanized.status_code)
        self.assertEqual({"status", "humanized_report"}, set(humanized.json()))

        saved = self.client.post(
            "/api/reports",
            json={
                "patient_id": "patient-1",
                "tooth_id": "11",
                "symptoms": ["pain"],
                "ai_draft_report": draft.json()["report"],
                "humanized_report": humanized.json()["humanized_report"],
                "final_medical_report": "Approved report",
            },
            headers=headers,
        )
        self.assertEqual(200, saved.status_code, saved.text)
        self.assertEqual(
            {"id", "patient_id", "status", "tooth_id", "created_at"}, set(saved.json())
        )

    def test_ai_chat_response_key(self):
        add_user(user_id="doctor-1", email="doctor@example.test", role="doctor")

        class FakeOllama:
            async def ainvoke(self, _messages):
                return SimpleNamespace(content="Characterized answer")

        with patch.object(active_main, "_get_ollama", return_value=FakeOllama()):
            response = self.client.post(
                "/api/ai/chat",
                json={"messages": [{"role": "user", "text": "Hello"}]},
                headers=bearer_token("doctor@example.test"),
            )
        self.assertEqual(200, response.status_code)
        self.assertEqual({"response": "Characterized answer"}, response.json())

    def test_clinic_settings_permissions(self):
        add_user(user_id="doctor-1", email="doctor@example.test", role="doctor")
        add_user(user_id="reception-1", email="reception@example.test", role="receptionist")
        db = TestingSessionLocal()
        try:
            db.add(
                models.ClinicSettings(
                    id="settings-1", name="Smart Dental Clinic", appointment_duration=30
                )
            )
            db.commit()
        finally:
            db.close()

        allowed = self.client.get(
            "/api/settings/clinic", headers=bearer_token("doctor@example.test")
        )
        denied = self.client.get(
            "/api/settings/clinic", headers=bearer_token("reception@example.test")
        )
        self.assertEqual(200, allowed.status_code)
        self.assertEqual(403, denied.status_code)

    def test_notification_response_shape(self):
        add_user(user_id="doctor-1", email="doctor@example.test", role="doctor")
        db = TestingSessionLocal()
        try:
            db.add(
                models.Notification(
                    id="notification-1",
                    title="Reminder",
                    body="Appointment soon",
                    type="info",
                    read=0,
                )
            )
            db.commit()
        finally:
            db.close()

        response = self.client.get(
            "/api/notifications", headers=bearer_token("doctor@example.test")
        )
        self.assertEqual(200, response.status_code)
        self.assertEqual(
            {"id", "title", "body", "type", "read", "created_at"},
            set(response.json()[0]),
        )
        self.assertIs(response.json()[0]["read"], False)

    @patch.object(active_main, "generate_clinical_report_task", return_value=None)
    def test_consultation_version_creation_increment_and_conflict(self, _background):
        add_user(user_id="doctor-1", email="doctor@example.test", role="doctor")
        add_patient()
        headers = bearer_token("doctor@example.test")

        created = self.client.post(
            "/api/consultations/patient-1",
            json={"toothData": {"11": "healthy"}, "version": 0},
            headers=headers,
        )
        self.assertEqual(200, created.status_code, created.text)
        self.assertEqual("success", created.json()["status"])
        self.assertEqual(1, created.json()["version"])

        conflict = self.client.post(
            "/api/consultations/patient-1",
            json={"toothData": {"11": "treated"}, "version": 0},
            headers=headers,
        )
        self.assertEqual(409, conflict.status_code)

        updated = self.client.post(
            "/api/consultations/patient-1",
            json={
                "toothData": {"11": "treated"},
                "version": 1,
                "dentalStateVersion": 1,
            },
            headers=headers,
        )
        self.assertEqual(200, updated.status_code)
        self.assertEqual(2, updated.json()["version"])

        fetched = self.client.get(
            "/api/consultations/patient-1", headers=headers
        )
        self.assertEqual(200, fetched.status_code)
        self.assertEqual(
            {
                "consultationId", "patientId", "doctorId", "appointmentId",
                "toothData", "sessionNote", "version", "dentalStateVersion", "createdAt",
                "lastUpdated", "lastConsultationNote",
            },
            set(fetched.json()),
        )


if __name__ == "__main__":
    unittest.main()
