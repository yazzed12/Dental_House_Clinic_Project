"""Pure, non-executing safeguards for later Auth and personal-email migrations."""

from __future__ import annotations

from dataclasses import dataclass


class IdentityMigrationConflict(Exception):
    pass


def normalize_email(value: str) -> str:
    normalized = value.strip().lower()
    if not normalized or "@" not in normalized:
        raise IdentityMigrationConflict("Invalid personal email")
    return normalized


@dataclass(frozen=True)
class PersonalEmailUpdate:
    user_id: str
    personal_email: str


def plan_personal_email_update(
    *, user_id: str, mapped_email: str, current_personal_email: str | None
) -> PersonalEmailUpdate | None:
    mapped = normalize_email(mapped_email)
    if current_personal_email is None:
        return PersonalEmailUpdate(user_id=user_id, personal_email=mapped)
    current = normalize_email(current_personal_email)
    if current != mapped:
        raise IdentityMigrationConflict("Existing personal email differs from mapping")
    return None


def validate_identity_link(
    *,
    intended_user_id: str,
    resolved_user_id: str,
    existing_subject: str | None,
    new_subject: str,
) -> None:
    if intended_user_id != resolved_user_id:
        raise IdentityMigrationConflict("Identity resolved to an unexpected domain user")
    if existing_subject is not None and existing_subject != new_subject:
        raise IdentityMigrationConflict("Domain user already has a different identity link")


def validate_unique_personal_email_updates(updates: list[PersonalEmailUpdate]) -> None:
    owners: dict[str, str] = {}
    for update in updates:
        email = normalize_email(update.personal_email)
        previous_owner = owners.setdefault(email, update.user_id)
        if previous_owner != update.user_id:
            raise IdentityMigrationConflict("Personal email maps to multiple domain users")


def validate_auth_email_match(*, intended_email: str, existing_auth_email: str | None) -> None:
    if existing_auth_email is None:
        return
    if normalize_email(intended_email) != normalize_email(existing_auth_email):
        raise IdentityMigrationConflict("Existing Auth identity email does not match")
