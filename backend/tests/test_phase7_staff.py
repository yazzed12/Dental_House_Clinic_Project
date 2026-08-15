from __future__ import annotations

import unittest

from fastapi.testclient import TestClient

from tests.support import (
    TestingSessionLocal,
    active_main,
    add_patient,
    add_user,
    bearer_token,
    models,
    pending_store,
    reset_database,
)


DOCTOR_FIELDS = {
    "id",
    "name",
    "username",
    "role",
    "email",
    "personal_email",
    "phone",
    "specialization",
    "status",
    "patients",
}
RECEPTIONIST_FIELDS = {
    "id",
    "name",
    "username",
    "role",
    "email",
    "personal_email",
    "phone",
    "status",
}


class Phase7StaffTests(unittest.TestCase):
    def setUp(self):
        reset_database()
        self.client = TestClient(active_main.app)
        add_user(user_id="1", email="admin@admin.com", role="admin")
        add_user(
            user_id="2",
            email="dentist@doctor.com",
            role="doctor",
            full_name="Doctor One",
        )
        add_user(
            user_id="3",
            email="desk@receptionist.com",
            role="receptionist",
            full_name="Reception One",
        )
        add_user(user_id="4", email="patient@example.test", role="patient")
        self.admin_headers = bearer_token("admin@admin.com")
        self.doctor_headers = bearer_token("dentist@doctor.com")
        self.reception_headers = bearer_token("desk@receptionist.com")
        self.patient_headers = bearer_token("patient@example.test")

    def test_lists_require_authentication(self):
        self.assertEqual(401, self.client.get("/api/doctors").status_code)
        self.assertEqual(401, self.client.get("/api/receptionists").status_code)

    def test_lists_remain_available_to_every_authenticated_role(self):
        for headers in (
            self.admin_headers,
            self.doctor_headers,
            self.reception_headers,
            self.patient_headers,
        ):
            self.assertEqual(200, self.client.get("/api/doctors", headers=headers).status_code)
            self.assertEqual(
                200, self.client.get("/api/receptionists", headers=headers).status_code
            )

    def test_doctor_list_contract_filtering_mapping_and_patient_count(self):
        pending_store.save_email_mapping("dentist@doctor.com", "doctor@personal.test")
        add_patient(patient_id="patient-1")
        db = TestingSessionLocal()
        try:
            db.add_all(
                [
                    models.ClinicalReport(
                        id="report-1", patient_id="patient-1", doctor_id="2"
                    ),
                    models.ClinicalReport(
                        id="report-2", patient_id="patient-1", doctor_id="2"
                    ),
                    models.User(
                        id="5",
                        username="inactive-doctor",
                        email="inactive@doctor.com",
                        role="doctor",
                        is_active=0,
                        hashed_password=active_main.pwd_context.hash("StoredPassword!"),
                    ),
                ]
            )
            db.commit()
        finally:
            db.close()

        response = self.client.get("/api/doctors", headers=self.patient_headers)
        self.assertEqual(200, response.status_code, response.text)
        self.assertEqual(1, len(response.json()))
        doctor = response.json()[0]
        self.assertEqual(DOCTOR_FIELDS, set(doctor))
        self.assertEqual("Doctor One", doctor["name"])
        self.assertEqual("doctor@personal.test", doctor["personal_email"])
        self.assertEqual("online", doctor["status"])
        self.assertEqual(1, doctor["patients"])

    def test_receptionist_list_contract_and_active_filter(self):
        pending_store.save_email_mapping(
            "desk@receptionist.com", "reception@personal.test"
        )
        db = TestingSessionLocal()
        try:
            db.add(
                models.User(
                    id="6",
                    username="inactive-reception",
                    email="inactive@receptionist.com",
                    role="receptionist",
                    is_active=0,
                    hashed_password=active_main.pwd_context.hash("StoredPassword!"),
                )
            )
            db.commit()
        finally:
            db.close()

        response = self.client.get("/api/receptionists", headers=self.doctor_headers)
        self.assertEqual(200, response.status_code, response.text)
        self.assertEqual(1, len(response.json()))
        receptionist = response.json()[0]
        self.assertEqual(RECEPTIONIST_FIELDS, set(receptionist))
        self.assertEqual("Reception One", receptionist["name"])
        self.assertEqual("reception@personal.test", receptionist["personal_email"])
        self.assertEqual("online", receptionist["status"])

    def test_staff_mutations_are_admin_only(self):
        create_payload = {
            "username": "newdoctor",
            "password": "StrongPassword!",
            "full_name": "New Doctor",
            "email": "newdoctor@doctor.com",
            "role": "doctor",
        }
        for headers in (
            self.doctor_headers,
            self.reception_headers,
            self.patient_headers,
        ):
            responses = (
                self.client.post("/api/staff", json=create_payload, headers=headers),
                self.client.put(
                    "/api/staff/2", json={"full_name": "Denied"}, headers=headers
                ),
                self.client.delete("/api/staff/2", headers=headers),
            )
            for response in responses:
                self.assertEqual(403, response.status_code)
                self.assertEqual("Insufficient permissions", response.json()["detail"])

        self.assertEqual(401, self.client.post("/api/staff", json=create_payload).status_code)
        self.assertEqual(401, self.client.put("/api/staff/2", json={}).status_code)
        self.assertEqual(401, self.client.delete("/api/staff/2").status_code)

    def test_create_normalizes_values_hashes_password_and_preserves_contract(self):
        response = self.client.post(
            "/api/staff",
            json={
                "username": "  NewDentist  ",
                "password": "NewStoredPassword!",
                "full_name": "New Dentist",
                "email": "  NewDentist@Doctor.com  ",
                "personal_email": "  Dentist@Personal.Test  ",
                "role": " Doctor ",
                "phone": "01012345678",
                "specialization": "Orthodontics",
            },
            headers=self.admin_headers,
        )
        self.assertEqual(200, response.status_code, response.text)
        self.assertEqual({"status", "id"}, set(response.json()))
        self.assertEqual("success", response.json()["status"])

        db = TestingSessionLocal()
        try:
            created = db.query(models.User).filter(models.User.id == response.json()["id"]).one()
            self.assertEqual("newdentist", created.username)
            self.assertEqual("newdentist@doctor.com", created.email)
            self.assertEqual("doctor", created.role)
            self.assertEqual("Orthodontics", created.specialization)
            self.assertEqual(1, created.is_active)
            self.assertNotEqual("NewStoredPassword!", created.hashed_password)
            self.assertTrue(
                active_main.pwd_context.verify(
                    "NewStoredPassword!", created.hashed_password
                )
            )
        finally:
            db.close()
        self.assertEqual(
            "dentist@personal.test",
            pending_store.get_personal_email_by_clinic_email(
                "newdentist@doctor.com"
            ),
        )

    def test_create_personal_email_compatibility_role_and_duplicates(self):
        base = {
            "username": "desk-two",
            "password": "StrongPassword!",
            "full_name": "Desk Two",
            "email": "PersonalDesk@Example.Test",
            "role": "receptionist",
        }
        created = self.client.post("/api/staff", json=base, headers=self.admin_headers)
        self.assertEqual(200, created.status_code, created.text)
        self.assertEqual(
            "personaldesk@example.test",
            pending_store.get_personal_email_by_clinic_email(
                "desktwo@receptionist.com"
            ),
        )

        invalid = self.client.post(
            "/api/staff",
            json={**base, "username": "invalid-role", "role": "patient"},
            headers=self.admin_headers,
        )
        self.assertEqual(400, invalid.status_code)
        self.assertEqual(
            "Invalid role. Must be doctor, receptionist, or admin.",
            invalid.json()["detail"],
        )

        duplicate_user = self.client.post(
            "/api/staff", json={**base, "email": "another@example.test"}, headers=self.admin_headers
        )
        self.assertEqual(400, duplicate_user.status_code)
        self.assertEqual(
            "Username or Clinic Email already exists", duplicate_user.json()["detail"]
        )

        duplicate_personal = self.client.post(
            "/api/staff",
            json={**base, "username": "other-desk"},
            headers=self.admin_headers,
        )
        self.assertEqual(400, duplicate_personal.status_code)
        self.assertEqual("Personal email already exists", duplicate_personal.json()["detail"])

    def test_update_preserves_fields_mapping_password_and_specialization_rules(self):
        pending_store.save_email_mapping("dentist@doctor.com", "old@personal.test")
        old_hash = self._get_user("2").hashed_password
        response = self.client.put(
            "/api/staff/2",
            json={
                "username": "  UpdatedDentist ",
                "full_name": "Updated Doctor",
                "email": "new@personal.test",
                "phone": "01100000000",
                "password": "UpdatedPassword!",
                "specialization": "Endodontics",
                "is_active": 1,
            },
            headers=self.admin_headers,
        )
        self.assertEqual(200, response.status_code, response.text)
        self.assertEqual({"status": "success"}, response.json())
        updated = self._get_user("2")
        self.assertEqual("updateddentist", updated.username)
        self.assertEqual("updateddentist@doctor.com", updated.email)
        self.assertEqual("Updated Doctor", updated.full_name)
        self.assertEqual("01100000000", updated.phone)
        self.assertEqual("Endodontics", updated.specialization)
        self.assertNotEqual(old_hash, updated.hashed_password)
        self.assertTrue(
            active_main.pwd_context.verify("UpdatedPassword!", updated.hashed_password)
        )
        self.assertIsNone(
            pending_store.get_personal_email_by_clinic_email("dentist@doctor.com")
        )
        self.assertEqual(
            "new@personal.test",
            pending_store.get_personal_email_by_clinic_email(
                "updateddentist@doctor.com"
            ),
        )

        changed_role = self.client.put(
            "/api/staff/2",
            json={"role": "receptionist", "specialization": "Must disappear"},
            headers=self.admin_headers,
        )
        self.assertEqual(200, changed_role.status_code)
        self.assertIsNone(self._get_user("2").specialization)

    def test_update_duplicate_and_missing_errors_are_unchanged(self):
        duplicate_username = self.client.put(
            "/api/staff/2", json={"username": "desk"}, headers=self.admin_headers
        )
        self.assertEqual(400, duplicate_username.status_code)
        self.assertEqual("Username already exists", duplicate_username.json()["detail"])

        duplicate_email = self.client.put(
            "/api/staff/2",
            json={"email": "desk@receptionist.com"},
            headers=self.admin_headers,
        )
        self.assertEqual(400, duplicate_email.status_code)
        self.assertEqual("Clinic email already exists", duplicate_email.json()["detail"])

        missing = self.client.put(
            "/api/staff/999", json={"full_name": "Missing"}, headers=self.admin_headers
        )
        self.assertEqual(404, missing.status_code)
        self.assertEqual("Staff member not found", missing.json()["detail"])

    def test_delete_soft_deactivates_and_missing_error_is_unchanged(self):
        deleted = self.client.delete("/api/staff/2", headers=self.admin_headers)
        self.assertEqual(200, deleted.status_code)
        self.assertEqual({"status": "success"}, deleted.json())
        self.assertEqual(0, self._get_user("2").is_active)
        listed = self.client.get("/api/doctors", headers=self.admin_headers)
        self.assertEqual([], listed.json())

        missing = self.client.delete("/api/staff/999", headers=self.admin_headers)
        self.assertEqual(404, missing.status_code)
        self.assertEqual("Staff member not found", missing.json()["detail"])

    @staticmethod
    def _get_user(user_id: str):
        db = TestingSessionLocal()
        try:
            user = db.query(models.User).filter(models.User.id == user_id).one()
            db.expunge(user)
            return user
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
