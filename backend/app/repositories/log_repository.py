from typing import List
from sqlalchemy.orm import Session
import models

class LogRepository:
    def get_all(self, db: Session) -> List[models.Log]:
        return db.query(models.Log).order_by(models.Log.created_at.desc()).all()

    def get_recent(self, db: Session, limit: int = 5) -> List[models.Log]:
        return db.query(models.Log).order_by(models.Log.created_at.desc()).limit(limit).all()

    def create(self, db: Session, log: models.Log) -> models.Log:
        db.add(log)
        db.commit()
        db.refresh(log)
        return log

    def count(self, db: Session) -> int:
        return db.query(models.Log).count()
