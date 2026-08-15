from __future__ import annotations

from datetime import date
import json
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.repositories.consultation_repository import ConsultationRepository

from tests.support import (
    TestingSessionLocal,
    active_main,
    add_patient,
    add_user,
    bearer_token,
    models,
    reset_database,
)


class PatientDentalStateLifecycleTests(unittest.TestCase):
    PATIENT_A = "20000000-0000-0000-0000-000000000001"
    PATIENT_B = "20000000-0000-0000-0000-000000000002"

    def setUp(self):
        reset_database()
        self.client = TestClient(active_main.app)
        add_user(
            user_id="10000000-0000-0000-0000-000000000001",
            email="doctor@example.test",
            role="doctor",
        )
        add_patient(patient_id=self.PATIENT_A)
        add_patient(patient_id=self.PATIENT_B)
        self.headers = bearer_token("doctor@example.test")
        task_patcher = patch.object(
            active_main, "generate_clinical_report_task", return_value=None
        )
        task_patcher.start()
        self.addCleanup(task_patcher.stop)

    @staticmethod
    def _add_appointment(appointment_id: str, patient_id: str, time: str = "09:00"):
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

    @staticmethod
    def _finish(appointment_id: str):
        db = TestingSessionLocal()
        try:
            appointment = db.query(models.Appointment).filter(
                models.Appointment.id == appointment_id
            ).one()
            appointment.status = "completed"
            db.commit()
        finally:
            db.close()

    def _get(self, patient_id: str):
        response = self.client.get(
            f"/api/consultations/{patient_id}", headers=self.headers
        )
        self.assertEqual(200, response.status_code, response.text)
        return response.json()

    def _save(self, patient_id: str, tooth_data: dict, version: int, state_version: int):
        return self.client.post(
            f"/api/consultations/{patient_id}",
            json={
                "toothData": tooth_data,
                "version": version,
                "dentalStateVersion": state_version,
            },
            headers=self.headers,
        )

    def test_visit_a_to_b_to_c_continuity_and_historical_immutability(self):
        appointment_a = "30000000-0000-0000-0000-000000000001"
        appointment_b = "30000000-0000-0000-0000-000000000002"
        appointment_c = "30000000-0000-0000-0000-000000000003"
        visit_a_data = {
            "14": {"status": "caries"},
            "16": {"status": "missing"},
            "22": {"status": "treated"},
        }

        self._add_appointment(appointment_a, self.PATIENT_A)
        opened_a = self._get(self.PATIENT_A)
        self.assertEqual({}, opened_a["toothData"])
        self.assertEqual(0, opened_a["dentalStateVersion"])
        saved_a = self._save(self.PATIENT_A, visit_a_data, 0, 0)
        self.assertEqual(200, saved_a.status_code, saved_a.text)
        self.assertEqual(1, saved_a.json()["dentalStateVersion"])
        visit_a_id = saved_a.json()["consultationId"]
        self._finish(appointment_a)

        self._add_appointment(appointment_b, self.PATIENT_A)
        opened_b = self._get(self.PATIENT_A)
        self.assertIsNone(opened_b["consultationId"])
        self.assertEqual(visit_a_data, opened_b["toothData"])
        self.assertEqual(1, opened_b["dentalStateVersion"])

        visit_b_data = {**visit_a_data, "14": {"status": "treated"}}
        saved_b = self._save(self.PATIENT_A, visit_b_data, 0, 1)
        self.assertEqual(200, saved_b.status_code, saved_b.text)
        self.assertEqual(2, saved_b.json()["dentalStateVersion"])
        visit_b_id = saved_b.json()["consultationId"]

        history = self.client.get(
            f"/api/consultations/{self.PATIENT_A}/history", headers=self.headers
        ).json()
        by_id = {row["consultationId"]: row for row in history}
        self.assertEqual("caries", by_id[visit_a_id]["toothData"]["14"]["status"])
        self.assertEqual("treated", by_id[visit_b_id]["toothData"]["14"]["status"])
        self.assertNotIn("dentalStateVersion", by_id[visit_a_id])

        db = TestingSessionLocal()
        try:
            current = db.query(models.PatientDentalState).filter(
                models.PatientDentalState.patient_id == self.PATIENT_A
            ).one()
            self.assertEqual("treated", json.loads(current.data)["14"]["status"])
            self.assertEqual(2, current.version)
        finally:
            db.close()

        self._finish(appointment_b)
        self._add_appointment(appointment_c, self.PATIENT_A)
        opened_c = self._get(self.PATIENT_A)
        self.assertEqual("treated", opened_c["toothData"]["14"]["status"])
        self.assertEqual("missing", opened_c["toothData"]["16"]["status"])
        self.assertEqual("treated", opened_c["toothData"]["22"]["status"])
        self.assertEqual(2, opened_c["dentalStateVersion"])

    def test_patients_are_isolated_and_patient_without_state_starts_clean(self):
        self._add_appointment("30000000-0000-0000-0000-000000000011", self.PATIENT_A)
        self._add_appointment("30000000-0000-0000-0000-000000000012", self.PATIENT_B)
        saved = self._save(
            self.PATIENT_A, {"14": {"status": "caries"}}, 0, 0
        )
        self.assertEqual(200, saved.status_code, saved.text)

        opened_b = self._get(self.PATIENT_B)
        self.assertEqual({}, opened_b["toothData"])
        self.assertEqual(0, opened_b["dentalStateVersion"])

    def test_missing_state_row_uses_clean_bootstrap_even_if_history_exists(self):
        db = TestingSessionLocal()
        try:
            db.add(
                models.Consultation(
                    id="40000000-0000-0000-0000-000000000001",
                    patient_id=self.PATIENT_A,
                    data=json.dumps({"14": {"status": "legacy"}}),
                    version=1,
                )
            )
            db.commit()
        finally:
            db.close()
        self._add_appointment(
            "30000000-0000-0000-0000-000000000013", self.PATIENT_A
        )

        opened = self._get(self.PATIENT_A)
        self.assertIsNone(opened["consultationId"])
        self.assertEqual({}, opened["toothData"])
        self.assertEqual(0, opened["dentalStateVersion"])

    def test_stale_dental_state_version_cannot_change_either_snapshot(self):
        appointment_id = "30000000-0000-0000-0000-000000000021"
        self._add_appointment(appointment_id, self.PATIENT_A)
        first_data = {"14": {"status": "caries"}}
        first = self._save(self.PATIENT_A, first_data, 0, 0)
        self.assertEqual(200, first.status_code, first.text)

        stale = self._save(
            self.PATIENT_A,
            {"14": {"status": "missing"}},
            first.json()["version"],
            0,
        )
        self.assertEqual(409, stale.status_code, stale.text)
        self.assertEqual(
            "Dental state version conflict. Please refresh.", stale.json()["detail"]
        )

        refreshed = self._get(self.PATIENT_A)
        self.assertEqual(first_data, refreshed["toothData"])
        self.assertEqual(1, refreshed["version"])
        self.assertEqual(1, refreshed["dentalStateVersion"])

    def test_existing_session_refresh_uses_its_snapshot_not_newer_current_state(self):
        appointment_id = "30000000-0000-0000-0000-000000000031"
        self._add_appointment(appointment_id, self.PATIENT_A)
        snapshot = {"14": {"status": "caries"}}
        saved = self._save(self.PATIENT_A, snapshot, 0, 0)
        self.assertEqual(200, saved.status_code, saved.text)

        db = TestingSessionLocal()
        try:
            current = db.query(models.PatientDentalState).filter(
                models.PatientDentalState.patient_id == self.PATIENT_A
            ).one()
            current.data = json.dumps({"14": {"status": "treated"}})
            current.version += 1
            db.commit()
        finally:
            db.close()

        refreshed = self._get(self.PATIENT_A)
        self.assertEqual(snapshot, refreshed["toothData"])
        self.assertEqual(2, refreshed["dentalStateVersion"])

    def test_failed_atomic_commit_persists_neither_consultation_nor_current_state(self):
        appointment_id = "30000000-0000-0000-0000-000000000041"
        self._add_appointment(appointment_id, self.PATIENT_A)
        with patch.object(
            ConsultationRepository,
            "commit_consultation_and_dental_state",
            side_effect=RuntimeError("synthetic transaction failure"),
        ):
            response = self._save(
                self.PATIENT_A, {"14": {"status": "caries"}}, 0, 0
            )
        self.assertEqual(500, response.status_code, response.text)

        db = TestingSessionLocal()
        try:
            self.assertEqual(0, db.query(models.Consultation).count())
            self.assertEqual(0, db.query(models.PatientDentalState).count())
        finally:
            db.close()

    def test_note_only_save_keeps_dental_state_version_stable(self):
        appointment_id = "30000000-0000-0000-0000-000000000051"
        self._add_appointment(appointment_id, self.PATIENT_A)
        tooth_data = {"14": {"status": "caries"}}
        first = self._save(self.PATIENT_A, tooth_data, 0, 0)
        self.assertEqual(200, first.status_code, first.text)

        note = self.client.post(
            f"/api/consultations/{self.PATIENT_A}",
            json={
                "toothData": tooth_data,
                "version": first.json()["version"],
                "dentalStateVersion": first.json()["dentalStateVersion"],
                "sessionNote": "Note-only update",
            },
            headers=self.headers,
        )
        self.assertEqual(200, note.status_code, note.text)
        self.assertEqual(2, note.json()["version"])
        self.assertEqual(1, note.json()["dentalStateVersion"])


if __name__ == "__main__":
    unittest.main()
