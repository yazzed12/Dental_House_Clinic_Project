from datetime import date
from typing import Optional
import json
import uuid

from sqlalchemy import String, cast, func, or_
from sqlalchemy.orm import Session, joinedload

import models


class ConsultationRepository:
    @staticmethod
    def get_active_appointment(db: Session, patient_id):
        pid = str(patient_id)
        return db.query(models.Appointment).filter(
            ((models.Appointment.patient_id == pid) | (models.Appointment.patient_id == patient_id)),
            or_(
                models.Appointment.date == date.today(),
                models.Appointment.appointment_date == date.today(),
            ),
            func.lower(cast(models.Appointment.status, String)) != "completed",
        ).order_by(
            models.Appointment.date.asc().nullslast(),
            models.Appointment.appointment_date.asc().nullslast(),
            models.Appointment.appointment_time.asc().nullslast(),
            models.Appointment.time.asc().nullslast(),
            models.Appointment.id.asc(),
        ).first()

    @staticmethod
    def get_for_appointment(db: Session, appointment_id):
        aid = str(appointment_id)
        return db.query(models.Consultation).filter(
            (models.Consultation.appointment_id == aid)
            | (models.Consultation.appointment_id == appointment_id)
        ).order_by(
            models.Consultation.last_updated.desc().nullslast(),
            models.Consultation.created_at.desc().nullslast(),
            models.Consultation.id.desc(),
        ).first()

    @staticmethod
    def get_latest_by_patient_id(db: Session, patient_id):
        pid = str(patient_id)
        return db.query(models.Consultation).filter(
            (models.Consultation.patient_id == pid)
            | (models.Consultation.patient_id == patient_id)
        ).order_by(
            models.Consultation.last_updated.desc().nullslast(),
            models.Consultation.created_at.desc().nullslast(),
            models.Consultation.id.desc(),
        ).first()

    def get_by_patient_id(self, db: Session, patient_id) -> Optional[models.Consultation]:
        appointment = self.get_active_appointment(db, patient_id)
        if appointment:
            return self.get_for_appointment(db, appointment.id)
        return self.get_latest_by_patient_id(db, patient_id)

    @staticmethod
    def get_patient(db: Session, patient_id):
        pid = str(patient_id)
        return db.query(models.Patient).filter(
            (models.Patient.id == pid) | (models.Patient.id == patient_id)
        ).first()

    @staticmethod
    def get_dental_state(db: Session, patient_id):
        pid = str(patient_id)
        return db.query(models.PatientDentalState).filter(
            (models.PatientDentalState.patient_id == pid)
            | (models.PatientDentalState.patient_id == patient_id)
        ).first()

    @staticmethod
    def get_dental_state_for_update(db: Session, patient_id):
        pid = str(patient_id)
        return db.query(models.PatientDentalState).filter(
            (models.PatientDentalState.patient_id == pid)
            | (models.PatientDentalState.patient_id == patient_id)
        ).with_for_update().first()

    @staticmethod
    def create_dental_state(db: Session, patient_id, data_json: str):
        state = models.PatientDentalState(
            patient_id=str(patient_id),
            data=data_json,
            version=1,
        )
        db.add(state)
        return state

    @staticmethod
    def update_dental_state(state, data_json: str):
        if json.loads(state.data) != json.loads(data_json):
            state.data = data_json
            state.version += 1
        return state

    @staticmethod
    def create(
        db: Session,
        patient_id: str,
        data_json: str,
        *,
        doctor_id=None,
        appointment_id=None,
        session_note=None,
    ) -> models.Consultation:
        consultation = models.Consultation(
            id=str(uuid.uuid4()),
            patient_id=str(patient_id),
            doctor_id=str(doctor_id) if doctor_id is not None else None,
            appointment_id=(
                str(appointment_id) if appointment_id is not None else None
            ),
            data=data_json,
            session_note=session_note,
            version=1,
        )
        db.add(consultation)
        return consultation

    @staticmethod
    def update_data(
        consultation: models.Consultation,
        data_json: str,
        *,
        session_note_supplied: bool = False,
        session_note=None,
    ) -> models.Consultation:
        consultation.data = data_json
        if session_note_supplied:
            consultation.session_note = session_note
        consultation.version += 1
        return consultation

    @staticmethod
    def commit(db: Session, consultation: models.Consultation) -> models.Consultation:
        db.commit()
        db.refresh(consultation)
        return consultation

    @staticmethod
    def commit_consultation_and_dental_state(
        db: Session,
        consultation: models.Consultation,
        dental_state: models.PatientDentalState,
    ):
        db.commit()
        db.refresh(consultation)
        db.refresh(dental_state)
        return consultation, dental_state

    @staticmethod
    def rollback(db: Session) -> None:
        db.rollback()

    @staticmethod
    def get_history(db: Session, patient_id):
        pid = str(patient_id)
        return db.query(models.Consultation).filter(
            (models.Consultation.patient_id == pid)
            | (models.Consultation.patient_id == patient_id)
        ).order_by(
            models.Consultation.created_at.desc().nullslast(),
            models.Consultation.last_updated.desc().nullslast(),
            models.Consultation.id.desc(),
        ).all()

    @staticmethod
    def get_latest_meaningful_note(db: Session, patient_id, excluded_id=None):
        pid = str(patient_id)
        query = db.query(models.Consultation).filter(
            (models.Consultation.patient_id == pid)
            | (models.Consultation.patient_id == patient_id),
            models.Consultation.session_note.isnot(None),
            func.length(func.trim(models.Consultation.session_note)) > 0,
        )
        if excluded_id is not None:
            query = query.filter(models.Consultation.id != excluded_id)
        return query.order_by(
            models.Consultation.created_at.desc().nullslast(),
            models.Consultation.last_updated.desc().nullslast(),
            models.Consultation.id.desc(),
        ).first()

    @staticmethod
    def get_doctor_history(db: Session, doctor_id):
        doc_id = str(doctor_id)
        return db.query(models.ClinicalReport).options(
            joinedload(models.ClinicalReport.patient)
        ).filter(
            (models.ClinicalReport.doctor_id == doc_id)
            | (models.ClinicalReport.doctor_id == doctor_id)
        ).order_by(
            models.ClinicalReport.created_at.desc().nullslast(),
            models.ClinicalReport.id.desc(),
        ).all()

    @staticmethod
    def find_session_for_report(db: Session, report):
        query = db.query(models.Consultation).filter(
            models.Consultation.patient_id == str(report.patient_id)
        )
        if report.appointment_id:
            matched = query.filter(
                models.Consultation.appointment_id == str(report.appointment_id)
            ).order_by(
                models.Consultation.last_updated.desc().nullslast(),
                models.Consultation.created_at.desc().nullslast(),
                models.Consultation.id.desc(),
            ).first()
            if matched:
                return matched
        if report.doctor_id:
            query = query.filter(
                models.Consultation.doctor_id == str(report.doctor_id)
            )
        if report.created_at:
            query = query.filter(models.Consultation.created_at <= report.created_at)
        return query.order_by(
            models.Consultation.created_at.desc().nullslast(),
            models.Consultation.last_updated.desc().nullslast(),
            models.Consultation.id.desc(),
        ).first()

    @staticmethod
    def list_procedures(db: Session, consultation_id):
        return db.query(models.ConsultationProcedure).filter(
            models.ConsultationProcedure.consultation_id == str(consultation_id)
        ).order_by(
            models.ConsultationProcedure.created_at.asc(),
            models.ConsultationProcedure.id.asc(),
        ).all()

    def count(self, db: Session) -> int:
        return db.query(models.Consultation).count()
