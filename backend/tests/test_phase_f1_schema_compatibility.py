from __future__ import annotations

import unittest
from types import SimpleNamespace
from unittest.mock import patch

from sqlalchemy import DateTime, Uuid
from sqlalchemy.dialects import postgresql
from sqlalchemy.schema import CreateTable
from fastapi import HTTPException

from app.services.finance_service import FinanceService
from tests.support import active_main, models


class PhaseF1SchemaCompatibilityTests(unittest.TestCase):
    def test_active_catalog_filter_compiles_as_postgresql_boolean(self):
        from app.repositories.finance_repository import FinanceRepository
        from unittest.mock import Mock

        query = Mock()
        query.filter.return_value = query
        query.order_by.return_value.all.return_value = []
        db = Mock()
        db.query.return_value = query

        FinanceRepository().list_procedures(db, active_only=True)
        predicate = query.filter.call_args.args[0]
        compiled = str(predicate.compile(dialect=postgresql.dialect())).lower()
        self.assertIn("is true", compiled)
        self.assertNotIn("!= 0", compiled)

    def test_financial_foreign_key_types_match_native_uuid_targets(self):
        consultation_id = models.Consultation.__table__.c.id.type
        catalog_id = models.ClinicProcedure.__table__.c.id.type
        selection = models.ConsultationProcedure.__table__.c

        for identifier_type in (
            consultation_id,
            catalog_id,
            selection.id.type,
            selection.consultation_id.type,
            selection.procedure_id.type,
        ):
            self.assertIsInstance(identifier_type, Uuid)
            self.assertFalse(identifier_type.as_uuid)

        self.assertEqual(type(consultation_id), type(selection.consultation_id.type))
        self.assertEqual(type(catalog_id), type(selection.procedure_id.type))

    def test_postgresql_ddl_uses_uuid_and_timezone_aware_timestamps(self):
        dialect = postgresql.dialect()
        catalog_ddl = str(
            CreateTable(models.ClinicProcedure.__table__).compile(dialect=dialect)
        ).upper()
        selection_ddl = str(
            CreateTable(models.ConsultationProcedure.__table__).compile(
                dialect=dialect
            )
        ).upper()

        self.assertIn("ID UUID NOT NULL", catalog_ddl)
        self.assertIn("ID UUID NOT NULL", selection_ddl)
        self.assertIn("CONSULTATION_ID UUID NOT NULL", selection_ddl)
        self.assertIn("PROCEDURE_ID UUID NOT NULL", selection_ddl)
        self.assertNotIn("CONSULTATION_ID VARCHAR", selection_ddl)
        self.assertNotIn("PROCEDURE_ID VARCHAR", selection_ddl)
        self.assertIn("TIMESTAMP WITH TIME ZONE", catalog_ddl)
        self.assertIn("TIMESTAMP WITH TIME ZONE", selection_ddl)

        for column in (
            models.ClinicProcedure.__table__.c.created_at,
            models.ClinicProcedure.__table__.c.updated_at,
            models.ConsultationProcedure.__table__.c.created_at,
        ):
            self.assertIsInstance(column.type, DateTime)
            self.assertTrue(column.type.timezone)

    def test_postgresql_startup_never_runs_create_all(self):
        fake_postgres = SimpleNamespace(
            dialect=SimpleNamespace(name="postgresql")
        )
        with patch.object(active_main.Base.metadata, "create_all") as create_all:
            created = active_main.create_runtime_schema(
                fake_postgres, allow_schema_bootstrap=True
            )

        self.assertFalse(created)
        create_all.assert_not_called()

    def test_phase_f3_f5_ledger_ddl_uses_uuid_numeric_and_timestamptz(self):
        dialect = postgresql.dialect()
        record = models.FinancialPaymentRecord.__table__.c
        allocation = models.FinancialPaymentAllocation.__table__.c
        adjustment = models.FinancialChargeAdjustment.__table__.c
        for column in (record.id, record.payment_id, record.consultation_id, record.created_by, allocation.id, allocation.payment_record_id, allocation.consultation_procedure_id, adjustment.id, adjustment.consultation_procedure_id, adjustment.created_by):
            self.assertIsInstance(column.type, Uuid)
            self.assertFalse(column.type.as_uuid)
        for table in (models.FinancialPaymentRecord.__table__, models.FinancialPaymentAllocation.__table__, models.FinancialChargeAdjustment.__table__):
            ddl = str(CreateTable(table).compile(dialect=dialect)).upper()
            self.assertIn("UUID", ddl)
            self.assertIn("TIMESTAMP WITH TIME ZONE", ddl)
            self.assertNotIn(" DOUBLE ", ddl)
            self.assertNotIn(" FLOAT", ddl)

    def test_explicit_non_postgresql_bootstrap_preserves_test_schema_creation(self):
        fake_sqlite = SimpleNamespace(dialect=SimpleNamespace(name="sqlite"))
        with patch.object(active_main.Base.metadata, "create_all") as create_all:
            created = active_main.create_runtime_schema(
                fake_sqlite, allow_schema_bootstrap=True
            )

        self.assertTrue(created)
        create_all.assert_called_once_with(bind=fake_sqlite)

    def test_non_postgresql_startup_does_not_bootstrap_by_default(self):
        fake_sqlite = SimpleNamespace(dialect=SimpleNamespace(name="sqlite"))
        with patch.object(active_main.Base.metadata, "create_all") as create_all:
            created = active_main.create_runtime_schema(
                fake_sqlite, allow_schema_bootstrap=False
            )

        self.assertFalse(created)
        create_all.assert_not_called()

    def test_missing_migration_disables_f1_with_clear_service_error(self):
        repository = SimpleNamespace(schema_available=lambda _db: False)
        service = FinanceService(repository=repository)

        with self.assertRaises(HTTPException) as raised:
            service.ensure_schema(SimpleNamespace())

        self.assertEqual(503, raised.exception.status_code)
        self.assertIn("Apply migration 003", raised.exception.detail)


if __name__ == "__main__":
    unittest.main()
