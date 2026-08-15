from sqlalchemy.orm import Session

from fastapi import HTTPException

from app.repositories.notification_repository import NotificationRepository


class NotificationService:
    def __init__(self, repository: NotificationRepository | None = None):
        self.repository = repository or NotificationRepository()

    @staticmethod
    def _serialize(notification) -> dict:
        return {
            "id": notification.id,
            "title": notification.title,
            "body": notification.body,
            "type": notification.type,
            "read": bool(notification.read),
            "created_at": notification.created_at.isoformat() + "Z"
            if notification.created_at
            else None,
        }

    def list_notifications(self, db: Session) -> list[dict]:
        return [self._serialize(item) for item in self.repository.get_all(db)]

    def mark_as_read(self, db: Session, notification_id: int) -> dict:
        notification = self.repository.get_by_id(db, notification_id)
        if not notification:
            raise HTTPException(status_code=404, detail="Notification not found")
        self.repository.mark_as_read(db, notification)
        return {"status": "success"}
