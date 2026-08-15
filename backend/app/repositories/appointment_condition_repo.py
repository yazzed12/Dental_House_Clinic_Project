from typing import Optional, List
from sqlalchemy.orm import Session
import models

class AppointmentConditionRepository:
    def get_active(self, db: Session) -> List[models.AppointmentCondition]:
        return db.query(models.AppointmentCondition).filter(models.AppointmentCondition.is_active != 0).all()

    def get_by_name(self, db: Session, name: str) -> Optional[models.AppointmentCondition]:
        norm = name.strip().title()
        return db.query(models.AppointmentCondition).filter(models.AppointmentCondition.name == norm).first()

    def create(self, db: Session, condition: models.AppointmentCondition) -> models.AppointmentCondition:
        db.add(condition)
        db.commit()
        db.refresh(condition)
        return condition

    def count(self, db: Session) -> int:
        return db.query(models.AppointmentCondition).count()
