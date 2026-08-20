from __future__ import annotations

import importlib
import unittest
from collections import Counter

from fastapi.testclient import TestClient

import database as active_database
import models as active_models
from app.repositories import (
    appointment_repository,
    clinic_settings_repository,
    common_repository,
    consultation_repository,
    medication_repository,
    notification_repository,
    patient_repository,
    report_repository,
    symptom_repository,
    user_repository,
)
from tests.route_inventory import _application_routes
from tests.support import (
    TestingSessionLocal,
    active_main,
    add_user,
    bearer_token,
    models,
    reset_database,
)


class Phase3ModularRouteTests(unittest.TestCase):
    def setUp(self):
        reset_database()
        self.client = TestClient(active_main.app)
        add_user(user_id="doctor-1", email="doctor@example.test", role="doctor")
        self.headers = bearer_token("doctor@example.test")

    def test_only_approved_handlers_are_modular(self):
        expected_modules = {
            ("GET", "/api/auth/me"): "app.routers.auth",
            ("GET", "/dashboard"): "app.routers.common",
            ("GET", "/api/dashboard"): "app.routers.common",
            ("GET", "/logs"): "app.routers.common",
            ("GET", "/api/records"): "app.routers.common",
            ("GET", "/api/appointment-conditions"): "app.routers.common",
            ("POST", "/api/appointment-conditions"): "app.routers.common",
            ("GET", "/api/ai/insights"): "app.routers.common",
            ("POST", "/api/ai/diagnosis"): "app.routers.common",
            ("POST", "/api/ai/chat"): "app.routers.common",
            ("GET", "/"): "app.routers.common",
            ("GET", "/api/notifications"): "app.routers.notifications",
            ("PATCH", "/api/notifications/{notification_id}/read"): "app.routers.notifications",
            ("GET", "/api/clinical/symptoms"): "app.routers.symptoms",
            ("POST", "/api/clinical/symptoms"): "app.routers.symptoms",
            ("GET", "/api/patients"): "app.routers.patients",
            ("POST", "/api/patients"): "app.routers.patients",
            ("PUT", "/api/patients/{patient_id}"): "app.routers.patients",
            ("GET", "/api/patients/{patient_id}"): "app.routers.patients",
            ("DELETE", "/api/patients/{patient_id}"): "app.routers.patients",
            ("GET", "/appointments/today"): "app.routers.appointments",
            ("GET", "/api/appointments"): "app.routers.appointments",
            ("POST", "/api/appointments"): "app.routers.appointments",
            ("PUT", "/api/appointments/{appointment_id}/status"): "app.routers.appointments",
            ("PUT", "/api/appointments/{appointment_id}"): "app.routers.appointments",
            ("DELETE", "/api/appointments/{appointment_id}"): "app.routers.appointments",
            ("POST", "/api/appointments/finish-by-patient/{patient_id}"): "app.routers.appointments",
            ("PUT", "/appointments/{appointment_id}/finish"): "app.routers.appointments",
            ("GET", "/api/settings/clinic"): "app.routers.clinic_settings",
            ("PUT", "/api/settings/clinic"): "app.routers.clinic_settings",
            ("GET", "/api/settings/profile"): "app.routers.clinic_settings",
            ("PUT", "/api/settings/profile"): "app.routers.clinic_settings",
            ("GET", "/api/doctors"): "app.routers.staff",
            ("GET", "/api/receptionists"): "app.routers.staff",
            ("POST", "/api/staff"): "app.routers.staff",
            ("PUT", "/api/staff/{user_id}"): "app.routers.staff",
            ("DELETE", "/api/staff/{user_id}"): "app.routers.staff",
            ("GET", "/api/clinic-procedures"): "app.routers.finance",
            ("POST", "/api/clinic-procedures"): "app.routers.finance",
            ("PATCH", "/api/clinic-procedures/{procedure_id}"): "app.routers.finance",
            ("GET", "/api/consultations/{patient_id}/procedures"): "app.routers.finance",
            ("PUT", "/api/consultations/{patient_id}/procedures"): "app.routers.finance",
            ("GET", "/api/finance/billing"): "app.routers.finance",
            ("GET", "/api/finance/patient-summaries"): "app.routers.finance",
            ("GET", "/api/finance/patients/{patient_id}/history"): "app.routers.finance",
            ("GET", "/api/finance/patients/{patient_id}/outstanding"): "app.routers.finance",
            ("POST", "/api/finance/consultations/{consultation_id}/payments"): "app.routers.finance",
            ("POST", "/api/finance/payments/{payment_id}/corrections"): "app.routers.finance",
            ("GET", "/api/consultations/{patient_id}"): "app.routers.consultations",
            ("POST", "/api/consultations/{patient_id}"): "app.routers.consultations",
            ("GET", "/api/consultations/{patient_id}/history"): "app.routers.consultations",
            ("GET", "/api/medications"): "app.routers.medications",
            ("POST", "/api/medications/custom"): "app.routers.medications",
            ("GET", "/api/medications/{medication_id}/effective-preset"): "app.routers.medications",
            ("GET", "/api/medications/{medication_id}"): "app.routers.medications",
            ("PUT", "/api/medications/{medication_id}/doctor-preset"): "app.routers.medications",
            ("DELETE", "/api/medications/{medication_id}/doctor-preset"): "app.routers.medications",
            ("GET", "/api/consultations/{consultation_id}/prescription"): "app.routers.medications",
            ("PUT", "/api/consultations/{consultation_id}/prescription/draft"): "app.routers.medications",
            ("POST", "/api/prescriptions/{prescription_id}/approve"): "app.routers.medications",
            ("POST", "/api/admin/medications/import"): "app.routers.medications",
            ("GET", "/api/doctor/consultations/history"): "app.routers.consultations",
            ("POST", "/api/ai/generate-report"): "app.routers.reports",
            ("POST", "/api/ai/humanize-report"): "app.routers.reports",
            ("POST", "/api/reports"): "app.routers.reports",
            ("GET", "/api/reports/patient/{patient_id}"): "app.routers.reports",
            ("GET", "/api/reports/{report_id}/download"): "app.routers.reports",
            ("PUT", "/api/reports/{report_id}"): "app.routers.reports",
        }
        matched = {}
        for route in _application_routes(active_main.app.routes):
            for method in route.methods or []:
                key = (method, route.path)
                if key in expected_modules:
                    matched[key] = route.endpoint.__module__
                else:
                    self.assertEqual("main", route.endpoint.__module__, key)
        self.assertEqual(expected_modules, matched)

    def test_active_repositories_share_the_monolithic_sqlalchemy_universe(self):
        self.assertIs(active_main.engine, active_database.engine)
        self.assertIs(active_main.Base, active_database.Base)
        self.assertIs(active_models.Notification.metadata, active_database.Base.metadata)
        self.assertIs(active_models.Symptom.metadata, active_database.Base.metadata)
        self.assertIs(active_models.Patient.metadata, active_database.Base.metadata)
        self.assertIs(active_models.Appointment.metadata, active_database.Base.metadata)
        self.assertIs(active_models.ClinicSettings.metadata, active_database.Base.metadata)
        self.assertIs(active_models.User.metadata, active_database.Base.metadata)
        self.assertIs(active_models.Consultation.metadata, active_database.Base.metadata)
        self.assertIs(active_models.ClinicalReport.metadata, active_database.Base.metadata)
        self.assertIs(active_models.Prescription.metadata, active_database.Base.metadata)
        self.assertIs(active_models.DentalMedication.metadata, active_database.Base.metadata)
        self.assertIs(notification_repository.models, active_models)
        self.assertIs(symptom_repository.models, active_models)
        self.assertIs(patient_repository.models, active_models)
        self.assertIs(appointment_repository.models, active_models)
        self.assertIs(clinic_settings_repository.models, active_models)
        self.assertIs(user_repository.models, active_models)
        self.assertIs(consultation_repository.models, active_models)
        self.assertIs(medication_repository.models, active_models)
        self.assertIs(report_repository.models, active_models)
        self.assertIs(common_repository.models, active_models)
        compatibility_session = importlib.import_module("app.database.session")
        compatibility_models = importlib.import_module("app.models")
        self.assertIs(compatibility_session.Base, active_database.Base)
        self.assertIs(compatibility_session.engine, active_database.engine)
        self.assertIs(compatibility_models.Patient, active_models.Patient)

    def test_no_method_and_path_pair_is_registered_twice(self):
        registrations = [
            (method, route.path)
            for route in _application_routes(active_main.app.routes)
            for method in route.methods or []
        ]
        duplicates = [key for key, count in Counter(registrations).items() if count > 1]
        self.assertEqual([], duplicates)

    def test_notification_list_and_read_contracts(self):
        db = TestingSessionLocal()
        try:
            db.add(
                models.Notification(
                    id="1",
                    title="Reminder",
                    body="Appointment soon",
                    type="info",
                    read=0,
                )
            )
            db.commit()
        finally:
            db.close()

        listed = self.client.get("/api/notifications", headers=self.headers)
        self.assertEqual(200, listed.status_code)
        self.assertEqual(
            {"id", "title", "body", "type", "read", "created_at"},
            set(listed.json()[0]),
        )
        self.assertIs(listed.json()[0]["read"], False)

        updated = self.client.patch("/api/notifications/1/read", headers=self.headers)
        self.assertEqual(200, updated.status_code)
        self.assertEqual({"status": "success"}, updated.json())

        relisted = self.client.get("/api/notifications", headers=self.headers)
        self.assertIs(relisted.json()[0]["read"], True)

        missing = self.client.patch("/api/notifications/999/read", headers=self.headers)
        self.assertEqual(404, missing.status_code)
        self.assertEqual("Notification not found", missing.json()["detail"])

    def test_symptom_list_create_duplicate_and_reactivation_contracts(self):
        listed = self.client.get("/api/clinical/symptoms", headers=self.headers)
        self.assertEqual(200, listed.status_code)
        self.assertEqual(14, len(listed.json()))
        self.assertEqual(
            {"id", "name", "created_by", "is_active", "created_at"},
            set(listed.json()[0]),
        )

        created = self.client.post(
            "/api/clinical/symptoms",
            json={"name": "  Custom Sensitivity  "},
            headers=self.headers,
        )
        self.assertEqual(200, created.status_code)
        self.assertEqual("Custom Sensitivity", created.json()["name"])
        self.assertEqual("doctor-1", created.json()["created_by"])
        self.assertEqual(1, created.json()["is_active"])

        duplicate = self.client.post(
            "/api/clinical/symptoms",
            json={"name": "custom sensitivity"},
            headers=self.headers,
        )
        self.assertEqual(200, duplicate.status_code)
        self.assertEqual(created.json(), duplicate.json())

        db = TestingSessionLocal()
        try:
            symptom = db.query(models.Symptom).filter(
                models.Symptom.id == created.json()["id"]
            ).one()
            symptom.is_active = 0
            db.commit()
        finally:
            db.close()

        reactivated = self.client.post(
            "/api/clinical/symptoms",
            json={"name": "CUSTOM SENSITIVITY"},
            headers=self.headers,
        )
        self.assertEqual(200, reactivated.status_code)
        self.assertEqual(created.json()["id"], reactivated.json()["id"])
        self.assertEqual("Custom Sensitivity", reactivated.json()["name"])
        self.assertEqual(1, reactivated.json()["is_active"])

        empty = self.client.post(
            "/api/clinical/symptoms", json={"name": "   "}, headers=self.headers
        )
        self.assertEqual(400, empty.status_code)
        self.assertEqual("Symptom name cannot be empty", empty.json()["detail"])


if __name__ == "__main__":
    unittest.main()
