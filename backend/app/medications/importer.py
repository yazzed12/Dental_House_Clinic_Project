from __future__ import annotations

import csv
import hashlib
import io
import json
import re
from dataclasses import dataclass
from typing import Any


VERIFICATION_STATUSES = {"pending", "verified", "unverified", "deprecated"}
LICENSING_STATUSES = {"pending", "approved", "restricted", "rejected"}


def normalize_text(value: Any) -> str | None:
    if value is None:
        return None
    normalized = re.sub(r"\s+", " ", str(value)).strip()
    return normalized or None


def normalized_identity(row: dict[str, Any], market: str) -> str:
    values = [
        row.get("brand_name"), row.get("generic_name"), row.get("strength"),
        row.get("dosage_form"), row.get("route"), market,
    ]
    return "|".join((normalize_text(value) or "").casefold() for value in values)


def _first(row: dict[str, Any], *names: str) -> Any:
    lowered = {str(key).strip().casefold(): value for key, value in row.items()}
    for name in names:
        if name.casefold() in lowered:
            return lowered[name.casefold()]
    return None


def _active(value: Any) -> bool:
    if value is None or normalize_text(value) is None:
        return True
    normalized = normalize_text(value).casefold()
    if normalized in {"true", "1", "yes", "active", "available"}:
        return True
    if normalized in {"false", "0", "no", "inactive", "withdrawn", "deprecated"}:
        return False
    raise ValueError("is_active must be a supported boolean/status value")


def parse_import_content(input_format: str, content: Any) -> list[dict[str, Any]]:
    if input_format == "csv":
        if not isinstance(content, str):
            raise ValueError("CSV content must be text")
        return [dict(row) for row in csv.DictReader(io.StringIO(content.lstrip("\ufeff")))]
    if input_format != "json":
        raise ValueError("Only csv and json import formats are supported")
    if isinstance(content, str):
        content = json.loads(content)
    if isinstance(content, dict):
        content = content.get("medications", content.get("rows"))
    if not isinstance(content, list) or any(not isinstance(row, dict) for row in content):
        raise ValueError("JSON content must be an array of medication objects")
    return content


@dataclass(frozen=True)
class NormalizedImportRow:
    row_number: int
    raw: dict[str, Any]
    values: dict[str, Any]


@dataclass(frozen=True)
class RejectedImportRow:
    row_number: int
    raw: dict[str, Any]
    source_record_id: str | None
    reasons: list[str]
    duplicate: bool = False


def normalize_import_rows(
    rows: list[dict[str, Any]], *, market: str, country: str | None = None,
) -> tuple[list[NormalizedImportRow], list[RejectedImportRow]]:
    normalized_rows: list[NormalizedImportRow] = []
    rejected: list[RejectedImportRow] = []
    seen_records: set[str] = set()
    seen_identities: set[str] = set()
    market_value = normalize_text(market)
    if not market_value:
        raise ValueError("market is required")

    for row_number, raw in enumerate(rows, start=1):
        source_record_id = normalize_text(_first(raw, "source_record_id", "source_id", "record_id", "id"))
        try:
            verification = (normalize_text(_first(raw, "verification_status")) or "pending").casefold()
            licensing = (normalize_text(_first(raw, "licensing_status")) or "pending").casefold()
            values = {
                "brand_name": normalize_text(_first(raw, "brand_name", "brand", "trade_name")),
                "generic_name": normalize_text(_first(raw, "generic_name", "generic", "active_ingredient")),
                "strength": normalize_text(_first(raw, "strength")),
                "dosage_form": normalize_text(_first(raw, "dosage_form", "form")),
                "route": normalize_text(_first(raw, "route")),
                "category": normalize_text(_first(raw, "category")),
                "manufacturer": normalize_text(_first(raw, "manufacturer")),
                "market": market_value,
                "country": normalize_text(_first(raw, "country")) or normalize_text(country),
                "source_record_id": source_record_id,
                "verification_status": verification,
                "licensing_status": licensing,
                "is_active": _active(_first(raw, "is_active", "status")),
            }
            reasons = []
            for field in ("brand_name", "strength", "dosage_form", "route"):
                if not values[field]:
                    reasons.append(f"{field} is required")
            limits = {
                "brand_name": 300, "generic_name": 500, "strength": 200,
                "dosage_form": 200, "route": 200, "category": 300,
                "manufacturer": 300, "market": 100, "country": 100,
            }
            reasons.extend(
                f"{field} exceeds {limit} characters"
                for field, limit in limits.items()
                if values.get(field) and len(values[field]) > limit
            )
            if verification not in VERIFICATION_STATUSES:
                reasons.append("verification_status is invalid")
            if licensing not in LICENSING_STATUSES:
                reasons.append("licensing_status is invalid")
            if reasons:
                rejected.append(RejectedImportRow(row_number, raw, source_record_id, reasons))
                continue
            identity_key = normalized_identity(values, market_value)
            values["identity_key"] = identity_key
            if not source_record_id:
                values["source_record_id"] = "derived:" + hashlib.sha256(identity_key.encode()).hexdigest()
            record_key = values["source_record_id"].casefold()
            if record_key in seen_records or identity_key in seen_identities:
                rejected.append(RejectedImportRow(
                    row_number, raw, values["source_record_id"],
                    ["duplicate source row in this import"], duplicate=True,
                ))
                continue
            seen_records.add(record_key)
            seen_identities.add(identity_key)
            normalized_rows.append(NormalizedImportRow(row_number, raw, values))
        except (TypeError, ValueError) as error:
            rejected.append(RejectedImportRow(row_number, raw, source_record_id, [str(error)]))
    return normalized_rows, rejected
