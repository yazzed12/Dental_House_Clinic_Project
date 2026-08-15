from __future__ import annotations

from datetime import date
import unittest
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


class ConsultationFinishLifecycleTests(unittest.TestCase):
    def setUp(self):
        reset_database()
        self.client = TestClient(active_main.app)
        add_user(user_id="10000000-0000-0000-0000-000000000001", email="doctor@example.test", role="doctor")
        add_patient(patient_id="20000000-0000-0000-0000-000000000001")
        add_patient(patient_id="20000000-0000-0000-0000-000000000002")
        self.headers = bearer_token("doctor@example.test")
        task_patcher = patch.object(
            active_main, "generate_clinical_report_task", return_value=None
        )
        task_patcher.start()
        self.addCleanup(task_patcher.stop)

    @staticmethod
    def _add_appointment(appointment_id: str, patient_id: str, time: str):
        db = TestingSessionLocal()
        try:
            db.add(
                models.Appointment(
                    id=appointment_id,
                    patient_id=patient_id,
                    date=date.today(),
                    time=time,
                    type="consultation",
                    status="pending",
                )
            )
            db.commit()
        finally:
            db.close()

    def test_both_finish_paths_persist_and_today_is_database_authoritative(self):
        patient_a = "20000000-0000-0000-0000-000000000001"
        patient_b = "20000000-0000-0000-0000-000000000002"
        appointment_a = "30000000-0000-0000-0000-000000000001"
        appointment_b = "30000000-0000-0000-0000-000000000002"
        self._add_appointment(appointment_a, patient_a, "09:00")
        self._add_appointment(appointment_b, patient_b, "10:00")

        saved = self.client.post(
            f"/api/consultations/{patient_a}",
            json={
                "toothData": {"11": {"status": "treated"}},
                "sessionNote": "Preserve this finished-session note.\nSecond line.",
                "version": 0,
            },
            headers=self.headers,
        )
        self.assertEqual(200, saved.status_code, saved.text)

        before = self.client.get("/appointments/today", headers=self.headers)
        self.assertEqual({appointment_a, appointment_b}, {row["id"] for row in before.json()})

        finished = self.client.post(
            f"/api/appointments/finish-by-patient/{patient_a}",
            headers=self.headers,
        )
        self.assertEqual(200, finished.status_code, finished.text)
        self.assertEqual({"status": "success"}, finished.json())

        refreshed = self.client.get("/appointments/today", headers=self.headers)
        self.assertEqual([appointment_b], [row["id"] for row in refreshed.json()])

        history = self.client.get(
            f"/api/consultations/{patient_a}/history", headers=self.headers
        )
        self.assertEqual(200, history.status_code)
        self.assertEqual(1, len(history.json()))
        self.assertEqual(
            "Preserve this finished-session note.\nSecond line.",
            history.json()[0]["sessionNote"],
        )
        self.assertEqual(
            {"11": {"status": "treated"}}, history.json()[0]["toothData"]
        )

        by_id = self.client.put(
            f"/appointments/{appointment_b}/finish", headers=self.headers
        )
        self.assertEqual(200, by_id.status_code, by_id.text)
        self.assertEqual([], self.client.get("/appointments/today", headers=self.headers).json())

        db = TestingSessionLocal()
        try:
            statuses = {
                row.id: row.status for row in db.query(models.Appointment).all()
            }
            self.assertEqual("completed", statuses[appointment_a])
            self.assertEqual("completed", statuses[appointment_b])
            consultation = db.query(models.Consultation).one()
            self.assertEqual(appointment_a, consultation.appointment_id)
            self.assertEqual(
                "Preserve this finished-session note.\nSecond line.",
                consultation.session_note,
            )
        finally:
            db.close()

    def test_today_excludes_all_supported_completed_status_spellings(self):
        patient_a = "20000000-0000-0000-0000-000000000001"
        patient_b = "20000000-0000-0000-0000-000000000002"
        self._add_appointment("30000000-0000-0000-0000-000000000011", patient_a, "09:00")
        self._add_appointment("30000000-0000-0000-0000-000000000012", patient_b, "10:00")
        db = TestingSessionLocal()
        try:
            rows = db.query(models.Appointment).order_by(models.Appointment.id).all()
            rows[0].status = "Completed"
            rows[1].status = "finished"
            db.commit()
        finally:
            db.close()

        self.assertEqual([], self.client.get("/appointments/today", headers=self.headers).json())


if __name__ == "__main__":
    unittest.main()
