from collections.abc import Callable
from typing import Union

from fastapi import HTTPException
from sqlalchemy.orm import Session

import models
from app.repositories.patient_repository import PatientRepository


class PatientService:
    def __init__(
        self,
        repository: PatientRepository | None = None,
        audit_logger: Callable | None = None,
    ):
        self.repository = repository or PatientRepository()
        self.audit_logger = audit_logger

    @staticmethod
    def _serialize(patient) -> dict:
        return {
            "id": patient.id,
            "name": patient.name,
            "age": patient.age,
            "phone": patient.phone,
            "gender": patient.gender,
            "status": patient.status,
            "condition": patient.condition,
            "lastVisit": patient.last_visit,
            "bloodType": patient.blood_type,
        }

    def list_patients(self, db: Session) -> list[dict]:
        return [self._serialize(patient) for patient in self.repository.get_all(db)]

    def get_patient(self, db: Session, patient_id: Union[int, str]) -> dict:
        patient = self.repository.get_by_id(db, patient_id)
        if not patient:
            raise HTTPException(status_code=404, detail="Patient not found")
        return self._serialize(patient)

    def create_patient(self, db: Session, payload) -> dict:
        patient = self.repository.create(db, models.Patient(**payload.dict()))
        return self._serialize(patient)

    def update_patient(
        self, db: Session, patient_id: Union[int, str], payload
    ) -> dict:
        patient = self.repository.get_by_id(db, patient_id)
        if not patient:
            raise HTTPException(status_code=404, detail="Patient not found")

        for key, value in payload.dict(exclude_unset=True).items():
            setattr(patient, key, value)
        patient = self.repository.update(db, patient)
        return {
            "status": "success",
            "patient": {
                "id": patient.id,
                "name": patient.name,
                "age": patient.age,
                "phone": patient.phone,
                "gender": patient.gender,
                "status": patient.status,
                "condition": patient.condition,
                "bloodType": patient.blood_type,
            },
        }

    def delete_patient(
        self, db: Session, patient_id: Union[int, str], user
    ) -> dict:
        patient = self.repository.get_by_id(db, patient_id)
        if not patient:
            raise HTTPException(status_code=404, detail="Patient not found")

        pid = str(patient_id)
        if self.repository.has_medical_history(db, patient_id):
            patient.status = "Archived"
            if self.audit_logger:
                self.audit_logger(
                    db,
                    f"Patient {patient.name} archived safely due to existing clinical/appointment history.",
                    doctor_id=user.id,
                    patient_id=pid,
                )
            self.repository.commit(db)
            return {
                "status": "success",
                "action": "archived",
                "message": "Patient archived safely to preserve clinical history.",
            }

        self.repository.stage_delete(db, patient)
        if self.audit_logger:
            self.audit_logger(
                db,
                f"Patient {patient.name} deleted completely.",
                doctor_id=user.id,
            )
        self.repository.commit(db)
        return {
            "status": "success",
            "action": "deleted",
            "message": "Patient deleted successfully from system.",
        }
