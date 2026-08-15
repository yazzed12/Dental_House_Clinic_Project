from datetime import date

from sqlalchemy.orm import Session, joinedload

import models


class CommonRepository:
    def dashboard_counts(self, db: Session) -> tuple[int, int, int]:
        today_str = date.today().isoformat()
        return (
            db.query(models.Patient)
            .filter(models.Patient.status != "Archived")
            .count(),
            db.query(models.Appointment)
            .filter(
                models.Appointment.date == today_str,
                models.Appointment.status != "completed",
            )
            .count(),
            db.query(models.Record).count(),
        )

    def recent_logs(self, db: Session, limit: int):
        return (
            db.query(models.Log)
            .order_by(models.Log.created_at.desc())
            .limit(limit)
            .all()
        )

    def records(self, db: Session):
        return db.query(models.Record).options(joinedload(models.Record.patient)).all()

    def reports_for_record_fallback(self, db: Session):
        return (
            db.query(models.ClinicalReport)
            .options(
                joinedload(models.ClinicalReport.patient),
                joinedload(models.ClinicalReport.doctor),
            )
            .order_by(models.ClinicalReport.created_at.desc())
            .all()
        )

    def active_appointment_conditions(self, db: Session):
        return (
            db.query(models.AppointmentCondition)
            .filter(models.AppointmentCondition.is_active != 0)
            .all()
        )

    def appointment_condition_by_name(self, db: Session, name: str):
        return (
            db.query(models.AppointmentCondition)
            .filter(models.AppointmentCondition.name == name)
            .first()
        )

    @staticmethod
    def create_appointment_condition(db: Session, name: str, user_id):
        condition = models.AppointmentCondition(
            name=name, created_by=str(user_id), is_active=True
        )
        db.add(condition)
        db.commit()
        db.refresh(condition)
        return condition

    @staticmethod
    def insight_context(db: Session):
        total_patients = db.query(models.Patient).count()
        today_appointments = (
            db.query(models.Appointment)
            .filter(models.Appointment.date == date.today())
            .all()
        )
        recent_records = db.query(models.Record).limit(20).all()
        return total_patients, today_appointments, recent_records

    @staticmethod
    def chat_context(db: Session):
        total_patients = db.query(models.Patient).count()
        today_appointments = (
            db.query(models.Appointment)
            .options(joinedload(models.Appointment.patient))
            .filter(models.Appointment.date == date.today())
            .all()
        )
        recent_logs = (
            db.query(models.Log)
            .order_by(models.Log.created_at.desc())
            .limit(5)
            .all()
        )
        return total_patients, today_appointments, recent_logs
