from __future__ import annotations

from datetime import date, time
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


class ConsultationSessionNoteTests(unittest.TestCase):
    def setUp(self):
        reset_database()
        self.client = TestClient(active_main.app)
        add_user(user_id="doctor-1", email="doctor@example.test", role="doctor")
        add_user(user_id="admin-1", email="admin@example.test", role="admin")
        add_user(
            user_id="reception-1",
            email="reception@example.test",
            role="receptionist",
        )
        add_patient(patient_id="patient-1")
        self.doctor_headers = bearer_token("doctor@example.test")
        self.admin_headers = bearer_token("admin@example.test")
        self.reception_headers = bearer_token("reception@example.test")
        self.dental_state_version = 0
        task_patcher = patch.object(
            active_main, "generate_clinical_report_task", return_value=None
        )
        self.report_task = task_patcher.start()
        self.addCleanup(task_patcher.stop)

    @staticmethod
    def _add_appointment(appointment_id: str, status: str = "pending"):
        db = TestingSessionLocal()
        try:
            appointment = models.Appointment(
                id=appointment_id,
                patient_id="patient-1",
                date=date.today(),
                time="09:00",
                type="consultation",
                status=status,
            )
            db.add(appointment)
            db.commit()
        finally:
            db.close()

    @staticmethod
    def _complete_appointment(appointment_id: str):
        db = TestingSessionLocal()
        try:
            appointment = db.query(models.Appointment).filter(
                models.Appointment.id == appointment_id
            ).one()
            appointment.status = "completed"
            db.commit()
        finally:
            db.close()

    def _save(self, *, note, version, tooth_data=None):
        payload = {
            "toothData": tooth_data or {"11": {"status": "healthy"}},
            "version": version,
            "sessionNote": note,
            "dentalStateVersion": self.dental_state_version,
        }
        response = self.client.post(
            "/api/consultations/patient-1",
            json=payload,
            headers=self.doctor_headers,
        )
        if response.status_code == 200:
            self.dental_state_version = response.json()["dentalStateVersion"]
        return response

    def test_create_retrieve_and_update_note_share_consultation_version(self):
        self._add_appointment("appointment-1")
        exact_note = "Keep original wording.\nSecond clinical line."
        created = self._save(note=exact_note, version=0)
        self.assertEqual(200, created.status_code, created.text)
        self.assertEqual(1, created.json()["version"])
        self.assertEqual(exact_note, created.json()["sessionNote"])

        fetched = self.client.get(
            "/api/consultations/patient-1", headers=self.doctor_headers
        )
        self.assertEqual(200, fetched.status_code)
        self.assertEqual(exact_note, fetched.json()["sessionNote"])
        self.assertEqual({"11": {"status": "healthy"}}, fetched.json()["toothData"])

        updated = self._save(
            note="Updated session note",
            version=1,
            tooth_data={"11": {"status": "treated"}},
        )
        self.assertEqual(200, updated.status_code)
        self.assertEqual(2, updated.json()["version"])
        self.assertEqual("Updated session note", updated.json()["sessionNote"])

        db = TestingSessionLocal()
        try:
            consultation = db.query(models.Consultation).one()
            self.assertEqual("Updated session note", consultation.session_note)
            self.assertEqual("appointment-1", consultation.appointment_id)
            self.assertEqual("doctor-1", consultation.doctor_id)
        finally:
            db.close()

    def test_stale_note_update_returns_409_and_cannot_overwrite_newer_note(self):
        self._add_appointment("appointment-1")
        self.assertEqual(200, self._save(note="Original", version=0).status_code)
        first = self.client.get(
            "/api/consultations/patient-1", headers=self.doctor_headers
        ).json()
        stale_version = first["version"]

        winner = self._save(note="Newer note", version=stale_version)
        self.assertEqual(2, winner.json()["version"])
        stale = self._save(note="Stale overwrite", version=stale_version)
        self.assertEqual(409, stale.status_code)
        self.assertEqual("Version conflict. Please refresh.", stale.json()["detail"])

        fetched = self.client.get(
            "/api/consultations/patient-1", headers=self.doctor_headers
        ).json()
        self.assertEqual("Newer note", fetched["sessionNote"])
        self.assertEqual(2, fetched["version"])

    def test_omitted_note_preserves_existing_and_old_null_note_is_valid(self):
        old = models.Consultation(
            id="old-consultation",
            patient_id="patient-1",
            doctor_id="doctor-1",
            data='{"11":{"status":"healthy"}}',
            session_note=None,
            version=1,
        )
        db = TestingSessionLocal()
        try:
            db.add(old)
            db.commit()
        finally:
            db.close()

        fetched = self.client.get(
            "/api/consultations/patient-1", headers=self.doctor_headers
        )
        self.assertEqual(200, fetched.status_code)
        self.assertIsNone(fetched.json()["sessionNote"])

        response = self.client.post(
            "/api/consultations/patient-1",
            json={
                "toothData": {"11": {"status": "treated"}},
                "version": 1,
                "dentalStateVersion": 0,
            },
            headers=self.doctor_headers,
        )
        self.assertEqual(200, response.status_code)
        self.assertIsNone(response.json()["sessionNote"])

    def test_patient_history_returns_complete_sessions_and_notes(self):
        self._add_appointment("appointment-1")
        first = self._save(note="Session A", version=0).json()
        self._complete_appointment("appointment-1")
        self._add_appointment("appointment-2")
        second = self._save(
            note="Session B", version=0, tooth_data={"21": {"status": "caries"}}
        ).json()

        response = self.client.get(
            "/api/consultations/patient-1/history", headers=self.doctor_headers
        )
        self.assertEqual(200, response.status_code, response.text)
        history = response.json()
        self.assertEqual(2, len(history))
        by_id = {item["consultationId"]: item for item in history}
        self.assertEqual("Session A", by_id[first["consultationId"]]["sessionNote"])
        self.assertEqual("Session B", by_id[second["consultationId"]]["sessionNote"])
        self.assertEqual(
            {"21": {"status": "caries"}},
            by_id[second["consultationId"]]["toothData"],
        )

    def test_existing_doctor_history_includes_matching_session_note(self):
        self._add_appointment("appointment-1")
        created = self._save(note="History-visible note", version=0).json()
        db = TestingSessionLocal()
        try:
            db.add(
                models.ClinicalReport(
                    id="report-1",
                    patient_id="patient-1",
                    doctor_id="doctor-1",
                    appointment_id="appointment-1",
                    tooth_id="11",
                    tooth_status="treated",
                    status="approved",
                )
            )
            db.commit()
        finally:
            db.close()

        response = self.client.get(
            "/api/doctor/consultations/history", headers=self.doctor_headers
        )
        self.assertEqual(200, response.status_code)
        self.assertEqual("History-visible note", response.json()[0]["sessionNote"])
        self.assertEqual(
            created["consultationId"], response.json()[0]["consultationId"]
        )

    def test_new_session_uses_latest_previous_meaningful_note(self):
        self._add_appointment("appointment-1")
        self._save(note="A", version=0)
        self._complete_appointment("appointment-1")
        self._add_appointment("appointment-2")
        self._save(note="B", version=0)
        self._complete_appointment("appointment-2")
        self._add_appointment("appointment-3")

        bootstrap = self.client.get(
            "/api/consultations/patient-1", headers=self.doctor_headers
        )
        self.assertEqual(200, bootstrap.status_code)
        self.assertEqual(0, bootstrap.json()["version"])
        self.assertIsNone(bootstrap.json()["sessionNote"])
        self.assertEqual(
            "B", bootstrap.json()["lastConsultationNote"]["sessionNote"]
        )

    def test_prior_note_remains_historical_across_three_appointment_sessions(self):
        self._add_appointment("appointment-a")
        visit_a = self._save(note="Visit A note", version=0).json()
        self._complete_appointment("appointment-a")

        self._add_appointment("appointment-b")
        opened_b = self.client.get(
            "/api/consultations/patient-1", headers=self.doctor_headers
        ).json()
        self.assertIsNone(opened_b["consultationId"])
        self.assertIsNone(opened_b["sessionNote"])
        self.assertEqual("Visit A note", opened_b["lastConsultationNote"]["sessionNote"])

        visit_b = self._save(note="Visit B note", version=0).json()
        self.assertNotEqual(visit_a["consultationId"], visit_b["consultationId"])
        current_b = self.client.get(
            "/api/consultations/patient-1", headers=self.doctor_headers
        ).json()
        self.assertEqual("Visit B note", current_b["sessionNote"])
        self.assertEqual("Visit A note", current_b["lastConsultationNote"]["sessionNote"])
        self._complete_appointment("appointment-b")

        self._add_appointment("appointment-c")
        opened_c = self.client.get(
            "/api/consultations/patient-1", headers=self.doctor_headers
        ).json()
        self.assertIsNone(opened_c["consultationId"])
        self.assertIsNone(opened_c["sessionNote"])
        self.assertEqual("Visit B note", opened_c["lastConsultationNote"]["sessionNote"])

        history = self.client.get(
            "/api/consultations/patient-1/history", headers=self.doctor_headers
        ).json()
        notes = {row["consultationId"]: row["sessionNote"] for row in history}
        self.assertEqual("Visit A note", notes[visit_a["consultationId"]])
        self.assertEqual("Visit B note", notes[visit_b["consultationId"]])

    def test_new_patient_session_has_empty_previous_note_without_fake_content(self):
        add_patient(patient_id="patient-without-history")
        db = TestingSessionLocal()
        try:
            db.add(
                models.Appointment(
                    id="appointment-without-history",
                    patient_id="patient-without-history",
                    date=date.today(),
                    time="11:00",
                    type="consultation",
                    status="pending",
                )
            )
            db.commit()
        finally:
            db.close()

        opened = self.client.get(
            "/api/consultations/patient-without-history",
            headers=self.doctor_headers,
        )
        self.assertEqual(200, opened.status_code)
        self.assertIsNone(opened.json()["sessionNote"])
        self.assertIsNone(opened.json()["lastConsultationNote"])

    def test_empty_latest_note_falls_back_to_earlier_meaningful_note(self):
        self._add_appointment("appointment-1")
        self._save(note="Important note", version=0)
        self._complete_appointment("appointment-1")
        self._add_appointment("appointment-2")
        self._save(note="   ", version=0)
        self._complete_appointment("appointment-2")
        self._add_appointment("appointment-3")

        bootstrap = self.client.get(
            "/api/consultations/patient-1", headers=self.doctor_headers
        ).json()
        self.assertEqual(
            "Important note", bootstrap["lastConsultationNote"]["sessionNote"]
        )

    def test_history_and_note_data_keep_existing_authorization(self):
        self._add_appointment("appointment-1")
        self._save(note="Protected", version=0)
        for request in (
            lambda: self.client.get("/api/consultations/patient-1/history"),
            lambda: self.client.get(
                "/api/consultations/patient-1/history",
                headers=self.reception_headers,
            ),
        ):
            response = request()
            self.assertIn(response.status_code, {401, 403})
        self.assertEqual(
            200,
            self.client.get(
                "/api/consultations/patient-1/history",
                headers=self.admin_headers,
            ).status_code,
        )

    def test_legacy_session_and_active_appointment_date_use_new_session(self):
        db = TestingSessionLocal()
        try:
            legacy = models.Consultation(
                id="legacy-session",
                patient_id="patient-1",
                doctor_id="doctor-1",
                data='{"11":{"status":"legacy"}}',
                session_note="Legacy note",
                version=4,
            )
            appointment = models.Appointment(
                id="appointment-current",
                patient_id="patient-1",
                appointment_date=date.today(),
                appointment_time=time(9, 30),
                status="pending",
                type="consultation",
            )
            db.add_all([legacy, appointment])
            db.commit()
        finally:
            db.close()

        bootstrap = self.client.get(
            "/api/consultations/patient-1", headers=self.doctor_headers
        )
        self.assertEqual(0, bootstrap.json()["version"])
        self.assertEqual("appointment-current", bootstrap.json()["appointmentId"])

        saved = self._save(note="Current appointment note", version=0)
        self.assertEqual(200, saved.status_code, saved.text)
        self.assertEqual("appointment-current", saved.json()["appointmentId"])

        reloaded = self.client.get(
            "/api/consultations/patient-1", headers=self.doctor_headers
        ).json()
        self.assertEqual("Current appointment note", reloaded["sessionNote"])
        self.assertNotEqual("legacy-session", reloaded["consultationId"])

        db = TestingSessionLocal()
        try:
            unchanged = db.get(models.Consultation, "legacy-session")
            self.assertEqual("Legacy note", unchanged.session_note)
            self.assertEqual(4, unchanged.version)
        finally:
            db.close()

    def test_report_uses_same_active_appointment_and_is_visible_everywhere(self):
        self._add_appointment("appointment-report")
        consultation = self._save(note="Report session note", version=0).json()
        with patch.object(active_main, "generate_pdf_report_file", return_value=None):
            saved = self.client.post(
                "/api/reports",
                json={
                    "patient_id": "patient-1",
                    "appointment_id": "appointment-report",
                    "tooth_id": "11",
                    "tooth_status": "treated",
                    "symptoms": ["Sensitivity"],
                    "final_medical_report": "Final report",
                    "status": "approved",
                },
                headers=self.doctor_headers,
            )
        self.assertEqual(200, saved.status_code, saved.text)

        patient_reports = self.client.get(
            "/api/reports/patient/patient-1", headers=self.doctor_headers
        ).json()
        self.assertEqual(saved.json()["id"], patient_reports[0]["id"])

        history = self.client.get(
            "/api/doctor/consultations/history", headers=self.doctor_headers
        ).json()
        self.assertEqual(saved.json()["id"], history[0]["id"])
        self.assertEqual(consultation["consultationId"], history[0]["consultationId"])
        self.assertEqual("Report session note", history[0]["sessionNote"])

        db = TestingSessionLocal()
        try:
            report = db.get(models.ClinicalReport, saved.json()["id"])
            self.assertEqual("appointment-report", report.appointment_id)
            self.assertEqual("doctor-1", report.doctor_id)
        finally:
            db.close()

    def test_report_bootstraps_missing_active_session_and_rejects_mismatch(self):
        self._add_appointment("appointment-report")
        with patch.object(active_main, "generate_pdf_report_file", return_value=None):
            mismatch = self.client.post(
                "/api/reports",
                json={
                    "patient_id": "patient-1",
                    "appointment_id": "different-appointment",
                    "final_medical_report": "Must not save",
                },
                headers=self.doctor_headers,
            )
            self.assertEqual(409, mismatch.status_code)

            saved = self.client.post(
                "/api/reports",
                json={
                    "patient_id": "patient-1",
                    "final_medical_report": "Current-session report",
                },
                headers=self.doctor_headers,
            )
        self.assertEqual(200, saved.status_code, saved.text)

        db = TestingSessionLocal()
        try:
            consultations = db.query(models.Consultation).all()
            reports = db.query(models.ClinicalReport).all()
            self.assertEqual(1, len(consultations))
            self.assertEqual("appointment-report", consultations[0].appointment_id)
            self.assertEqual(1, len(reports))
            self.assertEqual("appointment-report", reports[0].appointment_id)
        finally:
            db.close()

    def test_uuid_backed_consultation_insert_and_note_reload(self):
        doctor_id = "20000000-0000-0000-0000-000000000001"
        patient_id = "30000000-0000-0000-0000-000000000001"
        appointment_id = "40000000-0000-0000-0000-000000000001"
        add_user(
            user_id=doctor_id,
            email="uuid-doctor@example.test",
            role="doctor",
        )
        add_patient(patient_id=patient_id)
        db = TestingSessionLocal()
        try:
            db.add(
                models.Appointment(
                    id=appointment_id,
                    patient_id=patient_id,
                    doctor_id=doctor_id,
                    appointment_date=date.today(),
                    appointment_time=time(14, 0),
                    status="pending",
                    type="consultation",
                )
            )
            db.commit()
        finally:
            db.close()

        headers = bearer_token("uuid-doctor@example.test")
        saved = self.client.post(
            f"/api/consultations/{patient_id}",
            json={
                "toothData": {"11": {"status": "treated"}},
                "version": 0,
                "sessionNote": "UUID-backed note",
            },
            headers=headers,
        )
        self.assertEqual(200, saved.status_code, saved.text)
        UUID(saved.json()["consultationId"])
        self.assertEqual(appointment_id, saved.json()["appointmentId"])

        reloaded = self.client.get(
            f"/api/consultations/{patient_id}", headers=headers
        )
        self.assertEqual(200, reloaded.status_code, reloaded.text)
        self.assertEqual("UUID-backed note", reloaded.json()["sessionNote"])
        self.assertEqual(doctor_id, reloaded.json()["doctorId"])
        self.assertEqual(appointment_id, reloaded.json()["appointmentId"])


if __name__ == "__main__":
    unittest.main()
