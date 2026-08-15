from typing import List
from sqlalchemy.orm import Session, joinedload
import models

class RecordRepository:
    def get_all(self, db: Session) -> List[models.Record]:
        return db.query(models.Record).options(joinedload(models.Record.patient)).all()

    def count(self, db: Session) -> int:
        return db.query(models.Record).count()
