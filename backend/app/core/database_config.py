from __future__ import annotations

from dataclasses import dataclass
import os
from collections.abc import Mapping

from sqlalchemy.engine import make_url
from sqlalchemy.exc import ArgumentError


_SQLITE_ENVIRONMENTS = frozenset({"development", "local", "test"})
_TRUE_VALUES = frozenset({"1", "true", "yes", "on"})
_FALSE_VALUES = frozenset({"0", "false", "no", "off", ""})


def _read_bool(name: str, raw_value: str | None, *, default: bool = False) -> bool:
    if raw_value is None:
        return default
    value = raw_value.strip().lower()
    if value in _TRUE_VALUES:
        return True
    if value in _FALSE_VALUES:
        return False
    raise RuntimeError(f"{name} must be true or false")


@dataclass(frozen=True)
class DatabaseConfig:
    url: str
    dialect: str
    environment: str
    require_postgres: bool
    allow_schema_bootstrap: bool

    @property
    def safe_summary(self) -> str:
        return (
            f"dialect={self.dialect} environment={self.environment} "
            f"postgres_required={str(self.require_postgres).lower()}"
        )


def load_database_config(
    environ: Mapping[str, str] | None = None,
) -> DatabaseConfig:
    values = os.environ if environ is None else environ
    environment = values.get("ENVIRONMENT", "").strip().lower() or "unspecified"
    require_postgres = _read_bool(
        "REQUIRE_POSTGRES", values.get("REQUIRE_POSTGRES"), default=False
    )
    allow_schema_bootstrap = _read_bool(
        "ALLOW_SCHEMA_BOOTSTRAP",
        values.get("ALLOW_SCHEMA_BOOTSTRAP"),
        default=False,
    )
    raw_url = values.get("DATABASE_URL", "").strip()
    postgres_required = environment == "production" or require_postgres

    if not raw_url:
        raise RuntimeError(
            "DATABASE_URL must be explicitly configured; automatic SQLite fallback is disabled"
        )

    normalized_url = (
        f"postgresql://{raw_url[len('postgres://') :]}"
        if raw_url.startswith("postgres://")
        else raw_url
    )
    try:
        parsed = make_url(normalized_url)
    except ArgumentError as error:
        raise RuntimeError("DATABASE_URL is not a valid SQLAlchemy database URL") from error

    backend = parsed.get_backend_name()
    if backend == "postgresql":
        dialect = "postgresql"
    elif backend == "sqlite":
        dialect = "sqlite"
    else:
        raise RuntimeError("DATABASE_URL must use PostgreSQL or explicit local/test SQLite")

    if postgres_required and dialect != "postgresql":
        raise RuntimeError(
            "PostgreSQL is required for this environment; SQLite startup is refused"
        )
    if dialect == "sqlite" and environment not in _SQLITE_ENVIRONMENTS:
        raise RuntimeError(
            "SQLite is allowed only when ENVIRONMENT is explicitly development, local, or test"
        )
    if environment == "production" and allow_schema_bootstrap:
        raise RuntimeError("ALLOW_SCHEMA_BOOTSTRAP cannot be enabled in production")

    return DatabaseConfig(
        url=normalized_url,
        dialect=dialect,
        environment=environment,
        require_postgres=postgres_required,
        allow_schema_bootstrap=allow_schema_bootstrap,
    )
