from typing import Optional, List
from sqlalchemy.orm import Session
import models

class PatientRepository:
    def get_all(self, db: Session) -> List[models.Patient]:
        return db.query(models.Patient).filter(models.Patient.status != "Archived").all()

    def get_by_id(self, db: Session, patient_id: str) -> Optional[models.Patient]:
        pid = str(patient_id)
        return db.query(models.Patient).filter((models.Patient.id == pid) | (models.Patient.id == patient_id)).first()

    def create(self, db: Session, patient: models.Patient) -> models.Patient:
        db.add(patient)
        db.commit()
        db.refresh(patient)
        return patient

    def update(self, db: Session, patient: models.Patient) -> models.Patient:
        db.commit()
        db.refresh(patient)
        return patient

    def stage_delete(self, db: Session, patient: models.Patient) -> None:
        db.delete(patient)

    def has_medical_history(self, db: Session, patient_id: str) -> bool:
        pid = str(patient_id)
        has_appointment = db.query(models.Appointment).filter(
            (models.Appointment.patient_id == pid)
            | (models.Appointment.patient_id == patient_id)
        ).first()
        has_record = db.query(models.Record).filter(
            (models.Record.patient_id == pid) | (models.Record.patient_id == patient_id)
        ).first()
        has_consultation = db.query(models.Consultation).filter(
            (models.Consultation.patient_id == pid)
            | (models.Consultation.patient_id == patient_id)
        ).first()
        has_report = db.query(models.ClinicalReport).filter(
            (models.ClinicalReport.patient_id == pid)
            | (models.ClinicalReport.patient_id == patient_id)
        ).first()
        return bool(has_appointment or has_record or has_consultation or has_report)

    def commit(self, db: Session) -> None:
        db.commit()

    def count(self, db: Session) -> int:
        return db.query(models.Patient).count()
