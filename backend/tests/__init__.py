"""Characterization tests for the currently active monolithic FastAPI runtime."""
"""Test package bootstrap: always isolate imports from production databases."""

import os


os.environ["ENVIRONMENT"] = "test"
os.environ["REQUIRE_POSTGRES"] = "false"
os.environ["DATABASE_URL"] = "sqlite+pysqlite:///:memory:"
os.environ["ALLOW_SCHEMA_BOOTSTRAP"] = "false"
os.environ.setdefault("SECRET_KEY", "characterization-tests-only-secret")
