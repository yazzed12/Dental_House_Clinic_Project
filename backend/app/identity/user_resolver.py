from __future__ import annotations

from typing import Protocol, TypeVar

from sqlalchemy.orm import Session

from app.identity.identity_provider import IdentityClaims

UserT = TypeVar("UserT")


class ApplicationIdentityDenied(Exception):
    """A valid external identity has no permitted application account."""


class SupabaseLinkedUserRepository(Protocol[UserT]):
    def get_by_supabase_user_id(self, db: Session, subject: str) -> UserT | None: ...


class ApplicationUserResolver:
    """Resolves trusted identity subjects to canonical application users."""

    def __init__(self, repository: SupabaseLinkedUserRepository[UserT]) -> None:
        self._repository = repository

    def resolve(self, db: Session, claims: IdentityClaims) -> UserT:
        user = self._repository.get_by_supabase_user_id(db, str(claims.subject))
        if user is None or not bool(getattr(user, "is_active", False)):
            raise ApplicationIdentityDenied("Application access denied")
        return user
