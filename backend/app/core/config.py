from __future__ import annotations

import os
from dataclasses import dataclass
from urllib.parse import urlparse
from dotenv import load_dotenv

load_dotenv()

# Project Info
PROJECT_NAME = "Smart Dental Clinic Enterprise API"

# Security & JWT Configuration
SECRET_KEY = os.getenv("SECRET_KEY", "enterprise_secret_key_change_in_production")
ALGORITHM = os.getenv("ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "480"))

# CORS Configuration
CORS_ORIGINS = [
    "http://localhost:5173",
    "http://127.0.0.1:5173",
    "http://localhost:5174",
    "http://127.0.0.1:5174",
    "http://localhost:3000",
]

# AI Model Configuration
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.2:3b")
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")

VALID_AUTH_MODES = frozenset({"legacy", "supabase"})


def get_auth_mode(value: str | None = None) -> str:
    """Return the one explicitly selected authentication authority."""

    mode = (value if value is not None else os.getenv("AUTH_MODE", "legacy")).strip().lower()
    if mode not in VALID_AUTH_MODES:
        choices = ", ".join(sorted(VALID_AUTH_MODES))
        raise RuntimeError(f"Invalid AUTH_MODE '{mode}'. Expected one of: {choices}")
    return mode


@dataclass(frozen=True)
class SupabaseAuthSettings:
    """Inactive Phase 11B configuration for the future Supabase Auth provider."""

    url: str
    issuer: str
    jwks_url: str
    audience: str | None = "authenticated"
    allowed_algorithms: tuple[str, ...] = ("RS256",)

    @classmethod
    def from_env(cls) -> "SupabaseAuthSettings":
        url = os.getenv("SUPABASE_URL", "").rstrip("/")
        issuer = os.getenv("SUPABASE_JWT_ISSUER", f"{url}/auth/v1" if url else "")
        jwks_url = os.getenv(
            "SUPABASE_JWKS_URL",
            f"{issuer.rstrip('/')}/.well-known/jwks.json" if issuer else "",
        )
        audience = os.getenv("SUPABASE_JWT_AUDIENCE", "authenticated") or None
        algorithms = tuple(
            item.strip()
            for item in os.getenv("SUPABASE_JWT_ALGORITHMS", "RS256").split(",")
            if item.strip()
        )
        return cls(url, issuer, jwks_url, audience, algorithms)

    def validate(self) -> None:
        missing = [
            name
            for name, value in (
                ("SUPABASE_URL", self.url),
                ("SUPABASE_JWT_ISSUER", self.issuer),
                ("SUPABASE_JWKS_URL", self.jwks_url),
            )
            if not value
        ]
        if missing:
            raise ValueError(f"Missing Supabase Auth configuration: {', '.join(missing)}")
        for name, value in (
            ("SUPABASE_URL", self.url),
            ("SUPABASE_JWT_ISSUER", self.issuer),
            ("SUPABASE_JWKS_URL", self.jwks_url),
        ):
            parsed = urlparse(value)
            if parsed.scheme not in {"http", "https"} or not parsed.netloc:
                raise ValueError(f"{name} must be an absolute HTTP(S) URL")
        if not self.allowed_algorithms or any(
            algorithm not in {"RS256", "ES256"} for algorithm in self.allowed_algorithms
        ):
            raise ValueError("Supabase JWT algorithms must be restricted to RS256 and/or ES256")
