from __future__ import annotations

import io
import unittest
from contextlib import redirect_stdout

from fastapi.testclient import TestClient

from tests.support import active_main, add_user, reset_database


class CurrentSecurityCharacterizationTests(unittest.TestCase):
    def setUp(self):
        reset_database()
        self.client = TestClient(active_main.app)

    def test_password123_does_not_bypass_stored_password_hash(self):
        add_user(
            user_id="doctor-1",
            email="doctor@example.test",
            role="doctor",
            password="A-Different-Password!",
        )
        response = self.client.post(
            "/api/auth/login",
            json={"email": "doctor@example.test", "password": "password123"},
        )
        self.assertEqual(400, response.status_code)
        self.assertEqual("Invalid credentials", response.json()["detail"])

    def test_password123_still_works_when_it_is_the_stored_password(self):
        add_user(
            user_id="doctor-1",
            email="doctor@example.test",
            role="doctor",
            password="password123",
        )
        response = self.client.post(
            "/api/auth/login",
            json={"email": "doctor@example.test", "password": "password123"},
        )
        self.assertEqual(200, response.status_code)
        self.assertIn("access_token", response.json())

    def test_submitted_password_is_not_printed_by_login(self):
        submitted_password = "characterization-secret-value"
        output = io.StringIO()
        with redirect_stdout(output):
            response = self.client.post(
                "/api/auth/login",
                json={"email": "missing@example.test", "password": submitted_password},
            )
        self.assertEqual(400, response.status_code)
        self.assertNotIn(submitted_password, output.getvalue())

    def test_medical_and_operational_endpoints_require_authentication(self):
        requests = [
            ("GET", "/dashboard", None),
            ("GET", "/api/dashboard", None),
            ("GET", "/appointments/today", None),
            ("GET", "/logs", None),
            ("GET", "/api/notifications", None),
            ("PATCH", "/api/notifications/1/read", None),
            ("GET", "/api/patients", None),
            ("GET", "/api/patients/patient-1", None),
            ("GET", "/api/appointments", None),
            ("GET", "/api/appointment-conditions", None),
            ("GET", "/api/records", None),
            ("GET", "/api/reports/patient/patient-1", None),
            ("GET", "/api/reports/report-1/download", None),
            ("GET", "/api/ai/insights", None),
            (
                "POST",
                "/api/ai/diagnosis",
                {"symptoms": "pain", "history": "none", "tooth_data": {}},
            ),
            ("POST", "/api/ai/chat", {"messages": [{"role": "user", "text": "hello"}]}),
            ("GET", "/api/clinical/symptoms", None),
            ("POST", "/api/clinical/symptoms", {"name": "Pain"}),
        ]
        for method, path, payload in requests:
            with self.subTest(method=method, path=path):
                response = self.client.request(method, path, json=payload)
                self.assertEqual(401, response.status_code, response.text)


if __name__ == "__main__":
    unittest.main()
