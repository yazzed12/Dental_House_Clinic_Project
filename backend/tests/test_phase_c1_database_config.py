from __future__ import annotations

import ast
import os
from pathlib import Path
import subprocess
import sys
import unittest

from app.core.database_config import load_database_config


BACKEND_DIR = Path(__file__).resolve().parents[1]


class PhaseC1DatabaseConfigTests(unittest.TestCase):
    def test_production_without_database_url_fails(self):
        with self.assertRaisesRegex(RuntimeError, "DATABASE_URL must be explicitly"):
            load_database_config({"ENVIRONMENT": "production"})

    def test_production_with_sqlite_fails(self):
        with self.assertRaisesRegex(RuntimeError, "PostgreSQL is required"):
            load_database_config(
                {"ENVIRONMENT": "production", "DATABASE_URL": "sqlite:///clinic.db"}
            )

    def test_require_postgres_without_database_url_fails(self):
        with self.assertRaisesRegex(RuntimeError, "DATABASE_URL must be explicitly"):
            load_database_config({"ENVIRONMENT": "development", "REQUIRE_POSTGRES": "true"})

    def test_require_postgres_with_sqlite_fails(self):
        with self.assertRaisesRegex(RuntimeError, "PostgreSQL is required"):
            load_database_config(
                {
                    "ENVIRONMENT": "development",
                    "REQUIRE_POSTGRES": "true",
                    "DATABASE_URL": "sqlite+pysqlite:///:memory:",
                }
            )

    def test_development_with_explicit_sqlite_is_allowed(self):
        config = load_database_config(
            {
                "ENVIRONMENT": "development",
                "DATABASE_URL": "sqlite:///clinic.db",
            }
        )
        self.assertEqual("sqlite", config.dialect)
        self.assertFalse(config.require_postgres)

    def test_test_environment_with_isolated_sqlite_is_allowed(self):
        config = load_database_config(
            {
                "ENVIRONMENT": "test",
                "DATABASE_URL": "sqlite+pysqlite:///:memory:",
            }
        )
        self.assertEqual("sqlite", config.dialect)

    def test_production_with_postgresql_is_allowed(self):
        config = load_database_config(
            {
                "ENVIRONMENT": "production",
                "DATABASE_URL": "postgresql://db-user:secret@db.invalid/clinic",
            }
        )
        self.assertEqual("postgresql", config.dialect)
        self.assertTrue(config.require_postgres)
        self.assertNotIn("secret", config.safe_summary)

    def test_known_legacy_postgres_scheme_is_normalized(self):
        config = load_database_config(
            {
                "ENVIRONMENT": "production",
                "DATABASE_URL": "postgres://db-user:secret@db.invalid/clinic",
            }
        )
        self.assertTrue(config.url.startswith("postgresql://"))

    def test_sqlite_requires_explicit_local_or_test_environment(self):
        with self.assertRaisesRegex(RuntimeError, "explicitly development, local, or test"):
            load_database_config({"DATABASE_URL": "sqlite:///clinic.db"})

    def test_production_cannot_enable_schema_bootstrap(self):
        with self.assertRaisesRegex(RuntimeError, "cannot be enabled in production"):
            load_database_config(
                {
                    "ENVIRONMENT": "production",
                    "DATABASE_URL": "postgresql://db-user:secret@db.invalid/clinic",
                    "ALLOW_SCHEMA_BOOTSTRAP": "true",
                }
            )

    def test_valid_production_import_smoke_does_not_connect_or_create_schema(self):
        environment = os.environ.copy()
        environment.update(
            {
                "ENVIRONMENT": "production",
                "REQUIRE_POSTGRES": "true",
                "DATABASE_URL": "postgresql://db-user:secret@127.0.0.1:1/clinic",
                "ALLOW_SCHEMA_BOOTSTRAP": "false",
            }
        )
        completed = subprocess.run(
            [
                sys.executable,
                "-c",
                "import main; print(main.DATABASE_CONFIG.safe_summary)",
            ],
            cwd=BACKEND_DIR,
            env=environment,
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        self.assertEqual(0, completed.returncode, completed.stderr)
        self.assertIn("dialect=postgresql", completed.stdout)
        self.assertNotIn("secret", completed.stdout + completed.stderr)

    def test_main_ast_has_no_unconditional_create_all_call(self):
        tree = ast.parse((BACKEND_DIR / "main.py").read_text(encoding="utf-8"))
        module_level_create_all = []
        for statement in tree.body:
            if isinstance(statement, ast.Expr) and isinstance(statement.value, ast.Call):
                call = statement.value.func
                if isinstance(call, ast.Attribute) and call.attr == "create_all":
                    module_level_create_all.append(statement.lineno)
        self.assertEqual([], module_level_create_all)


if __name__ == "__main__":
    unittest.main()
