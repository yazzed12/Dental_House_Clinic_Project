from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol
from uuid import UUID


class InvalidIdentityToken(Exception):
    """A bearer credential could not be cryptographically authenticated."""


@dataclass(frozen=True)
class IdentityClaims:
    subject: UUID


class IdentityProvider(Protocol):
    async def verify_access_token(self, token: str) -> IdentityClaims:
        """Verify a provider token and return only trusted identity claims."""


def parse_bearer_token(authorization: str) -> str:
    scheme, separator, token = authorization.strip().partition(" ")
    if not separator or scheme.lower() != "bearer" or not token.strip():
        raise InvalidIdentityToken("Invalid bearer authorization")
    if any(character.isspace() for character in token.strip()):
        raise InvalidIdentityToken("Invalid bearer authorization")
    return token.strip()
