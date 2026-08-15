from typing import Optional, List
from sqlalchemy.orm import Session
import models

class NotificationRepository:
    def get_all(self, db: Session) -> List[models.Notification]:
        return db.query(models.Notification).order_by(models.Notification.created_at.desc()).all()

    def get_by_id(self, db: Session, notification_id: int) -> Optional[models.Notification]:
        return db.query(models.Notification).filter(models.Notification.id == notification_id).first()

    def mark_as_read(self, db: Session, notification: models.Notification) -> models.Notification:
        notification.read = 1
        db.commit()
        return notification

    def count(self, db: Session) -> int:
        return db.query(models.Notification).count()

    def create(self, db: Session, notification: models.Notification) -> models.Notification:
        db.add(notification)
        db.commit()
        db.refresh(notification)
        return notification
