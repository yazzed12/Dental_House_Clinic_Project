from collections.abc import Callable
import sqlite3

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.repositories.clinic_settings_repository import ClinicSettingsRepository


class ClinicSettingsService:
    def __init__(
        self,
        repository: ClinicSettingsRepository | None = None,
        password_hasher: Callable | None = None,
        pending_store_module=None,
    ):
        self.repository = repository or ClinicSettingsRepository()
        self.password_hasher = password_hasher
        self.pending_store = pending_store_module

    @staticmethod
    def _require_clinic_access(user) -> None:
        if user.role not in ["admin", "doctor"]:
            raise HTTPException(status_code=403, detail="Insufficient permissions")

    @staticmethod
    def _serialize_profile(user) -> dict:
        return {
            "id": user.id,
            "username": user.username,
            "role": user.role,
            "full_name": user.full_name,
            "email": user.email,
            "phone": user.phone,
            "specialization": user.specialization,
        }

    def get_clinic_settings(self, db: Session, user):
        self._require_clinic_access(user)
        settings = self.repository.get(db)
        if not settings:
            raise HTTPException(status_code=404, detail="Settings not found")
        return settings

    def update_clinic_settings(self, db: Session, payload, user):
        self._require_clinic_access(user)
        settings = self.repository.get(db)
        if not settings:
            raise HTTPException(status_code=404, detail="Settings not found")
        for key, value in payload.dict(exclude_unset=True).items():
            setattr(settings, key, value)
        return self.repository.update(db, settings)

    def get_profile(self, user) -> dict:
        return self._serialize_profile(user)

    def update_profile(self, db: Session, payload, user) -> dict:
        update_data = payload.dict(exclude_unset=True)
        if "password" in update_data and update_data["password"]:
            user.hashed_password = self.password_hasher(update_data["password"])
            del update_data["password"]

        if "email" in update_data and update_data["email"]:
            personal_email = update_data["email"].strip().lower()
            clinic_email = user.email
            connection = sqlite3.connect(self.pending_store.DB_PATH)
            cursor = connection.cursor()
            cursor.execute(
                "SELECT clinic_email FROM email_mappings "
                "WHERE personal_email = ? AND clinic_email != ?",
                (personal_email, clinic_email),
            )
            row = cursor.fetchone()
            connection.close()
            if row:
                raise HTTPException(
                    status_code=400,
                    detail="Email address is already in use by another account",
                )
            self.pending_store.save_email_mapping(clinic_email, personal_email)
            del update_data["email"]

        for key, value in update_data.items():
            setattr(user, key, value)
        user = self.repository.update_user(db, user)
        return self._serialize_profile(user)
