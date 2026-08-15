from __future__ import annotations

import unittest
from uuid import uuid4

from fastapi import FastAPI
from fastapi.security import OAuth2PasswordBearer
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import models
from app.identity.auth_dependencies import AuthDependencies
from app.identity.identity_provider import IdentityClaims, InvalidIdentityToken
from app.identity.user_resolver import ApplicationUserResolver
from app.repositories.user_repository import UserRepository
from app.routers.reports import create_report_router
from app.services.auth_service import AuthService


class SyntheticProvider:
    def __init__(self, subject):
        self.subject = subject

    async def verify_access_token(self, token):
        if token != 'valid-supabase-token':
            raise InvalidIdentityToken('rejected')
        return IdentityClaims(subject=self.subject)


class AiSupabaseAuthBridgeTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine(
            'sqlite+pysqlite:///:memory:',
            connect_args={'check_same_thread': False},
            poolclass=StaticPool,
        )
        models.Base.metadata.create_all(self.engine)
        with self.engine.begin() as connection:
            connection.execute(text('ALTER TABLE users ADD COLUMN supabase_user_id TEXT'))
            connection.execute(text('ALTER TABLE users ADD COLUMN approved_at TIMESTAMP'))
        self.sessions = sessionmaker(bind=self.engine)
        self.subject = uuid4()
        self.received = []
        self.received_humanize = []

    def tearDown(self):
        self.engine.dispose()

    def get_db(self):
        db = self.sessions()
        try:
            yield db
        finally:
            db.close()

    def add_user(self, role='doctor', active=True, approved=True, specialization=None):
        db = self.sessions()
        try:
            user = models.User(
                id=str(uuid4()), username=f'{role}-{uuid4()}',
                email=f'{uuid4()}@clinic.invalid', hashed_password='unused',
                full_name='AI Clinician', role=role, is_active=active,
                specialization=specialization,
            )
            db.add(user)
            db.commit()
            approved_sql = ', approved_at = CURRENT_TIMESTAMP' if approved else ''
            db.execute(text(
                f'UPDATE users SET supabase_user_id=:subject{approved_sql} WHERE id=:id'
            ), {'subject': str(self.subject), 'id': user.id})
            db.commit()
        finally:
            db.close()

    def client(self):
        dependencies = AuthDependencies(
            mode='supabase', get_db_dependency=self.get_db,
            token_dependency=OAuth2PasswordBearer(tokenUrl='unused'),
            auth_service=AuthService(),
            identity_provider=SyntheticProvider(self.subject),
            user_resolver=ApplicationUserResolver(UserRepository()),
        )

        async def report_ai(payload):
            self.received.append(payload)
            return '# Clinical Dental Report'

        async def humanize_ai(report, patient_name):
            self.received_humanize.append((report, patient_name))
            return 'Patient-friendly derivative'

        app = FastAPI()
        app.include_router(create_report_router(
            get_db_dependency=self.get_db,
            auth_dependency=dependencies.get_current_user,
            doctor_dependency=dependencies.require_role('doctor'),
            pdf_generator=lambda *_: None,
            report_ai=report_ai,
            humanize_ai=humanize_ai,
            audit_logger=lambda *_args, **_kwargs: None,
            logger=None,
        ))
        return TestClient(app)

    def post(self, token='valid-supabase-token', payload=None):
        headers = {'Authorization': f'Bearer {token}'} if token is not None else {}
        return self.client().post('/api/ai/generate-report', headers=headers, json=payload or {'selectedTooth': '11'})

    def test_valid_doctor_and_admin_use_authoritative_identity_and_preserve_clinical_payload(self):
        payload = {
            'selectedTooth': '11', 'symptoms': ['Pain'], 'doctorNotes': 'Keep exact',
            'doctor': {'name': 'Browser Impostor', 'specialty': 'Browser Specialty'},
        }
        self.add_user('doctor')
        response = self.post(payload=payload)
        self.assertEqual(200, response.status_code)
        self.assertEqual('# Clinical Dental Report', response.json()['report'])
        self.assertEqual('AI Clinician', self.received[-1]['doctor']['name'])
        self.assertIsNone(self.received[-1]['doctor']['specialty'])
        self.assertRegex(self.received[-1]['reportDate'], r'^\d{4}-\d{2}-\d{2}$')
        self.assertEqual('Keep exact', self.received[-1]['doctorNotes'])
        with self.engine.begin() as connection:
            connection.execute(text('DELETE FROM users'))
        self.add_user('admin')
        self.assertEqual(200, self.post(payload=payload).status_code)
        self.assertEqual('AI Clinician', self.received[-1]['doctor']['name'])

    def test_receptionist_is_rejected(self):
        self.add_user('receptionist')
        self.assertEqual(403, self.post().status_code)

    def test_authenticated_specialization_replaces_browser_value(self):
        self.add_user('doctor', specialization='Orthodontics')
        response = self.post(payload={'doctor': {
            'name': 'Browser Name', 'specialty': 'Browser Specialty',
        }})
        self.assertEqual(200, response.status_code)
        self.assertEqual({
            'name': 'AI Clinician', 'specialty': 'Orthodontics',
        }, self.received[-1]['doctor'])

    def test_inactive_and_unapproved_are_rejected(self):
        self.add_user('doctor', active=False)
        self.assertEqual(401, self.post().status_code)
        with self.engine.begin() as connection:
            connection.execute(text('DELETE FROM users'))
        self.add_user('doctor', approved=False)
        self.assertEqual(401, self.post().status_code)

    def test_missing_and_legacy_malformed_tokens_are_rejected(self):
        self.add_user('doctor')
        self.assertEqual(401, self.post(token=None).status_code)
        self.assertEqual(401, self.post(token='legacy-or-malformed').status_code)

    def test_humanize_uses_same_doctor_auth_bridge_and_preserves_current_text(self):
        self.add_user('doctor')
        response = self.client().post(
            '/api/ai/humanize-report',
            headers={'Authorization': 'Bearer valid-supabase-token'},
            json={'report': 'Current manually edited report', 'patient_name': 'Ada'},
        )
        self.assertEqual(200, response.status_code)
        self.assertEqual('Patient-friendly derivative', response.json()['humanized_report'])
        self.assertEqual(
            [('Current manually edited report', 'Ada')],
            self.received_humanize,
        )

    def test_humanize_rejects_receptionist_and_missing_token(self):
        self.add_user('receptionist')
        payload = {'report': 'Current report', 'patient_name': 'Ada'}
        self.assertEqual(403, self.client().post(
            '/api/ai/humanize-report',
            headers={'Authorization': 'Bearer valid-supabase-token'}, json=payload,
        ).status_code)
        self.assertEqual(401, self.client().post(
            '/api/ai/humanize-report', json=payload,
        ).status_code)


if __name__ == '__main__':
    unittest.main()
