from __future__ import annotations

from datetime import date, datetime
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

from sqlalchemy.dialects import postgresql
from tests.support import TestingSessionLocal, models, reset_database

from app.repositories.consultation_repository import ConsultationRepository


LOW_UUID = "00000000-0000-0000-0000-000000000001"
MIDDLE_UUID = "00000000-0000-0000-0000-000000000002"
HIGH_UUID = "00000000-0000-0000-0000-000000000003"
PATIENT_UUID = "10000000-0000-0000-0000-000000000001"
DOCTOR_UUID = "20000000-0000-0000-0000-000000000001"
APPOINTMENT_UUID = "30000000-0000-0000-0000-000000000001"


class ConsultationDeterministicSelectionTests(unittest.TestCase):
    def setUp(self):
        reset_database()
        self.repository = ConsultationRepository()
        db = TestingSessionLocal()
        try:
            db.add(
                models.User(
                    id=DOCTOR_UUID,
                    username="tie-doctor",
                    email="tie-doctor@example.test",
                    full_name="Tie Doctor",
                    role="doctor",
                    is_active=1,
                    hashed_password="not-used-by-selection-tests",
                )
            )
            db.add(
                models.Patient(
                    id=PATIENT_UUID,
                    name="Tie Patient",
                    status="Active",
                )
            )
            db.commit()
        finally:
            db.close()

    @staticmethod
    def _add_appointment(db, appointment_id: str, time_value: str = "09:00"):
        appointment = models.Appointment(
            id=appointment_id,
            patient_id=PATIENT_UUID,
            doctor_id=DOCTOR_UUID,
            date=date.today(),
            time=time_value,
            type="consultation",
            status="pending",
        )
        db.add(appointment)
        return appointment

    @staticmethod
    def _add_consultation(
        db,
        consultation_id: str,
        *,
        timestamp: datetime,
        appointment_id: str | None = None,
        session_note: str | None = None,
    ):
        consultation = models.Consultation(
            id=consultation_id,
            patient_id=PATIENT_UUID,
            doctor_id=DOCTOR_UUID,
            appointment_id=appointment_id,
            data="{}",
            session_note=session_note,
            version=1,
            created_at=timestamp,
            last_updated=timestamp,
        )
        db.add(consultation)
        return consultation

    def test_active_appointment_uses_earliest_time_then_ascending_uuid(self):
        db = TestingSessionLocal()
        try:
            self._add_appointment(db, HIGH_UUID, "09:00")
            self._add_appointment(db, MIDDLE_UUID, "10:00")
            self._add_appointment(db, LOW_UUID, "09:00")
            db.commit()

            selected = self.repository.get_active_appointment(db, PATIENT_UUID)

            self.assertEqual(LOW_UUID, selected.id)
        finally:
            db.close()

    def test_active_status_filter_casts_postgresql_enum_to_text(self):
        query = Mock()
        query.filter.return_value = query
        query.order_by.return_value = query
        query.first.return_value = None
        db = Mock()
        db.query.return_value = query

        self.repository.get_active_appointment(db, PATIENT_UUID)

        status_filter = query.filter.call_args.args[2]
        compiled = str(
            status_filter.compile(
                dialect=postgresql.dialect(),
                compile_kwargs={"literal_binds": True},
            )
        )
        self.assertEqual(
            "lower(CAST(appointments.status AS VARCHAR)) != 'completed'",
            compiled,
        )

    def test_latest_and_history_use_descending_uuid_for_timestamp_ties(self):
        tied_at = datetime(2026, 8, 9, 9, 30)
        db = TestingSessionLocal()
        try:
            self._add_consultation(db, LOW_UUID, timestamp=tied_at)
            self._add_consultation(db, HIGH_UUID, timestamp=tied_at)
            db.commit()

            latest = self.repository.get_latest_by_patient_id(db, PATIENT_UUID)
            history = self.repository.get_history(db, PATIENT_UUID)

            self.assertEqual(HIGH_UUID, latest.id)
            self.assertEqual([HIGH_UUID, LOW_UUID], [row.id for row in history])
        finally:
            db.close()

    def test_appointment_lookup_is_deterministic_when_duplicates_are_allowed(self):
        tied_at = datetime(2026, 8, 9, 10, 15)
        db = TestingSessionLocal()
        try:
            self._add_appointment(db, APPOINTMENT_UUID)
            self._add_consultation(
                db,
                LOW_UUID,
                timestamp=tied_at,
                appointment_id=APPOINTMENT_UUID,
            )
            self._add_consultation(
                db,
                HIGH_UUID,
                timestamp=tied_at,
                appointment_id=APPOINTMENT_UUID,
            )
            db.commit()

            selected = self.repository.get_for_appointment(db, APPOINTMENT_UUID)

            self.assertEqual(HIGH_UUID, selected.id)
        finally:
            db.close()

    def test_blank_newer_note_is_ignored_and_meaningful_tie_uses_uuid(self):
        older_at = datetime(2026, 8, 9, 8, 0)
        newer_at = datetime(2026, 8, 9, 11, 0)
        db = TestingSessionLocal()
        try:
            self._add_consultation(
                db,
                LOW_UUID,
                timestamp=older_at,
                session_note="Meaningful lower UUID",
            )
            self._add_consultation(
                db,
                MIDDLE_UUID,
                timestamp=older_at,
                session_note="Meaningful higher UUID",
            )
            self._add_consultation(
                db,
                HIGH_UUID,
                timestamp=newer_at,
                session_note="   ",
            )
            db.commit()

            selected = self.repository.get_latest_meaningful_note(
                db, PATIENT_UUID
            )

            self.assertEqual(MIDDLE_UUID, selected.id)
            self.assertEqual("Meaningful higher UUID", selected.session_note)
        finally:
            db.close()

    def test_report_appointment_match_is_deterministic_under_timestamp_ties(self):
        tied_at = datetime(2026, 8, 9, 12, 0)
        db = TestingSessionLocal()
        try:
            self._add_appointment(db, APPOINTMENT_UUID)
            self._add_consultation(
                db,
                LOW_UUID,
                timestamp=tied_at,
                appointment_id=APPOINTMENT_UUID,
                session_note="Lower UUID",
            )
            self._add_consultation(
                db,
                HIGH_UUID,
                timestamp=tied_at,
                appointment_id=APPOINTMENT_UUID,
                session_note="Higher UUID",
            )
            db.commit()
            report = SimpleNamespace(
                patient_id=PATIENT_UUID,
                appointment_id=APPOINTMENT_UUID,
                doctor_id=DOCTOR_UUID,
                created_at=tied_at,
            )

            selected = self.repository.find_session_for_report(db, report)

            self.assertEqual(HIGH_UUID, selected.id)
            self.assertEqual("Higher UUID", selected.session_note)

            report.appointment_id = None
            fallback_selected = self.repository.find_session_for_report(db, report)
            self.assertEqual(HIGH_UUID, fallback_selected.id)
        finally:
            db.close()

    def test_doctor_history_uses_descending_report_uuid_for_timestamp_ties(self):
        tied_at = datetime(2026, 8, 9, 13, 0)
        db = TestingSessionLocal()
        try:
            for report_id in (LOW_UUID, HIGH_UUID):
                db.add(
                    models.ClinicalReport(
                        id=report_id,
                        patient_id=PATIENT_UUID,
                        doctor_id=DOCTOR_UUID,
                        tooth_id="11",
                        tooth_status="healthy",
                        created_at=tied_at,
                    )
                )
            db.commit()

            history = self.repository.get_doctor_history(db, DOCTOR_UUID)

            self.assertEqual([HIGH_UUID, LOW_UUID], [row.id for row in history])
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
