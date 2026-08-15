from collections.abc import Callable

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.schemas.clinic_settings import ClinicSettingsResponse, ClinicSettingsUpdate
from app.schemas.user import UserProfile, UserProfileUpdate
from app.services.clinic_settings_service import ClinicSettingsService


def create_clinic_settings_router(
    *,
    get_db_dependency: Callable,
    auth_dependency: Callable,
    password_hasher: Callable,
    pending_store_module,
) -> APIRouter:
    router = APIRouter()
    service = ClinicSettingsService(
        password_hasher=password_hasher,
        pending_store_module=pending_store_module,
    )

    @router.get("/api/settings/clinic", response_model=ClinicSettingsResponse)
    def get_clinic_settings(
        db: Session = Depends(get_db_dependency), user=Depends(auth_dependency)
    ):
        return service.get_clinic_settings(db, user)

    @router.put("/api/settings/clinic", response_model=ClinicSettingsResponse)
    def update_clinic_settings(
        payload: ClinicSettingsUpdate,
        db: Session = Depends(get_db_dependency),
        user=Depends(auth_dependency),
    ):
        return service.update_clinic_settings(db, payload, user)

    @router.get("/api/settings/profile", response_model=UserProfile)
    def get_profile_settings(
        db: Session = Depends(get_db_dependency), user=Depends(auth_dependency)
    ):
        return service.get_profile(user)

    @router.put("/api/settings/profile", response_model=UserProfile)
    def update_profile_settings(
        payload: UserProfileUpdate,
        db: Session = Depends(get_db_dependency),
        user=Depends(auth_dependency),
    ):
        return service.update_profile(db, payload, user)

    return router
