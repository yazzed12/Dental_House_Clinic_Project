"""Isolated test harness for the current ``backend/main.py`` application.

The environment is pinned before importing the active runtime so module-level
SQLAlchemy initialization can never resolve to the production Supabase URL.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path

from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ["ENVIRONMENT"] = "test"
os.environ["REQUIRE_POSTGRES"] = "false"
os.environ["DATABASE_URL"] = "sqlite+pysqlite:///:memory:"
os.environ["AUTH_MODE"] = "legacy"
os.environ.setdefault("SECRET_KEY", "characterization-tests-only-secret")

import main as active_main  # noqa: E402  (environment must be set first)
import models  # noqa: E402
import pending_store  # noqa: E402

TEST_DATABASE_URL = "sqlite+pysqlite:///:memory:"
TEST_ENGINE = create_engine(
    TEST_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=TEST_ENGINE)

_pending_directory = tempfile.TemporaryDirectory(prefix="smart-clinic-tests-")
pending_store.DB_PATH = str(Path(_pending_directory.name) / "pending_users.db")


@event.listens_for(TestingSessionLocal.class_, "before_flush")
def _supply_test_ids(session, _flush_context, _instances):
    """Emulate PostgreSQL-side UUID defaults in the disposable test database."""

    for instance in session.new:
        if hasattr(instance, "id") and getattr(instance, "id") is None:
            instance.id = str(uuid.uuid4())


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


active_main.app.dependency_overrides[active_main.get_db] = override_get_db


def reset_database() -> None:
    active_main.Base.metadata.drop_all(bind=TEST_ENGINE)
    active_main.Base.metadata.create_all(bind=TEST_ENGINE)
    pending_path = Path(pending_store.DB_PATH)
    if pending_path.exists():
        pending_path.unlink()


def add_user(
    *,
    user_id: str,
    email: str,
    role: str,
    password: str = "CorrectPassword!",
    full_name: str | None = None,
) -> models.User:
    db = TestingSessionLocal()
    try:
        user = models.User(
            id=user_id,
            username=email.split("@", 1)[0],
            email=email,
            full_name=full_name or role.title(),
            role=role,
            is_active=1,
            hashed_password=active_main.pwd_context.hash(password),
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        db.expunge(user)
        return user
    finally:
        db.close()


def add_patient(*, patient_id: str = "patient-1") -> models.Patient:
    db = TestingSessionLocal()
    try:
        patient = models.Patient(
            id=patient_id,
            name="Characterization Patient",
            age=34,
            phone="01000000000",
            gender="Female",
            status="Active",
            condition="Routine Checkup",
            last_visit="2026-08-01",
            blood_type="O+",
        )
        db.add(patient)
        db.commit()
        db.refresh(patient)
        db.expunge(patient)
        return patient
    finally:
        db.close()


def bearer_token(email: str) -> dict[str, str]:
    token = active_main.jwt.encode(
        {"sub": email}, active_main.SECRET_KEY, algorithm=active_main.ALGORITHM
    )
    return {"Authorization": f"Bearer {token}"}
