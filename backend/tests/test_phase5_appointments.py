from __future__ import annotations

import unittest
from datetime import date, time
from unittest.mock import patch

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


APPOINTMENT_FIELDS = {
    "id",
    "patient_id",
    "patient",
    "date",
    "time",
    "type",
    "status",
    "condition",
}


class Phase5AppointmentRouteTests(unittest.TestCase):
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
        add_patient()
        self.doctor_headers = bearer_token("doctor@example.test")
        self.reception_headers = bearer_token("reception@example.test")
        self.patient_headers = bearer_token("patient@example.test")

    def _add_appointment(
        self,
        *,
        appointment_id="123",
        appointment_date=None,
        appointment_time="09:30",
        status="pending",
        appointment_type="normal",
        patient_id="patient-1",
    ):
        db = TestingSessionLocal()
        try:
            appointment = models.Appointment(
                id=appointment_id,
                patient_id=patient_id,
                date=appointment_date or date.today(),
                time=appointment_time,
                status=status,
                type=appointment_type,
                condition="Routine Checkup",
            )
            db.add(appointment)
            db.commit()
        finally:
            db.close()

    def test_list_and_today_contracts(self):
        self._add_appointment()

        listed = self.client.get("/api/appointments", headers=self.doctor_headers)
        self.assertEqual(200, listed.status_code)
        self.assertEqual(APPOINTMENT_FIELDS, set(listed.json()[0]))
        self.assertEqual("Characterization Patient", listed.json()[0]["patient"])

        today = self.client.get("/appointments/today", headers=self.doctor_headers)
        self.assertEqual(200, today.status_code)
        self.assertEqual(
            {"id", "patient_id", "patient_name", "time", "type", "status"},
            set(today.json()[0]),
        )
        self.assertEqual("Characterization Patient", today.json()[0]["patient_name"])

    def test_create_preserves_normalization_time_columns_and_background_task(self):
        with patch.object(active_main, "send_appointment_reminder_task") as reminder:
            created = self.client.post(
                "/api/appointments",
                json={
                    "patient_id": "patient-1",
                    "date": "2026-08-25",
                    "time": "2:15 PM",
                    "type": "Emergency Visit",
                    "status": "unexpected",
                    "condition": "Dental Pain",
                },
                headers=self.reception_headers,
            )
        self.assertEqual(200, created.status_code, created.text)
        self.assertEqual(APPOINTMENT_FIELDS, set(created.json()))
        self.assertEqual("urgent", created.json()["type"])
        self.assertEqual("pending", created.json()["status"])
        self.assertEqual("2:15 PM", created.json()["time"])
        reminder.assert_called_once_with(created.json()["id"])

        db = TestingSessionLocal()
        try:
            appointment = db.query(models.Appointment).filter(
                models.Appointment.id == created.json()["id"]
            ).one()
            self.assertEqual(date(2026, 8, 25), appointment.date)
            self.assertEqual(appointment.date, appointment.appointment_date)
            self.assertEqual(time(14, 15), appointment.appointment_time)
        finally:
            db.close()

    def test_invalid_time_keeps_raw_value_and_uses_existing_nine_am_fallback(self):
        with patch.object(active_main, "send_appointment_reminder_task"):
            created = self.client.post(
                "/api/appointments",
                json={
                    "patient_id": "patient-1",
                    "date": "2026-08-25",
                    "time": "not-a-time",
                },
                headers=self.reception_headers,
            )
        self.assertEqual(200, created.status_code)
        self.assertEqual("not-a-time", created.json()["time"])
        db = TestingSessionLocal()
        try:
            appointment = db.query(models.Appointment).filter(
                models.Appointment.id == created.json()["id"]
            ).one()
            self.assertEqual(time(9, 0), appointment.appointment_time)
        finally:
            db.close()

    def test_create_invalid_date_and_missing_patient_contracts(self):
        invalid = self.client.post(
            "/api/appointments",
            json={"patient_id": "patient-1", "date": "25/08/2026", "time": "09:30"},
            headers=self.reception_headers,
        )
        self.assertEqual(400, invalid.status_code)
        self.assertEqual(
            "Invalid date format, use YYYY-MM-DD", invalid.json()["detail"]
        )

        with patch.object(active_main, "send_appointment_reminder_task"):
            missing_patient = self.client.post(
                "/api/appointments",
                json={"patient_id": "missing", "date": "2026-08-25", "time": "09:30"},
                headers=self.reception_headers,
            )
        self.assertEqual(200, missing_patient.status_code)
        self.assertEqual("Unknown", missing_patient.json()["patient"])

    def test_status_update_preserves_arrived_fallback_and_notification_behavior(self):
        self._add_appointment()
        arrived = self.client.put(
            "/api/appointments/123/status",
            json={"status": "arrived"},
            headers=self.reception_headers,
        )
        self.assertEqual(200, arrived.status_code)
        self.assertEqual({"status": "success", "new_status": "pending"}, arrived.json())

        db = TestingSessionLocal()
        try:
            notification = db.query(models.Notification).one()
            self.assertEqual("Patient Arrived", notification.title)
            self.assertIn("Characterization Patient", notification.body)
        finally:
            db.close()

        normalized = self.client.put(
            "/api/appointments/123/status",
            json={"status": "No Show"},
            headers=self.reception_headers,
        )
        self.assertEqual(
            {"status": "success", "new_status": "no_show"}, normalized.json()
        )

    def test_general_update_contract_and_date_validation(self):
        self._add_appointment()
        invalid = self.client.put(
            "/api/appointments/123",
            json={"date": "not-a-date"},
            headers=self.reception_headers,
        )
        self.assertEqual(400, invalid.status_code)
        self.assertEqual("Invalid date format", invalid.json()["detail"])

        updated = self.client.put(
            "/api/appointments/123",
            json={
                "date": "2026-09-01",
                "time": "10:45",
                "type": "follow up",
                "status": "confirmed",
                "condition": "Review",
                "notes": "Bring x-rays",
            },
            headers=self.reception_headers,
        )
        self.assertEqual(200, updated.status_code, updated.text)
        self.assertEqual(APPOINTMENT_FIELDS | {"notes"}, set(updated.json()))
        self.assertEqual("follow_up", updated.json()["type"])
        self.assertEqual("confirmed", updated.json()["status"])
        self.assertEqual("Bring x-rays", updated.json()["notes"])

        db = TestingSessionLocal()
        try:
            appointment = db.query(models.Appointment).filter(models.Appointment.id == "123").one()
            self.assertEqual(appointment.date, appointment.appointment_date)
            self.assertEqual(time(10, 45), appointment.appointment_time)
            self.assertTrue(
                db.query(models.Log).filter(models.Log.message.contains("Appointment 123 updated")).first()
            )
        finally:
            db.close()

    def test_delete_and_not_found_contracts_with_numeric_string_id(self):
        self._add_appointment()
        deleted = self.client.delete(
            "/api/appointments/123", headers=self.reception_headers
        )
        self.assertEqual(200, deleted.status_code)
        self.assertEqual({"status": "success"}, deleted.json())

        requests = [
            self.client.put(
                "/api/appointments/missing/status",
                json={"status": "completed"},
                headers=self.reception_headers,
            ),
            self.client.put(
                "/api/appointments/missing",
                json={"time": "10:00"},
                headers=self.reception_headers,
            ),
            self.client.delete(
                "/api/appointments/missing", headers=self.reception_headers
            ),
            self.client.put(
                "/appointments/missing/finish", headers=self.doctor_headers
            ),
        ]
        for response in requests:
            self.assertEqual(404, response.status_code)
            self.assertEqual("Appointment not found", response.json()["detail"])

    def test_completion_workflows_and_doctor_role(self):
        self._add_appointment(appointment_id="patient-finish")
        denied = self.client.post(
            "/api/appointments/finish-by-patient/patient-1",
            headers=self.reception_headers,
        )
        self.assertEqual(403, denied.status_code)

        finished = self.client.post(
            "/api/appointments/finish-by-patient/patient-1",
            headers=self.doctor_headers,
        )
        self.assertEqual(200, finished.status_code, finished.text)
        self.assertEqual({"status": "success"}, finished.json())

        self._add_appointment(appointment_id="456")
        by_id = self.client.put(
            "/appointments/456/finish", headers=self.doctor_headers
        )
        self.assertEqual(200, by_id.status_code)
        self.assertEqual({"status": "success"}, by_id.json())

        db = TestingSessionLocal()
        try:
            statuses = {
                appointment.id: appointment.status
                for appointment in db.query(models.Appointment).all()
            }
            self.assertEqual("completed", statuses["patient-finish"])
            self.assertEqual("completed", statuses["456"])
        finally:
            db.close()

        missing_patient = self.client.post(
            "/api/appointments/finish-by-patient/missing",
            headers=self.doctor_headers,
        )
        self.assertEqual(404, missing_patient.status_code)
        self.assertEqual(
            "No active appointment found for this patient today",
            missing_patient.json()["detail"],
        )

    def test_staff_role_and_unauthenticated_write_protection(self):
        self._add_appointment()
        staff_denied = [
            self.client.post(
                "/api/appointments",
                json={"patient_id": "patient-1", "date": "2026-08-25", "time": "09:30"},
                headers=self.patient_headers,
            ),
            self.client.put(
                "/api/appointments/123/status",
                json={"status": "completed"},
                headers=self.patient_headers,
            ),
            self.client.put(
                "/api/appointments/123",
                json={"time": "10:00"},
                headers=self.patient_headers,
            ),
            self.client.delete(
                "/api/appointments/123", headers=self.patient_headers
            ),
        ]
        self.assertTrue(all(response.status_code == 403 for response in staff_denied))

        unauthenticated = [
            self.client.get("/api/appointments"),
            self.client.get("/appointments/today"),
            self.client.post(
                "/api/appointments",
                json={"patient_id": "patient-1", "date": "2026-08-25", "time": "09:30"},
            ),
            self.client.put(
                "/api/appointments/123/status", json={"status": "completed"}
            ),
            self.client.put("/api/appointments/123", json={"time": "10:00"}),
            self.client.delete("/api/appointments/123"),
            self.client.post("/api/appointments/finish-by-patient/patient-1"),
            self.client.put("/appointments/123/finish"),
        ]
        self.assertTrue(all(response.status_code == 401 for response in unauthenticated))


if __name__ == "__main__":
    unittest.main()
