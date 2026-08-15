from __future__ import annotations

import ast
import importlib
import unittest
from pathlib import Path

from sqlalchemy import Boolean, DateTime, Numeric, Uuid
from sqlalchemy.dialects import postgresql
from sqlalchemy.schema import CreateTable

from tests.support import TEST_ENGINE, active_main, models


BACKEND_DIR = Path(__file__).resolve().parents[1]


class ModelSessionConsolidationTests(unittest.TestCase):
    def test_compatibility_paths_share_authoritative_identities(self):
        active_database = importlib.import_module("database")
        compatibility_session = importlib.import_module("app.database.session")
        compatibility_models = importlib.import_module("app.models")

        self.assertIs(active_database.Base, compatibility_session.Base)
        self.assertIs(active_database.engine, compatibility_session.engine)
        self.assertIs(active_database.SessionLocal, compatibility_session.SessionLocal)
        self.assertIs(active_database.get_db, compatibility_session.get_db)
        self.assertIs(models.User, compatibility_models.User)
        self.assertIs(models.Patient, compatibility_models.Patient)
        self.assertIs(models.Consultation, compatibility_models.Consultation)
        self.assertIs(models.ClinicProcedure, compatibility_models.ClinicProcedure)
        self.assertIs(models.FinancialPaymentRecord, compatibility_models.FinancialPaymentRecord)

    def test_individual_compatibility_model_modules_are_aliases(self):
        aliases = {
            "app.models.user": ("User", models.User),
            "app.models.patient": ("Patient", models.Patient),
            "app.models.appointment": ("Appointment", models.Appointment),
            "app.models.consultation": ("Consultation", models.Consultation),
            "app.models.report": ("ClinicalReport", models.ClinicalReport),
        }
        for module_name, (attribute, authoritative_model) in aliases.items():
            module = importlib.import_module(module_name)
            self.assertIs(authoritative_model, getattr(module, attribute))

    def test_modular_compatibility_tree_defines_no_engine_base_or_tables(self):
        files = [BACKEND_DIR / "app/database/session.py", *(BACKEND_DIR / "app/models").glob("*.py")]
        for path in files:
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            calls = {
                node.func.id
                for node in ast.walk(tree)
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
            }
            self.assertNotIn("create_engine", calls, path)
            self.assertNotIn("declarative_base", calls, path)
            self.assertNotIn("sessionmaker", calls, path)
            self.assertFalse(
                any(isinstance(node, ast.ClassDef) for node in ast.walk(tree)),
                path,
            )

    def test_active_runtime_has_no_stale_modular_model_or_session_imports(self):
        active_roots = [BACKEND_DIR / "main.py", BACKEND_DIR / "app"]
        stale_imports = []
        for root in active_roots:
            paths = [root] if root.is_file() else root.rglob("*.py")
            for path in paths:
                if path.parts[-2:] == ("database", "session.py") or "models" in path.parts:
                    continue
                source = path.read_text(encoding="utf-8")
                if "app.database.session" in source or "app.models" in source:
                    stale_imports.append(str(path.relative_to(BACKEND_DIR)))
        self.assertEqual([], stale_imports)

    def test_test_engine_binds_the_authoritative_metadata(self):
        self.assertIs(active_main.Base, models.Base)
        models.Base.metadata.create_all(bind=TEST_ENGINE)
        self.assertIn("patients", models.Base.metadata.tables)
        self.assertIn("financial_payment_records", models.Base.metadata.tables)

    def test_postgresql_identity_boolean_timestamp_and_money_types_compile(self):
        uuid_columns = (
            models.User.__table__.c.id,
            models.Patient.__table__.c.id,
            models.Appointment.__table__.c.id,
            models.Consultation.__table__.c.id,
            models.Consultation.__table__.c.doctor_id,
            models.Consultation.__table__.c.appointment_id,
        )
        for column in uuid_columns:
            self.assertIsInstance(column.type, Uuid, column)
            self.assertFalse(column.type.as_uuid, column)

        self.assertIsInstance(models.ClinicProcedure.__table__.c.is_active.type, Boolean)
        self.assertIsInstance(models.ClinicProcedure.__table__.c.created_at.type, DateTime)
        self.assertTrue(models.ClinicProcedure.__table__.c.created_at.type.timezone)
        self.assertTrue(models.Consultation.__table__.c.created_at.type.timezone)
        self.assertTrue(models.PatientDentalState.__table__.c.updated_at.type.timezone)
        self.assertIsInstance(models.ClinicProcedure.__table__.c.price.type, Numeric)

        ddl = "\n".join(
            str(CreateTable(model.__table__).compile(dialect=postgresql.dialect())).upper()
            for model in (
                models.User,
                models.Appointment,
                models.ClinicProcedure,
                models.FinancialPaymentRecord,
            )
        )
        self.assertIn(" UUID", ddl)
        self.assertIn(" BOOLEAN", ddl)
        self.assertIn("TIMESTAMP WITH TIME ZONE", ddl)
        self.assertIn("NUMERIC(15, 2)", ddl)


if __name__ == "__main__":
    unittest.main()
