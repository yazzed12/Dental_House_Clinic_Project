from sqlalchemy.orm import Session

from fastapi import HTTPException

import models
from app.repositories.symptom_repository import SymptomRepository


DEFAULT_SYMPTOMS = [
    "Cold Sensitivity",
    "Hot Sensitivity",
    "Sweet Sensitivity",
    "Sharp Pain",
    "Dull Ache",
    "Spontaneous Pain",
    "Pain on Biting",
    "Swelling",
    "Bleeding Gums",
    "Tooth Mobility",
    "Visible Decay",
    "Fractured/Chipped",
    "Defective Restoration",
    "Halitosis (Bad Breath)",
]


class SymptomService:
    def __init__(self, repository: SymptomRepository | None = None):
        self.repository = repository or SymptomRepository()

    @staticmethod
    def _serialize(symptom) -> dict:
        return {
            "id": str(symptom.id),
            "name": symptom.name,
            "created_by": str(symptom.created_by) if symptom.created_by else None,
            "is_active": 1 if symptom.is_active else 0,
            "created_at": symptom.created_at.isoformat() + "Z"
            if symptom.created_at
            else None,
        }

    def list_active(self, db: Session) -> list[dict]:
        symptoms = self.repository.get_active(db)
        if not symptoms:
            self.repository.create_many(
                db, [models.Symptom(name=name) for name in DEFAULT_SYMPTOMS]
            )
            symptoms = self.repository.get_active(db)
        return [self._serialize(item) for item in symptoms]

    def create(self, db: Session, name: str, user) -> dict:
        normalized_name = name.strip()
        if not normalized_name:
            raise HTTPException(status_code=400, detail="Symptom name cannot be empty")

        existing = self.repository.get_by_name(db, normalized_name)
        if existing:
            if not existing.is_active:
                existing = self.repository.reactivate(db, existing)
            return self._serialize(existing)

        symptom = self.repository.create(
            db,
            models.Symptom(name=normalized_name, created_by=str(user.id)),
        )
        return self._serialize(symptom)
