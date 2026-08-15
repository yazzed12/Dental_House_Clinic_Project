from collections.abc import Callable

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.services.notification_service import NotificationService


def create_notification_router(
    *, get_db_dependency: Callable, auth_dependency: Callable
) -> APIRouter:
    router = APIRouter()
    service = NotificationService()

    @router.get("/api/notifications", dependencies=[Depends(auth_dependency)])
    def get_notifications(db: Session = Depends(get_db_dependency)):
        return service.list_notifications(db)

    @router.patch(
        "/api/notifications/{notification_id}/read",
        dependencies=[Depends(auth_dependency)],
    )
    def mark_notification_read(
        notification_id: int, db: Session = Depends(get_db_dependency)
    ):
        return service.mark_as_read(db, notification_id)

    return router
