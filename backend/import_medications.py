"""Privileged CSV/JSON medication importer. It never downloads source data."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from types import SimpleNamespace

from app.schemas.medication import MedicationImportRequest
from app.services.medication_service import MedicationImportService
from database import SessionLocal
import models


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Import an approved medication dataset into the clinic database"
    )
    parser.add_argument("file", type=Path)
    parser.add_argument("--admin-id", required=True)
    parser.add_argument("--source-name", required=True)
    parser.add_argument("--source-version")
    parser.add_argument("--source-reference")
    parser.add_argument("--market", required=True)
    parser.add_argument("--country")
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()
    input_format = args.file.suffix.lower().lstrip(".")
    if input_format not in {"csv", "json"}:
        parser.error("file extension must be .csv or .json")
    payload = MedicationImportRequest(
        source_name=args.source_name,
        source_version=args.source_version,
        source_reference=args.source_reference,
        market=args.market,
        country=args.country,
        input_format=input_format,
        content=args.file.read_text(encoding="utf-8"),
        preview=args.preview,
    )
    db = SessionLocal()
    try:
        admin = db.query(models.User).filter(models.User.id == args.admin_id).first()
        if not admin or admin.role != "admin" or not bool(admin.is_active):
            raise SystemExit("--admin-id must identify an active application Admin")
        result = MedicationImportService().run(
            db, payload, SimpleNamespace(id=admin.id, role=admin.role)
        )
        print(json.dumps(result, indent=2, default=str))
    finally:
        db.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
