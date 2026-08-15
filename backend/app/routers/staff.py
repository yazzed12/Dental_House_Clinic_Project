from collections.abc import Callable

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.schemas.user import UserCreate, UserStaffUpdate
from app.services.staff_service import StaffService


def create_staff_router(
    *,
    get_db_dependency: Callable,
    authenticated_dependency: Callable,
    admin_dependency: Callable,
    password_hasher: Callable,
    clinic_email_factory: Callable,
    pending_store_module,
) -> APIRouter:
    router = APIRouter()
    service = StaffService(
        password_hasher=password_hasher,
        clinic_email_factory=clinic_email_factory,
        pending_store_module=pending_store_module,
    )

    @router.get("/api/doctors")
    def get_doctors(
        db: Session = Depends(get_db_dependency),
        current_user=Depends(authenticated_dependency),
    ):
        return service.list_doctors(db)

    @router.get("/api/receptionists")
    def get_receptionists(
        db: Session = Depends(get_db_dependency),
        current_user=Depends(authenticated_dependency),
    ):
        return service.list_receptionists(db)

    @router.post("/api/staff")
    def create_staff(
        payload: UserCreate,
        db: Session = Depends(get_db_dependency),
        user=Depends(admin_dependency),
    ):
        return service.create_staff(db, payload)

    @router.put("/api/staff/{user_id}")
    def update_staff(
        user_id: int,
        payload: UserStaffUpdate,
        db: Session = Depends(get_db_dependency),
        user=Depends(admin_dependency),
    ):
        return service.update_staff(db, user_id, payload)

    @router.delete("/api/staff/{user_id}")
    def delete_staff(
        user_id: int,
        db: Session = Depends(get_db_dependency),
        user=Depends(admin_dependency),
    ):
        return service.delete_staff(db, user_id)

    return router
