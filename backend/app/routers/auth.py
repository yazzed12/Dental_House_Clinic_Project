from collections.abc import Callable

from fastapi import APIRouter, Depends

import models
from app.services.auth_service import AuthService


def create_auth_router(
    *, auth_dependency: Callable, auth_service: AuthService
) -> APIRouter:
    router = APIRouter(prefix="/api/auth", tags=["auth"])

    @router.get("/me")
    def get_me(user: models.User = Depends(auth_dependency)):
        return auth_service.serialize_current_user(user)

    return router
