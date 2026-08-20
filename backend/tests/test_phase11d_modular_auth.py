from __future__ import annotations

import unittest
from types import SimpleNamespace
from uuid import uuid4

from fastapi import Depends, FastAPI
from fastapi.security import OAuth2PasswordBearer
from fastapi.testclient import TestClient
from jose import jwt
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import models
from app.core.config import get_auth_mode
from app.identity.auth_dependencies import AuthDependencies
from app.identity.identity_provider import IdentityClaims, InvalidIdentityToken
from app.identity.user_resolver import ApplicationUserResolver
from app.repositories.user_repository import UserRepository
from app.routers.auth import create_auth_router
from app.services.auth_service import AuthService
from tests.route_inventory import _application_routes
from tests.support import active_main


class SyntheticIdentityProvider:
    def __init__(self, subject):
        self.subject = subject
        self.tokens = []

    async def verify_access_token(self, token):
        self.tokens.append(token)
        if token != "valid-supabase-token":
            raise InvalidIdentityToken("synthetic rejection")
        return IdentityClaims(subject=self.subject)


class Phase11DModularAuthTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite+pysqlite:///:memory:",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        models.Base.metadata.create_all(self.engine)
        with self.engine.begin() as connection:
            connection.execute(text("ALTER TABLE users ADD COLUMN supabase_user_id TEXT"))
            connection.execute(text("ALTER TABLE users ADD COLUMN approved_at TIMESTAMP"))
        self.sessions = sessionmaker(bind=self.engine)
        self.subject = uuid4()
        self.provider = SyntheticIdentityProvider(self.subject)
        self.service = AuthService()

    def tearDown(self):
        self.engine.dispose()

    def db_dependency(self):
        db = self.sessions()
        try:
            yield db
        finally:
            db.close()

    def build_supabase_app(self):
        token_scheme = OAuth2PasswordBearer(tokenUrl="unused")
        dependencies = AuthDependencies(
            mode="supabase",
            get_db_dependency=self.db_dependency,
            token_dependency=token_scheme,
            auth_service=self.service,
            identity_provider=self.provider,
            user_resolver=ApplicationUserResolver(UserRepository()),
        )
        app = FastAPI()
        app.include_router(
            create_auth_router(
                auth_dependency=dependencies.get_current_user,
                auth_service=self.service,
            )
        )

        @app.get("/doctor-only")
        def doctor_only(user=Depends(dependencies.require_role("doctor"))):
            return {"role": user.role}

        return app

    def add_linked_user(self, *, role="doctor", is_active=1, linked=True, approved=True):
        db = self.sessions()
        try:
            user = models.User(
                id=str(uuid4()),
                username=f"{role}-{uuid4()}",
                email=f"{uuid4()}@clinic.invalid",
                hashed_password="not-used-by-supabase-mode",
                full_name="Linked Clinician",
                role=role,
                is_active=is_active,
            )
            db.add(user)
            db.commit()
            if linked:
                approved_clause = ", approved_at = CURRENT_TIMESTAMP" if approved else ""
                db.execute(
                    text(f"UPDATE users SET supabase_user_id=:subject{approved_clause} WHERE id=:id"),
                    {"subject": str(self.subject), "id": user.id},
                )
                db.commit()
            return {
                "id": user.id,
                "username": user.username,
                "email": user.email,
            }
        finally:
            db.close()

    def test_default_and_explicit_modes_and_invalid_configuration(self):
        self.assertEqual("legacy", get_auth_mode("legacy"))
        self.assertEqual("supabase", get_auth_mode(" SUPABASE "))
        with self.assertRaisesRegex(RuntimeError, "Invalid AUTH_MODE"):
            get_auth_mode("fallback")

    def test_linked_active_user_gets_exact_me_contract_and_database_role(self):
        user = self.add_linked_user(role="doctor", approved=True)
        response = TestClient(self.build_supabase_app()).get(
            "/api/auth/me",
            headers={"Authorization": "Bearer valid-supabase-token"},
        )
        self.assertEqual(200, response.status_code)
        self.assertEqual(
            {
                "id": user["id"],
                "username": user["username"],
                "role": "doctor",
                "full_name": "Linked Clinician",
                "email": user["email"],
                "phone": None,
                "specialization": None,
            },
            response.json(),
        )

    def test_unlinked_inactive_unapproved_and_wrong_role_are_denied(self):
        client = TestClient(self.build_supabase_app())
        headers = {"Authorization": "Bearer valid-supabase-token"}
        # 1. Unlinked user -> 401
        self.assertEqual(401, client.get("/api/auth/me", headers=headers).status_code)

        # 2. Linked + active + unapproved (approved_at IS NULL) -> 401
        self.add_linked_user(is_active=1, approved=False)
        self.assertEqual(401, client.get("/api/auth/me", headers=headers).status_code)

        # 3. Linked + inactive + approved -> 401
        with self.engine.begin() as connection:
            connection.execute(text("DELETE FROM users"))
        self.add_linked_user(is_active=0, approved=True)
        self.assertEqual(401, client.get("/api/auth/me", headers=headers).status_code)

        # 4. Wrong role -> 403
        with self.engine.begin() as connection:
            connection.execute(text("DELETE FROM users"))
        self.add_linked_user(role="receptionist", is_active=1, approved=True)
        self.assertEqual(403, client.get("/doctor-only", headers=headers).status_code)

    def test_malformed_subject_fails_closed_without_500_error(self):
        provider = SyntheticIdentityProvider("not-a-valid-uuid")
        token_scheme = OAuth2PasswordBearer(tokenUrl="unused")
        dependencies = AuthDependencies(
            mode="supabase",
            get_db_dependency=self.db_dependency,
            token_dependency=token_scheme,
            auth_service=self.service,
            identity_provider=provider,
            user_resolver=ApplicationUserResolver(UserRepository()),
        )
        app = FastAPI()
        app.include_router(
            create_auth_router(
                auth_dependency=dependencies.get_current_user,
                auth_service=self.service,
            )
        )
        client = TestClient(app)
        response = client.get("/api/auth/me", headers={"Authorization": "Bearer valid-supabase-token"})
        self.assertEqual(401, response.status_code)

    def test_supabase_mode_rejects_legacy_jwt_without_fallback(self):
        self.add_linked_user()
        legacy = jwt.encode({"sub": "linked"}, "legacy-secret", algorithm="HS256")
        response = TestClient(self.build_supabase_app()).get(
            "/api/auth/me", headers={"Authorization": f"Bearer {legacy}"}
        )
        self.assertEqual(401, response.status_code)
        self.assertEqual([legacy], self.provider.tokens)

    def test_schema_guard_and_linked_user_startup_safety(self):
        db = self.sessions()
        try:
            # 1. Complete schema succeeds
            self.service.validate_supabase_identity_schema(db)
            linked = self.add_linked_user()
            self.assertIn(linked["id"], self.service.linked_user_ids(db))
        finally:
            db.close()

        # 2. Base table missing both columns -> fails
        missing_both_engine = create_engine("sqlite+pysqlite:///:memory:")
        models.Base.metadata.create_all(missing_both_engine)
        missing_both_db = sessionmaker(bind=missing_both_engine)()
        try:
            with self.assertRaisesRegex(RuntimeError, "approved_at, supabase_user_id"):
                self.service.validate_supabase_identity_schema(missing_both_db)
        finally:
            missing_both_db.close()
            missing_both_engine.dispose()

        # 3. Table missing approved_at -> fails
        missing_approved_engine = create_engine("sqlite+pysqlite:///:memory:")
        models.Base.metadata.create_all(missing_approved_engine)
        with missing_approved_engine.begin() as conn:
            conn.execute(text("ALTER TABLE users ADD COLUMN supabase_user_id TEXT"))
        missing_approved_db = sessionmaker(bind=missing_approved_engine)()
        try:
            with self.assertRaisesRegex(RuntimeError, "approved_at"):
                self.service.validate_supabase_identity_schema(missing_approved_db)
        finally:
            missing_approved_db.close()
            missing_approved_engine.dispose()

        # 4. Table missing supabase_user_id -> fails
        missing_subject_engine = create_engine("sqlite+pysqlite:///:memory:")
        models.Base.metadata.create_all(missing_subject_engine)
        with missing_subject_engine.begin() as conn:
            conn.execute(text("ALTER TABLE users ADD COLUMN approved_at TIMESTAMP"))
        missing_subject_db = sessionmaker(bind=missing_subject_engine)()
        try:
            with self.assertRaisesRegex(RuntimeError, "supabase_user_id"):
                self.service.validate_supabase_identity_schema(missing_subject_db)
        finally:
            missing_subject_db.close()
            missing_subject_engine.dispose()

    def test_legacy_routes_are_registered_but_guarded_when_supabase_selected(self):
        original_mode = active_main.AUTH_MODE
        active_main.AUTH_MODE = "supabase"
        try:
            client = TestClient(active_main.app)
            response = client.post(
                "/api/auth/login", json={"email": "nobody", "password": "irrelevant"}
            )
            self.assertEqual(404, response.status_code)
        finally:
            active_main.AUTH_MODE = original_mode

    def test_route_count_and_me_has_modular_owner(self):
        routes = list(_application_routes(active_main.app.routes))
        registrations = [
            (method, route.path) for route in routes for method in route.methods or []
        ]
        self.assertEqual(74, len(registrations))
        me = next(route for route in routes if route.path == "/api/auth/me")
        self.assertEqual("app.routers.auth", me.endpoint.__module__)

    def test_bootstrap_and_email_rewrite_are_noops_in_supabase_mode(self):
        active_main.bootstrap_default_users("supabase")
        active_main.migrate_existing_users_to_clinic_emails(
            SimpleNamespace(), "supabase"
        )

    def test_legacy_startup_does_not_rewrite_a_linked_user(self):
        linked = self.add_linked_user()
        original_email = linked["email"]
        db = self.sessions()
        try:
            active_main.migrate_existing_users_to_clinic_emails(db, "legacy")
            preserved = db.query(models.User).filter(models.User.id == linked["id"]).one()
            self.assertEqual(original_email, preserved.email)
        finally:
            db.close()
