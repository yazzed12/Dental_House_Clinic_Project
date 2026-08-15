from collections.abc import Callable
import sqlite3

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.repositories.user_repository import UserRepository


class StaffService:
    _STAFF_ROLES = ("doctor", "receptionist", "admin")

    def __init__(
        self,
        repository: UserRepository | None = None,
        password_hasher: Callable | None = None,
        clinic_email_factory: Callable | None = None,
        pending_store_module=None,
    ):
        self.repository = repository or UserRepository()
        self.password_hasher = password_hasher
        self.clinic_email_factory = clinic_email_factory
        self.pending_store = pending_store_module

    @classmethod
    def _is_clinic_email(cls, email: str) -> bool:
        return any(email.endswith(f"@{role}.com") for role in cls._STAFF_ROLES)

    def list_doctors(self, db: Session) -> list[dict]:
        doctors = self.repository.get_doctors(db)
        counts = self.repository.get_doctor_patient_counts(db)
        counts_map = {doctor_id: count for doctor_id, count in counts}
        return [
            {
                "id": doctor.id,
                "name": doctor.full_name or doctor.username,
                "username": doctor.username,
                "role": doctor.role,
                "email": doctor.email,
                "personal_email": self.pending_store.get_personal_email_by_clinic_email(
                    doctor.email
                ),
                "phone": doctor.phone,
                "specialization": doctor.specialization,
                "status": "online",
                "patients": counts_map.get(doctor.id, 0),
            }
            for doctor in doctors
        ]

    def list_receptionists(self, db: Session) -> list[dict]:
        receptionists = self.repository.get_receptionists(db)
        return [
            {
                "id": receptionist.id,
                "name": receptionist.full_name or receptionist.username,
                "username": receptionist.username,
                "role": receptionist.role,
                "email": receptionist.email,
                "personal_email": self.pending_store.get_personal_email_by_clinic_email(
                    receptionist.email
                ),
                "phone": receptionist.phone,
                "status": "online",
            }
            for receptionist in receptionists
        ]

    def create_staff(self, db: Session, payload) -> dict:
        role_clean = payload.role.strip().lower()
        if role_clean not in self._STAFF_ROLES:
            raise HTTPException(
                status_code=400,
                detail="Invalid role. Must be doctor, receptionist, or admin.",
            )

        username_clean = payload.username.strip().lower()
        if payload.email and "@" in payload.email:
            email_candidate = payload.email.strip().lower()
            if self._is_clinic_email(email_candidate) or payload.personal_email:
                clinic_email = email_candidate
            else:
                clinic_email = self.clinic_email_factory(username_clean, role_clean)
        else:
            clinic_email = self.clinic_email_factory(username_clean, role_clean)

        if self.repository.find_by_username_or_clinic_email(
            db, username_clean, clinic_email
        ):
            raise HTTPException(
                status_code=400, detail="Username or Clinic Email already exists"
            )

        personal_email = (
            payload.personal_email.strip().lower() if payload.personal_email else None
        )
        if not personal_email:
            if payload.email and not self._is_clinic_email(payload.email.strip().lower()):
                personal_email = payload.email.strip().lower()
            else:
                personal_email = f"{username_clean}@personal.com"

        if self.pending_store.is_personal_email_exists(personal_email):
            raise HTTPException(status_code=400, detail="Personal email already exists")

        self.pending_store.save_email_mapping(clinic_email, personal_email)
        new_user = self.repository.build_user(
            username=username_clean,
            hashed_password=self.password_hasher(payload.password),
            full_name=payload.full_name,
            email=clinic_email,
            role=role_clean,
            phone=payload.phone,
            specialization=payload.specialization if role_clean == "doctor" else None,
            is_active=1,
        )
        new_user = self.repository.create(db, new_user)
        return {"status": "success", "id": new_user.id}

    def _personal_email_owner(self, personal_email: str):
        connection = sqlite3.connect(self.pending_store.DB_PATH)
        cursor = connection.cursor()
        cursor.execute(
            "SELECT clinic_email FROM email_mappings WHERE personal_email = ?",
            (personal_email,),
        )
        row = cursor.fetchone()
        connection.close()
        return row[0] if row else None

    def _delete_email_mapping(self, clinic_email: str) -> None:
        connection = sqlite3.connect(self.pending_store.DB_PATH)
        cursor = connection.cursor()
        cursor.execute(
            "DELETE FROM email_mappings WHERE clinic_email = ?",
            (clinic_email.strip().lower(),),
        )
        connection.commit()
        connection.close()

    def update_staff(self, db: Session, user_id: int, payload) -> dict:
        target = self.repository.get_by_id(db, user_id)
        if not target:
            raise HTTPException(status_code=404, detail="Staff member not found")

        new_username = (
            payload.username.strip().lower()
            if payload.username is not None
            else target.username
        )
        new_role = (
            payload.role.strip().lower() if payload.role is not None else target.role
        )
        email_payload = (
            payload.email.strip().lower() if payload.email is not None else None
        )
        personal_payload = (
            payload.personal_email.strip().lower()
            if payload.personal_email is not None
            else None
        )

        if email_payload and not personal_payload and not self._is_clinic_email(
            email_payload
        ):
            personal_payload = email_payload
            email_payload = None

        if email_payload:
            new_clinic_email = email_payload
        elif payload.username is not None or payload.role is not None:
            new_clinic_email = self.clinic_email_factory(new_username, new_role)
        else:
            new_clinic_email = target.email

        if new_username != target.username and self.repository.find_username_conflict(
            db, new_username, target.id
        ):
            raise HTTPException(status_code=400, detail="Username already exists")

        if new_clinic_email.lower() != target.email.lower():
            if self.repository.find_email_conflict(db, new_clinic_email, target.id):
                raise HTTPException(status_code=400, detail="Clinic email already exists")

            existing_personal = self.pending_store.get_personal_email_by_clinic_email(
                target.email
            )
            if existing_personal:
                final_personal = personal_payload or existing_personal
                owner = self._personal_email_owner(final_personal)
                if owner and owner.strip().lower() not in {
                    target.email.strip().lower(),
                    new_clinic_email.lower(),
                }:
                    raise HTTPException(
                        status_code=400,
                        detail="Personal email already in use by another account",
                    )
                self.pending_store.save_email_mapping(new_clinic_email, final_personal)
                self._delete_email_mapping(target.email)
                personal_payload = None

        target.username = new_username
        target.role = new_role
        target.email = new_clinic_email
        if payload.full_name is not None:
            target.full_name = payload.full_name
        if payload.phone is not None:
            target.phone = payload.phone
        if payload.is_active is not None:
            target.is_active = payload.is_active
        if payload.password is not None and payload.password.strip() != "":
            target.hashed_password = self.password_hasher(payload.password)
        if payload.specialization is not None:
            target.specialization = (
                payload.specialization if target.role == "doctor" else None
            )
        if target.role != "doctor":
            target.specialization = None

        if personal_payload:
            owner = self._personal_email_owner(personal_payload)
            if owner and owner.strip().lower() != target.email.strip().lower():
                raise HTTPException(
                    status_code=400,
                    detail="Personal email already in use by another account",
                )
            self.pending_store.save_email_mapping(target.email, personal_payload)

        self.repository.commit(db)
        return {"status": "success"}

    def delete_staff(self, db: Session, user_id: int) -> dict:
        target = self.repository.get_by_id(db, user_id)
        if not target:
            raise HTTPException(status_code=404, detail="Staff member not found")
        target.is_active = 0
        self.repository.commit(db)
        return {"status": "success"}
