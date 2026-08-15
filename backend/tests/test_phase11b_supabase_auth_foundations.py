from __future__ import annotations

import importlib
import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from jose import jwk, jwt
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import SupabaseAuthSettings
from app.identity.identity_provider import IdentityClaims, InvalidIdentityToken, parse_bearer_token
from app.identity.migration_planning import (
    IdentityMigrationConflict,
    PersonalEmailUpdate,
    plan_personal_email_update,
    validate_auth_email_match,
    validate_identity_link,
    validate_unique_personal_email_updates,
)
from app.identity.supabase_auth_provider import SupabaseJwtProvider
from app.identity.user_resolver import ApplicationIdentityDenied, ApplicationUserResolver
from app.repositories.user_repository import UserRepository
import models


class SupabaseJwtProviderTests(unittest.IsolatedAsyncioTestCase):
    @classmethod
    def setUpClass(cls):
        private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        cls.private_pem = private_key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
        public_pem = private_key.public_key().public_bytes(
            serialization.Encoding.PEM,
            serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        cls.key_id = "synthetic-phase11b-key"
        cls.public_jwk = jwk.construct(public_pem, algorithm="RS256").to_dict()
        cls.public_jwk["kid"] = cls.key_id
        cls.settings = SupabaseAuthSettings(
            url="https://isolated.invalid",
            issuer="https://isolated.invalid/auth/v1",
            jwks_url="https://isolated.invalid/auth/v1/.well-known/jwks.json",
            audience="authenticated",
            allowed_algorithms=("RS256",),
        )

    def setUp(self):
        async def synthetic_jwks(_url):
            return {"keys": [self.public_jwk]}

        self.provider = SupabaseJwtProvider(self.settings, synthetic_jwks)
        self.subject = uuid4()

    def token(self, **overrides):
        now = datetime.now(timezone.utc)
        payload = {
            "sub": str(self.subject),
            "iss": self.settings.issuer,
            "aud": "authenticated",
            "iat": now,
            "exp": now + timedelta(minutes=5),
        }
        payload.update(overrides)
        return jwt.encode(
            payload,
            self.private_pem,
            algorithm="RS256",
            headers={"kid": self.key_id},
        )

    async def assert_rejected(self, token):
        with self.assertRaises(InvalidIdentityToken):
            await self.provider.verify_access_token(token)

    async def test_valid_synthetic_supabase_jwt_is_accepted(self):
        claims = await self.provider.verify_access_token(self.token())
        self.assertEqual(self.subject, claims.subject)

    async def test_invalid_signature_is_rejected(self):
        other_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        other_pem = other_key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
        token = jwt.encode(
            {
                "sub": str(self.subject),
                "iss": self.settings.issuer,
                "aud": "authenticated",
                "exp": datetime.now(timezone.utc) + timedelta(minutes=5),
            },
            other_pem,
            algorithm="RS256",
            headers={"kid": self.key_id},
        )
        await self.assert_rejected(token)

    async def test_expired_token_is_rejected(self):
        await self.assert_rejected(
            self.token(exp=datetime.now(timezone.utc) - timedelta(seconds=1))
        )

    async def test_wrong_issuer_is_rejected(self):
        await self.assert_rejected(self.token(iss="https://wrong.invalid/auth/v1"))

    async def test_wrong_audience_is_rejected(self):
        await self.assert_rejected(self.token(aud="wrong-audience"))

    async def test_unsupported_algorithm_is_rejected_before_verification(self):
        token = jwt.encode(
            {"sub": str(self.subject)},
            "synthetic-secret",
            algorithm="HS256",
            headers={"kid": self.key_id},
        )
        await self.assert_rejected(token)

    async def test_missing_subject_is_rejected(self):
        await self.assert_rejected(self.token(sub=None))

    async def test_malformed_subject_is_rejected(self):
        await self.assert_rejected(self.token(sub="not-a-uuid"))

    async def test_unknown_or_missing_kid_is_rejected(self):
        unknown = jwt.encode(
            {
                "sub": str(self.subject),
                "iss": self.settings.issuer,
                "aud": "authenticated",
                "exp": datetime.now(timezone.utc) + timedelta(minutes=5),
            },
            self.private_pem,
            algorithm="RS256",
            headers={"kid": "unknown"},
        )
        await self.assert_rejected(unknown)

    async def test_untrusted_role_claims_are_not_returned_as_authorization(self):
        claims = await self.provider.verify_access_token(
            self.token(role="admin", user_metadata={"role": "admin"})
        )
        self.assertEqual(IdentityClaims(subject=self.subject), claims)
        self.assertFalse(hasattr(claims, "role"))

    def test_bearer_parser_accepts_only_a_single_nonempty_bearer_credential(self):
        self.assertEqual("abc.def.ghi", parse_bearer_token("Bearer abc.def.ghi"))
        for value in ("", "Basic token", "Bearer", "Bearer a b"):
            with self.subTest(value=value), self.assertRaises(InvalidIdentityToken):
                parse_bearer_token(value)


class FakeLinkedUserRepository:
    def __init__(self, user):
        self.user = user
        self.subjects = []

    def get_by_supabase_user_id(self, _db, subject):
        self.subjects.append(subject)
        return self.user


class ApplicationUserResolverTests(unittest.TestCase):
    def setUp(self):
        self.claims = IdentityClaims(subject=uuid4())

    def test_linked_active_user_resolves_with_canonical_application_role(self):
        user = SimpleNamespace(is_active=True, role="doctor")
        repository = FakeLinkedUserRepository(user)
        resolved = ApplicationUserResolver(repository).resolve(object(), self.claims)
        self.assertIs(user, resolved)
        self.assertEqual("doctor", resolved.role)
        self.assertEqual([str(self.claims.subject)], repository.subjects)

    def test_linked_inactive_user_is_denied(self):
        resolver = ApplicationUserResolver(
            FakeLinkedUserRepository(SimpleNamespace(is_active=False, role="admin"))
        )
        with self.assertRaises(ApplicationIdentityDenied):
            resolver.resolve(object(), self.claims)

    def test_unlinked_identity_is_denied(self):
        with self.assertRaises(ApplicationIdentityDenied):
            ApplicationUserResolver(FakeLinkedUserRepository(None)).resolve(
                object(), self.claims
            )

    def test_identity_claims_cannot_override_application_role(self):
        user = SimpleNamespace(is_active=True, role="receptionist")
        resolved = ApplicationUserResolver(FakeLinkedUserRepository(user)).resolve(
            object(), self.claims
        )
        self.assertEqual("receptionist", resolved.role)

    def test_root_repository_resolves_linked_user_in_disposable_database(self):
        engine = create_engine(
            "sqlite+pysqlite:///:memory:",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        models.Base.metadata.create_all(engine)
        with engine.begin() as connection:
            connection.execute(text("ALTER TABLE users ADD COLUMN supabase_user_id TEXT"))
            connection.execute(text("ALTER TABLE users ADD COLUMN approved_at TIMESTAMP"))
        session_factory = sessionmaker(bind=engine)
        db = session_factory()
        try:
            user = models.User(
                id="domain-user",
                username="linked-user",
                email="linked@clinic.invalid",
                hashed_password="synthetic-not-used",
                role="doctor",
                is_active=1,
            )
            db.add(user)
            db.commit()
            db.execute(
                text("UPDATE users SET supabase_user_id = :subject, approved_at = CURRENT_TIMESTAMP WHERE id = :user_id"),
                {"subject": str(self.claims.subject), "user_id": user.id},
            )
            db.commit()
            resolved = ApplicationUserResolver(UserRepository()).resolve(db, self.claims)
            self.assertEqual("domain-user", resolved.id)
            self.assertEqual("doctor", resolved.role)
        finally:
            db.close()
            engine.dispose()

    def test_root_repository_rejects_unapproved_user_when_approved_at_is_null(self):
        engine = create_engine(
            "sqlite+pysqlite:///:memory:",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        models.Base.metadata.create_all(engine)
        with engine.begin() as connection:
            connection.execute(text("ALTER TABLE users ADD COLUMN supabase_user_id TEXT"))
            connection.execute(text("ALTER TABLE users ADD COLUMN approved_at TIMESTAMP"))
        session_factory = sessionmaker(bind=engine)
        db = session_factory()
        try:
            user = models.User(
                id="unapproved-user",
                username="unapproved-user",
                email="unapproved@clinic.invalid",
                hashed_password="synthetic-not-used",
                role="doctor",
                is_active=1,
            )
            db.add(user)
            db.commit()
            db.execute(
                text("UPDATE users SET supabase_user_id = :subject WHERE id = :user_id"),
                {"subject": str(self.claims.subject), "user_id": user.id},
            )
            db.commit()
            with self.assertRaises(ApplicationIdentityDenied):
                ApplicationUserResolver(UserRepository()).resolve(db, self.claims)
        finally:
            db.close()
            engine.dispose()

    def test_root_repository_rejects_malformed_supabase_subject_fails_closed(self):
        repo = UserRepository()
        engine = create_engine(
            "sqlite+pysqlite:///:memory:",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        models.Base.metadata.create_all(engine)
        session_factory = sessionmaker(bind=engine)
        db = session_factory()
        try:
            for malformed in ("not-a-uuid", "123", "", None, "admin"):
                self.assertIsNone(repo.get_by_supabase_user_id(db, malformed))
        finally:
            db.close()
            engine.dispose()


class MigrationPlanningTests(unittest.TestCase):
    def test_personal_email_plan_normalizes_and_is_idempotent(self):
        planned = plan_personal_email_update(
            user_id="domain-user", mapped_email="  Person@Example.COM ", current_personal_email=None
        )
        self.assertEqual("person@example.com", planned.personal_email)
        self.assertIsNone(
            plan_personal_email_update(
                user_id="domain-user",
                mapped_email="person@example.com",
                current_personal_email="PERSON@example.com",
            )
        )

    def test_personal_email_plan_never_overwrites_a_different_value(self):
        with self.assertRaises(IdentityMigrationConflict):
            plan_personal_email_update(
                user_id="domain-user",
                mapped_email="one@example.com",
                current_personal_email="two@example.com",
            )

    def test_identity_link_requires_explicit_domain_match_and_is_idempotent(self):
        validate_identity_link(
            intended_user_id="user-1",
            resolved_user_id="user-1",
            existing_subject="subject-1",
            new_subject="subject-1",
        )
        with self.assertRaises(IdentityMigrationConflict):
            validate_identity_link(
                intended_user_id="user-1",
                resolved_user_id="user-2",
                existing_subject=None,
                new_subject="subject-1",
            )
        with self.assertRaises(IdentityMigrationConflict):
            validate_identity_link(
                intended_user_id="user-1",
                resolved_user_id="user-1",
                existing_subject="subject-2",
                new_subject="subject-1",
            )

    def test_batch_planning_rejects_duplicate_personal_email_ownership(self):
        with self.assertRaises(IdentityMigrationConflict):
            validate_unique_personal_email_updates(
                [
                    PersonalEmailUpdate("user-1", "person@example.com"),
                    PersonalEmailUpdate("user-2", "PERSON@example.com"),
                ]
            )

    def test_existing_auth_identity_must_match_intended_normalized_email(self):
        validate_auth_email_match(
            intended_email=" Person@Example.com ",
            existing_auth_email="person@example.com",
        )
        with self.assertRaises(IdentityMigrationConflict):
            validate_auth_email_match(
                intended_email="person@example.com",
                existing_auth_email="different@example.com",
            )

    def test_compatibility_database_paths_do_not_create_a_parallel_universe(self):
        active_database = importlib.import_module("database")
        active_models = importlib.import_module("models")
        compatibility_session = importlib.import_module("app.database.session")
        compatibility_models = importlib.import_module("app.models")
        self.assertIs(compatibility_session.Base, active_database.Base)
        self.assertIs(compatibility_session.engine, active_database.engine)
        self.assertIs(compatibility_models.User, active_models.User)


if __name__ == "__main__":
    unittest.main()
