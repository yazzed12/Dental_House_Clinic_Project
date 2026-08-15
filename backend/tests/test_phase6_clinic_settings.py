from __future__ import annotations

import unittest

from fastapi.testclient import TestClient

from tests.support import (
    TestingSessionLocal,
    active_main,
    add_user,
    bearer_token,
    models,
    pending_store,
    reset_database,
)


CLINIC_FIELDS = {
    "id",
    "name",
    "email",
    "phone",
    "address",
    "working_hours",
    "appointment_duration",
    "services",
    "notification_settings",
}

PROFILE_FIELDS = {
    "id",
    "username",
    "role",
    "full_name",
    "email",
    "phone",
    "specialization",
}


class Phase6ClinicSettingsTests(unittest.TestCase):
    def setUp(self):
        reset_database()
        self.client = TestClient(active_main.app)
        add_user(user_id="admin-1", email="admin@example.test", role="admin")
        add_user(user_id="doctor-1", email="doctor@example.test", role="doctor")
        add_user(
            user_id="reception-1",
            email="reception@example.test",
            role="receptionist",
        )
        add_user(user_id="patient-user", email="patient@example.test", role="patient")
        self.admin_headers = bearer_token("admin@example.test")
        self.doctor_headers = bearer_token("doctor@example.test")
        self.reception_headers = bearer_token("reception@example.test")
        self.patient_headers = bearer_token("patient@example.test")

    def _add_settings(self):
        db = TestingSessionLocal()
        try:
            db.add(
                models.ClinicSettings(
                    id="settings-1",
                    name="Smart Dental Clinic",
                    email="clinic@example.test",
                    phone="01000000000",
                    address="Cairo",
                    working_hours="09:00-17:00",
                    appointment_duration=30,
                    services='["General Dentistry"]',
                    notification_settings='{"appointmentReminders":true}',
                )
            )
            db.commit()
        finally:
            db.close()

    def test_authenticated_clinic_get_contract_for_doctor_and_admin(self):
        self._add_settings()
        for headers in (self.doctor_headers, self.admin_headers):
            response = self.client.get("/api/settings/clinic", headers=headers)
            self.assertEqual(200, response.status_code)
            self.assertEqual(CLINIC_FIELDS, set(response.json()))
            self.assertEqual("Smart Dental Clinic", response.json()["name"])
            self.assertEqual(30, response.json()["appointment_duration"])

    def test_clinic_role_restrictions_are_unchanged(self):
        self._add_settings()
        for headers in (self.reception_headers, self.patient_headers):
            get_response = self.client.get("/api/settings/clinic", headers=headers)
            put_response = self.client.put(
                "/api/settings/clinic", json={"name": "Denied"}, headers=headers
            )
            self.assertEqual(403, get_response.status_code)
            self.assertEqual("Insufficient permissions", get_response.json()["detail"])
            self.assertEqual(403, put_response.status_code)
            self.assertEqual("Insufficient permissions", put_response.json()["detail"])

    def test_clinic_update_contract(self):
        self._add_settings()
        response = self.client.put(
            "/api/settings/clinic",
            json={
                "name": "Updated Clinic",
                "appointment_duration": 45,
                "notification_settings": '{"criticalAlerts":true}',
            },
            headers=self.doctor_headers,
        )
        self.assertEqual(200, response.status_code, response.text)
        self.assertEqual(CLINIC_FIELDS, set(response.json()))
        self.assertEqual("Updated Clinic", response.json()["name"])
        self.assertEqual(45, response.json()["appointment_duration"])
        self.assertEqual("01000000000", response.json()["phone"])

    def test_missing_clinic_settings_returns_current_404(self):
        get_response = self.client.get(
            "/api/settings/clinic", headers=self.doctor_headers
        )
        put_response = self.client.put(
            "/api/settings/clinic",
            json={"name": "Missing"},
            headers=self.doctor_headers,
        )
        for response in (get_response, put_response):
            self.assertEqual(404, response.status_code)
            self.assertEqual("Settings not found", response.json()["detail"])

    def test_profile_get_contract_is_available_to_any_authenticated_role(self):
        for headers in (
            self.admin_headers,
            self.doctor_headers,
            self.reception_headers,
            self.patient_headers,
        ):
            response = self.client.get("/api/settings/profile", headers=headers)
            self.assertEqual(200, response.status_code)
            self.assertEqual(PROFILE_FIELDS, set(response.json()))

    def test_profile_update_response_and_password_hashing(self):
        response = self.client.put(
            "/api/settings/profile",
            json={
                "full_name": "Updated Doctor",
                "phone": "01111111111",
                "specialization": "Endodontics",
                "password": "NewStoredPassword!",
            },
            headers=self.doctor_headers,
        )
        self.assertEqual(200, response.status_code, response.text)
        self.assertEqual(PROFILE_FIELDS, set(response.json()))
        self.assertEqual("Updated Doctor", response.json()["full_name"])
        self.assertEqual("01111111111", response.json()["phone"])
        self.assertEqual("Endodontics", response.json()["specialization"])

        db = TestingSessionLocal()
        try:
            doctor = db.query(models.User).filter(models.User.id == "doctor-1").one()
            self.assertTrue(
                active_main.pwd_context.verify(
                    "NewStoredPassword!", doctor.hashed_password
                )
            )
        finally:
            db.close()

    def test_profile_personal_email_mapping_preserves_clinic_email(self):
        response = self.client.put(
            "/api/settings/profile",
            json={"email": "  Personal@Example.Test  "},
            headers=self.doctor_headers,
        )
        self.assertEqual(200, response.status_code, response.text)
        self.assertEqual("doctor@example.test", response.json()["email"])
        self.assertEqual(
            "personal@example.test",
            pending_store.get_personal_email_by_clinic_email("doctor@example.test"),
        )

    def test_profile_duplicate_personal_email_error_is_unchanged(self):
        pending_store.save_email_mapping(
            "other-doctor@example.test", "used@example.test"
        )
        response = self.client.put(
            "/api/settings/profile",
            json={"email": "used@example.test"},
            headers=self.doctor_headers,
        )
        self.assertEqual(400, response.status_code)
        self.assertEqual(
            "Email address is already in use by another account",
            response.json()["detail"],
        )

    def test_all_settings_routes_require_authentication(self):
        self._add_settings()
        responses = [
            self.client.get("/api/settings/clinic"),
            self.client.put("/api/settings/clinic", json={"name": "Denied"}),
            self.client.get("/api/settings/profile"),
            self.client.put("/api/settings/profile", json={"full_name": "Denied"}),
        ]
        self.assertTrue(all(response.status_code == 401 for response in responses))


if __name__ == "__main__":
    unittest.main()
