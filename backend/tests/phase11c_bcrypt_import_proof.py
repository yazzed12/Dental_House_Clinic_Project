"""Disposable, localhost-only proof for importing Passlib bcrypt into Supabase Auth."""

from __future__ import annotations

import os
import secrets
from dataclasses import dataclass
from urllib.parse import urlparse

import httpx
from passlib.context import CryptContext


@dataclass(frozen=True)
class ProofResult:
    imported: bool
    correct_password_accepted: bool
    incorrect_password_rejected: bool
    duplicate_email_rejected: bool
    identity_deleted: bool
    deletion_verified: bool


def _require_local_url(url: str) -> str:
    normalized = url.rstrip("/")
    parsed = urlparse(normalized)
    if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost"}:
        raise RuntimeError("Phase 11C proof is restricted to local HTTP Supabase instances")
    return normalized


def run_proof() -> ProofResult:
    api_url = _require_local_url(os.environ.get("PHASE11C_SUPABASE_URL", ""))
    secret_key = os.environ.get("PHASE11C_SUPABASE_SECRET_KEY", "")
    publishable_key = os.environ.get("PHASE11C_SUPABASE_PUBLISHABLE_KEY", "")
    if not secret_key or not publishable_key:
        raise RuntimeError("Disposable Supabase keys are required")

    password = f"Synthetic-{secrets.token_urlsafe(24)}-9A!"
    wrong_password = f"Wrong-{secrets.token_urlsafe(24)}-8B!"
    email = f"phase11c-{secrets.token_hex(12)}@example.invalid"
    password_hash = CryptContext(schemes=["bcrypt"], deprecated="auto").hash(password)
    if not password_hash.startswith("$2b$"):
        raise RuntimeError("Synthetic Passlib hash did not use the expected bcrypt format")
    admin_headers = {
        "apikey": secret_key,
        "Authorization": f"Bearer {secret_key}",
        "Content-Type": "application/json",
    }
    public_headers = {
        "apikey": publishable_key,
        "Content-Type": "application/json",
    }

    user_id: str | None = None
    imported = False
    correct_accepted = False
    incorrect_rejected = False
    duplicate_rejected = False
    deleted = False
    deletion_verified = False
    with httpx.Client(timeout=10.0) as client:
        try:
            created = client.post(
                f"{api_url}/auth/v1/admin/users",
                headers=admin_headers,
                json={
                    "email": email,
                    "password_hash": password_hash,
                    "email_confirm": True,
                },
            )
            created.raise_for_status()
            user_id = created.json().get("id")
            if not user_id:
                raise RuntimeError("Supabase did not return an imported user ID")
            imported = True

            duplicate = client.post(
                f"{api_url}/auth/v1/admin/users",
                headers=admin_headers,
                json={
                    "email": email,
                    "password_hash": password_hash,
                    "email_confirm": True,
                },
            )
            duplicate_rejected = duplicate.status_code in {400, 409, 422}

            correct = client.post(
                f"{api_url}/auth/v1/token?grant_type=password",
                headers=public_headers,
                json={"email": email, "password": password},
            )
            correct_accepted = correct.status_code == 200 and bool(
                correct.json().get("access_token")
            )

            incorrect = client.post(
                f"{api_url}/auth/v1/token?grant_type=password",
                headers=public_headers,
                json={"email": email, "password": wrong_password},
            )
            incorrect_rejected = incorrect.status_code in {400, 401}
        finally:
            if user_id:
                response = client.delete(
                    f"{api_url}/auth/v1/admin/users/{user_id}", headers=admin_headers
                )
                deleted = response.status_code in {200, 204}
                absent = client.get(
                    f"{api_url}/auth/v1/admin/users/{user_id}", headers=admin_headers
                )
                deletion_verified = absent.status_code == 404

    return ProofResult(
        imported=imported,
        correct_password_accepted=correct_accepted,
        incorrect_password_rejected=incorrect_rejected,
        duplicate_email_rejected=duplicate_rejected,
        identity_deleted=deleted,
        deletion_verified=deletion_verified,
    )


if __name__ == "__main__":
    result = run_proof()
    if not all(result.__dict__.values()):
        raise SystemExit("Phase 11C bcrypt import proof failed")
    print("Phase 11C bcrypt import proof passed; synthetic identity deleted.")
