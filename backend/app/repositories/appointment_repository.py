from typing import Optional, List
from sqlalchemy import String, cast, func
from sqlalchemy.orm import Session, joinedload
import models


COMPLETED_APPOINTMENT_STATUSES = ("completed", "finished")

class AppointmentRepository:
    def get_all(self, db: Session) -> List[models.Appointment]:
        return db.query(models.Appointment).options(joinedload(models.Appointment.patient)).all()

    def get_by_id(self, db: Session, appointment_id: str) -> Optional[models.Appointment]:
        aid = str(appointment_id)
        return db.query(models.Appointment).filter((models.Appointment.id == aid) | (models.Appointment.id == appointment_id)).first()

    def get_patient_by_id(self, db: Session, patient_id: str) -> Optional[models.Patient]:
        pid = str(patient_id)
        return db.query(models.Patient).filter(
            (models.Patient.id == pid) | (models.Patient.id == patient_id)
        ).first()

    def get_today(self, db: Session, today) -> List[models.Appointment]:
        return db.query(models.Appointment).options(
            joinedload(models.Appointment.patient)
        ).filter(
            models.Appointment.date == today,
            func.lower(cast(models.Appointment.status, String)).notin_(
                COMPLETED_APPOINTMENT_STATUSES
            ),
        ).order_by(
            models.Appointment.appointment_time.asc().nullslast(),
            models.Appointment.time.asc().nullslast(),
            models.Appointment.id.asc(),
        ).all()

    def get_active_by_patient_id(
        self, db: Session, patient_id: str, today
    ) -> Optional[models.Appointment]:
        pid = str(patient_id)
        return db.query(models.Appointment).filter(
            ((models.Appointment.patient_id == pid) | (models.Appointment.patient_id == patient_id)),
            models.Appointment.date == today,
            func.lower(cast(models.Appointment.status, String)).notin_(
                COMPLETED_APPOINTMENT_STATUSES
            ),
        ).order_by(
            models.Appointment.appointment_time.asc().nullslast(),
            models.Appointment.time.asc().nullslast(),
            models.Appointment.id.asc(),
        ).first()

    def create(self, db: Session, appointment: models.Appointment) -> models.Appointment:
        db.add(appointment)
        db.commit()
        db.refresh(appointment)
        return appointment

    def update(self, db: Session, appointment: models.Appointment) -> models.Appointment:
        db.commit()
        db.refresh(appointment)
        return appointment

    def delete(self, db: Session, appointment: models.Appointment) -> None:
        db.delete(appointment)
        db.commit()

    def add(self, db: Session, instance) -> None:
        db.add(instance)

    def commit(self, db: Session) -> None:
        db.commit()

    def count(self, db: Session) -> int:
        return db.query(models.Appointment).count()

    def count_by_status(self, db: Session, status: str) -> int:
        return db.query(models.Appointment).filter(models.Appointment.status == status).count()
