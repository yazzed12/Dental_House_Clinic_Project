from typing import Optional, List
from sqlalchemy.orm import Session
from sqlalchemy import func
import models

class SymptomRepository:
    def get_active(self, db: Session) -> List[models.Symptom]:
        return db.query(models.Symptom).filter(models.Symptom.is_active != 0).order_by(models.Symptom.name.asc()).all()

    def get_by_name(self, db: Session, name: str) -> Optional[models.Symptom]:
        norm = name.strip().lower()
        return db.query(models.Symptom).filter(func.lower(models.Symptom.name) == norm).first()

    def create(self, db: Session, symptom: models.Symptom) -> models.Symptom:
        db.add(symptom)
        db.commit()
        db.refresh(symptom)
        return symptom

    def create_many(self, db: Session, symptoms: List[models.Symptom]) -> None:
        db.add_all(symptoms)
        db.commit()

    def reactivate(self, db: Session, symptom: models.Symptom) -> models.Symptom:
        symptom.is_active = 1
        db.commit()
        db.refresh(symptom)
        return symptom

    def count(self, db: Session) -> int:
        return db.query(models.Symptom).count()
