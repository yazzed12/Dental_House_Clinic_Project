from __future__ import annotations

from collections.abc import Awaitable, Callable, Mapping
from typing import Any
from uuid import UUID

import httpx
from jose import JWTError, jwt

from app.core.config import SupabaseAuthSettings
from app.identity.identity_provider import IdentityClaims, InvalidIdentityToken

JwksFetcher = Callable[[str], Awaitable[Mapping[str, Any]]]


class SupabaseJwtProvider:
    """Cryptographically verifies Supabase JWTs; not wired to runtime in Phase 11B."""

    def __init__(
        self,
        settings: SupabaseAuthSettings,
        jwks_fetcher: JwksFetcher | None = None,
    ) -> None:
        settings.validate()
        self._settings = settings
        self._jwks_fetcher = jwks_fetcher or self._fetch_jwks

    @staticmethod
    async def _fetch_jwks(url: str) -> Mapping[str, Any]:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(url)
            response.raise_for_status()
            value = response.json()
        if not isinstance(value, Mapping):
            raise InvalidIdentityToken("Invalid signing-key response")
        return value

    async def verify_access_token(self, token: str) -> IdentityClaims:
        try:
            header = jwt.get_unverified_header(token)
            algorithm = header.get("alg")
            key_id = header.get("kid")
            if algorithm not in self._settings.allowed_algorithms:
                raise InvalidIdentityToken("Unsupported token algorithm")
            if not isinstance(key_id, str) or not key_id:
                raise InvalidIdentityToken("Missing token key identifier")

            jwks = await self._jwks_fetcher(self._settings.jwks_url)
            keys = jwks.get("keys")
            if not isinstance(keys, list):
                raise InvalidIdentityToken("Invalid signing-key response")
            matches = [
                key
                for key in keys
                if isinstance(key, Mapping) and key.get("kid") == key_id
            ]
            if len(matches) != 1:
                raise InvalidIdentityToken("Unknown token key identifier")

            options = {"verify_aud": self._settings.audience is not None}
            payload = jwt.decode(
                token,
                dict(matches[0]),
                algorithms=list(self._settings.allowed_algorithms),
                issuer=self._settings.issuer,
                audience=self._settings.audience,
                options=options,
            )
            raw_subject = payload.get("sub")
            if not isinstance(raw_subject, str):
                raise InvalidIdentityToken("Missing token subject")
            return IdentityClaims(subject=UUID(raw_subject))
        except InvalidIdentityToken:
            raise
        except (JWTError, ValueError, TypeError, httpx.HTTPError) as exc:
            raise InvalidIdentityToken("Could not validate identity token") from exc
