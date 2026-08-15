from typing import Optional
from sqlalchemy.orm import Session
import models

class ClinicSettingsRepository:
    def get(self, db: Session) -> Optional[models.ClinicSettings]:
        return db.query(models.ClinicSettings).first()

    def update(self, db: Session, settings: models.ClinicSettings) -> models.ClinicSettings:
        db.commit()
        db.refresh(settings)
        return settings

    def update_user(self, db: Session, user: models.User) -> models.User:
        db.commit()
        db.refresh(user)
        return user
