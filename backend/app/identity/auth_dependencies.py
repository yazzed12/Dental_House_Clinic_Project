from __future__ import annotations

from collections.abc import Callable
from typing import Any

from fastapi import Depends, HTTPException
from sqlalchemy.orm import Session

import models
from app.identity.identity_provider import IdentityProvider, InvalidIdentityToken
from app.identity.user_resolver import ApplicationIdentityDenied, ApplicationUserResolver
from app.services.auth_service import AuthService, credentials_exception


class AuthDependencies:
    """Mode-selected FastAPI dependencies with no cross-authority fallback."""

    def __init__(
        self,
        *,
        mode: str,
        get_db_dependency: Callable,
        token_dependency: Any,
        auth_service: AuthService,
        secret_key: str | None = None,
        algorithm: str | None = None,
        is_blacklisted: Callable[[str], bool] | None = None,
        identity_provider: IdentityProvider | None = None,
        user_resolver: ApplicationUserResolver | None = None,
    ) -> None:
        if mode == "legacy":
            if not secret_key or not algorithm or is_blacklisted is None:
                raise RuntimeError("Legacy authentication dependencies are incomplete")

            def get_current_user(
                db: Session = Depends(get_db_dependency),
                token: str = Depends(token_dependency),
            ) -> models.User:
                return auth_service.resolve_legacy_token(
                    db,
                    token,
                    secret_key=secret_key,
                    algorithm=algorithm,
                    is_blacklisted=is_blacklisted,
                )

        elif mode == "supabase":
            if identity_provider is None or user_resolver is None:
                raise RuntimeError("Supabase authentication dependencies are incomplete")

            async def get_current_user(
                db: Session = Depends(get_db_dependency),
                token: str = Depends(token_dependency),
            ) -> models.User:
                try:
                    claims = await identity_provider.verify_access_token(token)
                    return user_resolver.resolve(db, claims)
                except (InvalidIdentityToken, ApplicationIdentityDenied):
                    raise credentials_exception()

        else:
            raise RuntimeError(f"Unsupported authentication mode: {mode}")

        self.get_current_user = get_current_user

    def require_role(self, role: str):
        def role_checker(user: models.User = Depends(self.get_current_user)):
            if user.role != role and user.role != "admin":
                raise HTTPException(status_code=403, detail="Insufficient permissions")
            return user

        return role_checker

    def require_staff_role(self):
        def role_checker(user: models.User = Depends(self.get_current_user)):
            if user.role not in ["doctor", "receptionist", "admin"]:
                raise HTTPException(status_code=403, detail="Insufficient permissions")
            return user

        return role_checker
