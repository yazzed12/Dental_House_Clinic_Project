import uuid
from typing import List, Optional, Tuple

from sqlalchemy import func, text
from sqlalchemy.orm import Session

import models


class UserRepository:
    def get_by_supabase_user_id(self, db: Session, subject: str) -> Optional[models.User]:
        """Phase 11B bridge; safe to call only after migration 002 is applied.

        The active ORM intentionally does not declare the new column before the
        production schema migration, since doing so would break legacy queries.
        """
        try:
            clean_subject = str(uuid.UUID(str(subject)))
        except (ValueError, TypeError, AttributeError):
            return None

        dialect_name = db.bind.dialect.name
        table_name = "public.users" if dialect_name == "postgresql" else "users"

        subject_param = (
            "CAST(:subject AS uuid)" if dialect_name == "postgresql" else ":subject"
        )
        user_id = db.execute(
            text(
                f"SELECT id FROM {table_name} "
                f"WHERE supabase_user_id = {subject_param} "
                f"AND approved_at IS NOT NULL"
            ),
            {"subject": clean_subject},
        ).scalar_one_or_none()
        return self.get_by_id(db, user_id) if user_id is not None else None

    def get_by_id(self, db: Session, user_id) -> Optional[models.User]:
        return db.query(models.User).filter(models.User.id == user_id).first()

    def get_by_username(self, db: Session, username: str) -> Optional[models.User]:
        return db.query(models.User).filter(
            func.lower(models.User.username) == username.strip().lower()
        ).first()

    def get_by_email(self, db: Session, email: str) -> Optional[models.User]:
        return db.query(models.User).filter(
            func.trim(func.lower(models.User.email)) == email.strip().lower()
        ).first()

    def get_by_email_or_username(self, db: Session, identifier: str) -> Optional[models.User]:
        clean_id = identifier.strip().lower()
        return db.query(models.User).filter(
            (models.User.username == clean_id)
            | (func.trim(func.lower(models.User.email)) == clean_id)
        ).first()

    def get_doctors(self, db: Session) -> List[models.User]:
        return db.query(models.User).filter(
            models.User.role == "doctor", models.User.is_active.isnot(False)
        ).all()

    def get_receptionists(self, db: Session) -> List[models.User]:
        return db.query(models.User).filter(
            models.User.role == "receptionist", models.User.is_active.isnot(False)
        ).all()

    def get_doctor_patient_counts(self, db: Session) -> List[Tuple[str, int]]:
        return db.query(
            models.ClinicalReport.doctor_id,
            func.count(func.distinct(models.ClinicalReport.patient_id)).label("count"),
        ).group_by(models.ClinicalReport.doctor_id).all()

    def find_by_username_or_clinic_email(
        self, db: Session, username: str, clinic_email: str
    ) -> Optional[models.User]:
        return db.query(models.User).filter(
            (func.lower(models.User.username) == username)
            | (func.lower(models.User.email) == clinic_email)
        ).first()

    def find_username_conflict(
        self, db: Session, username: str, excluded_user_id
    ) -> Optional[models.User]:
        return db.query(models.User).filter(
            func.lower(models.User.username) == username,
            models.User.id != excluded_user_id,
        ).first()

    def find_email_conflict(
        self, db: Session, clinic_email: str, excluded_user_id
    ) -> Optional[models.User]:
        return db.query(models.User).filter(
            func.lower(models.User.email) == clinic_email,
            models.User.id != excluded_user_id,
        ).first()

    @staticmethod
    def build_user(**values) -> models.User:
        return models.User(**values)

    def create(self, db: Session, user: models.User) -> models.User:
        db.add(user)
        db.commit()
        db.refresh(user)
        return user

    def update(self, db: Session, user: models.User) -> models.User:
        db.commit()
        db.refresh(user)
        return user

    def commit(self, db: Session) -> None:
        db.commit()

    def count(self, db: Session) -> int:
        return db.query(models.User).count()
