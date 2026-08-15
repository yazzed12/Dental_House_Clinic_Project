from __future__ import annotations

from collections.abc import Callable

from fastapi import HTTPException, status
from jose import JWTError, jwt
from sqlalchemy import func, inspect, text
from sqlalchemy.orm import Session

import models


def credentials_exception() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )


class AuthService:
    """Application authentication behavior over the active root model/session universe."""

    @staticmethod
    def serialize_current_user(user: models.User) -> dict:
        return {
            "id": str(user.id) if user.id is not None else None,
            "username": user.username,
            "role": user.role,
            "full_name": user.full_name,
            "email": user.email,
            "phone": user.phone,
            "specialization": user.specialization,
        }

    @staticmethod
    def resolve_legacy_token(
        db: Session,
        token: str,
        *,
        secret_key: str,
        algorithm: str,
        is_blacklisted: Callable[[str], bool],
    ) -> models.User:
        denied = credentials_exception()
        if is_blacklisted(token):
            raise denied
        try:
            payload = jwt.decode(token, secret_key, algorithms=[algorithm])
            subject = payload.get("sub")
            if not isinstance(subject, str) or not subject:
                raise denied
        except JWTError:
            raise denied

        user = db.query(models.User).filter(
            (models.User.username == subject)
            | (func.trim(func.lower(models.User.email)) == subject.lower())
        ).first()
        if user is None:
            raise denied
        return user

    @staticmethod
    def get_user_table_columns(db: Session) -> set[str]:
        schema = "public" if db.bind.dialect.name == "postgresql" else None
        return {
            column["name"]
            for column in inspect(db.bind).get_columns("users", schema=schema)
        }

    @staticmethod
    def has_supabase_identity_column(db: Session) -> bool:
        return "supabase_user_id" in AuthService.get_user_table_columns(db)

    def validate_supabase_identity_schema(self, db: Session) -> None:
        columns = self.get_user_table_columns(db)
        required_columns = {"supabase_user_id", "approved_at"}
        missing = required_columns - columns
        if missing:
            missing_fmt = ", ".join(sorted(missing))
            raise RuntimeError(
                f"AUTH_MODE=supabase requires public.users columns: {missing_fmt}; "
                "apply the approved identity-link migration before startup"
            )

    def linked_user_ids(self, db: Session) -> set[str]:
        if not self.has_supabase_identity_column(db):
            return set()
        table = "public.users" if db.bind.dialect.name == "postgresql" else "users"
        rows = db.execute(
            text(f"SELECT id FROM {table} WHERE supabase_user_id IS NOT NULL")
        ).scalars()
        return {str(value) for value in rows}
