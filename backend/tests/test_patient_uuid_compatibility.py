from __future__ import annotations

import unittest

from sqlalchemy import Uuid
from sqlalchemy.dialects import postgresql
from sqlalchemy.schema import CreateTable

from tests.support import models


class PatientUuidCompatibilityTests(unittest.TestCase):
    def test_patient_id_compiles_as_server_generated_postgresql_uuid(self):
        patient_id = models.Patient.__table__.c.id
        self.assertIsInstance(patient_id.type, Uuid)
        self.assertFalse(patient_id.type.as_uuid)
        self.assertIsNone(patient_id.default)
        self.assertIsNotNone(patient_id.server_default)

        ddl = str(CreateTable(models.Patient.__table__).compile(dialect=postgresql.dialect())).upper()
        self.assertIn("ID UUID DEFAULT GEN_RANDOM_UUID() NOT NULL", ddl)
        self.assertNotIn("ID VARCHAR", ddl)

    def test_all_root_patient_foreign_keys_match_patient_uuid_type(self):
        patient_id = models.Patient.__table__.c.id
        referencing_columns = (
            models.Appointment.__table__.c.patient_id,
            models.Consultation.__table__.c.patient_id,
            models.ClinicalReport.__table__.c.patient_id,
            models.Record.__table__.c.patient_id,
            models.PatientDentalState.__table__.c.patient_id,
            models.Log.__table__.c.patient_id,
        )
        for column in referencing_columns:
            self.assertIsInstance(column.type, Uuid, column)
            self.assertFalse(column.type.as_uuid, column)
            self.assertEqual(type(patient_id.type), type(column.type), column)
            self.assertEqual("patients.id", next(iter(column.foreign_keys)).target_fullname)


if __name__ == "__main__":
    unittest.main()
