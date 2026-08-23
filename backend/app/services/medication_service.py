from __future__ import annotations

from datetime import datetime, timezone
import uuid

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

import models
from app.medications.importer import (
    normalize_import_rows,
    normalize_text,
    normalized_identity,
    parse_import_content,
)
from app.repositories.medication_repository import MedicationRepository


def _clean(value):
    value = value.strip() if isinstance(value, str) else value
    return value or None


class MedicationService:
    def __init__(self, repository: MedicationRepository | None = None):
        self.repository = repository or MedicationRepository()

    @staticmethod
    def serialize_medication(row) -> dict:
        return {
            "id": row.id, "brandName": row.brand_name,
            "genericName": row.generic_name, "strength": row.strength,
            "dosageForm": row.dosage_form, "route": row.route,
            "category": row.category, "manufacturer": row.manufacturer,
            "market": row.market, "catalogScope": row.catalog_scope,
            "isCustom": row.catalog_scope == "clinic",
            "verificationStatus": row.verification_status,
            "sourceType": row.source_type, "sourceName": row.source_name,
            "sourceReference": row.source_reference,
            "sourceVersion": row.source_version,
            "sourceRecordId": row.source_record_id,
        }

    @staticmethod
    def _is_prescribable(medication) -> bool:
        return bool(medication and medication.is_active and (
            (medication.catalog_scope == "clinic" and medication.verification_status == "unverified")
            or (medication.catalog_scope == "global" and medication.verification_status == "verified")
        ))

    def search(self, db: Session, query: str, limit: int = 20) -> list[dict]:
        normalized = " ".join((query or "").split()).casefold()
        if not normalized or len(normalized) > 200:
            raise HTTPException(status_code=400, detail="MEDICATION_SEARCH_INVALID")
        return [self.serialize_medication(row) for row in self.repository.search(db, normalized, min(max(limit, 1), 50))]

    def details(self, db: Session, medication_id) -> dict:
        medication = self.repository.get_medication(db, medication_id)
        if not self._is_prescribable(medication):
            raise HTTPException(status_code=404, detail="MEDICATION_NOT_AVAILABLE")
        return self.serialize_medication(medication)

    def create_custom(self, db: Session, payload, user) -> dict:
        values = payload.model_dump()
        identity_key = normalized_identity(values, "clinic")
        existing = self.repository.get_custom_by_identity(db, identity_key)
        if existing:
            if not existing.is_active:
                existing.is_active = True
                existing.updated_at = datetime.now(timezone.utc)
                db.commit()
            return self.serialize_medication(existing)
        medication = models.DentalMedication(
            id=str(uuid.uuid4()), catalog_scope="clinic", identity_key=identity_key,
            brand_name=payload.brand_name, generic_name=_clean(payload.generic_name),
            strength=payload.strength, dosage_form=payload.dosage_form,
            route=payload.route, category=_clean(payload.category),
            manufacturer=_clean(payload.manufacturer), market="clinic", country="clinic",
            source_type="clinic_custom", source_name="Clinician-entered custom medication",
            verification_status="unverified", is_active=True, created_by=str(user.id),
        )
        db.add(medication)
        try:
            db.commit()
        except IntegrityError as error:
            db.rollback()
            existing = self.repository.get_custom_by_identity(db, identity_key)
            if existing:
                return self.serialize_medication(existing)
            raise HTTPException(status_code=409, detail="CUSTOM_MEDICATION_DUPLICATE") from error
        db.refresh(medication)
        return self.serialize_medication(medication)

    def effective_preset(self, db: Session, medication_id, user) -> dict:
        medication = self.repository.get_medication(db, medication_id)
        if not self._is_prescribable(medication):
            raise HTTPException(status_code=404, detail="MEDICATION_NOT_AVAILABLE")
        standard = self.repository.get_standard_preset(db, medication_id)
        doctor = self.repository.get_doctor_preset(db, user.id, medication_id)
        standard_data = None if not standard else {
            "id": standard.id, "dose": standard.default_dose,
            "frequency": standard.default_frequency, "duration": standard.default_duration,
            "instructions": standard.default_instructions,
            "clinicalContext": standard.clinical_context,
            "presetVersion": standard.preset_version,
        }
        doctor_data = None if not doctor else {
            "id": doctor.id, "dose": doctor.default_dose,
            "frequency": doctor.default_frequency, "duration": doctor.default_duration,
            "instructions": doctor.default_instructions, "doctorNotes": doctor.doctor_notes,
        }
        return {
            "medication": self.serialize_medication(medication),
            "clinicalPreset": standard_data, "doctorPreset": doctor_data,
            "effectivePreset": {
                "dose": (doctor.default_dose if doctor and doctor.default_dose is not None else standard.default_dose if standard else None),
                "frequency": (doctor.default_frequency if doctor and doctor.default_frequency is not None else standard.default_frequency if standard else None),
                "duration": (doctor.default_duration if doctor and doctor.default_duration is not None else standard.default_duration if standard else None),
                "instructions": (doctor.default_instructions if doctor and doctor.default_instructions is not None else standard.default_instructions if standard else None),
                "doctorNotes": doctor.doctor_notes if doctor else None,
                "clinicalPresetId": standard.id if standard else None,
                "doctorPresetId": doctor.id if doctor else None,
            },
        }

    def upsert_doctor_preset(self, db: Session, medication_id, payload, user) -> dict:
        if user.role != "doctor":
            raise HTTPException(status_code=403, detail="DOCTOR_PRESET_AUTHORIZATION_DENIED")
        if not self._is_prescribable(self.repository.get_medication(db, medication_id)):
            raise HTTPException(status_code=404, detail="MEDICATION_NOT_AVAILABLE")
        preset = self.repository.get_doctor_preset(db, user.id, medication_id)
        if not preset:
            preset = models.DoctorMedicationPreset(
                id=str(uuid.uuid4()), doctor_id=str(user.id), medication_id=str(medication_id)
            )
            db.add(preset)
        for source, target in (
            ("dose", "default_dose"), ("frequency", "default_frequency"),
            ("duration", "default_duration"), ("instructions", "default_instructions"),
            ("doctor_notes", "doctor_notes"),
        ):
            setattr(preset, target, _clean(getattr(payload, source)))
        db.commit(); db.refresh(preset)
        return {"id": preset.id, "medicationId": preset.medication_id,
            "dose": preset.default_dose, "frequency": preset.default_frequency,
            "duration": preset.default_duration, "instructions": preset.default_instructions,
            "doctorNotes": preset.doctor_notes}

    def delete_doctor_preset(self, db: Session, medication_id, user) -> dict:
        preset = self.repository.get_doctor_preset(db, user.id, medication_id)
        if preset:
            db.delete(preset); db.commit()
        return {"deleted": bool(preset), "medicationId": str(medication_id)}

    @staticmethod
    def serialize_prescription(prescription) -> dict | None:
        if not prescription:
            return None
        return {
            "id": prescription.id, "consultationId": prescription.consultation_id,
            "patientId": prescription.patient_id, "doctorId": prescription.doctor_id,
            "appointmentId": prescription.appointment_id, "status": prescription.status,
            "version": prescription.version, "approvedBy": prescription.approved_by,
            "approvedAt": prescription.approved_at.isoformat() if prescription.approved_at else None,
            "items": [{
                "id": item.id, "medicationId": item.medication_id,
                "clinicalPresetId": item.clinical_preset_id, "doctorPresetId": item.doctor_preset_id,
                "position": item.position, "brandName": item.brand_name_snapshot,
                "genericName": item.generic_name_snapshot, "strength": item.strength_snapshot,
                "dosageForm": item.dosage_form_snapshot, "route": item.route_snapshot,
                "dose": item.dose_snapshot, "frequency": item.frequency_snapshot,
                "duration": item.duration_snapshot, "instructions": item.instructions_snapshot,
                "doctorNotes": item.doctor_notes_snapshot, "sourceType": item.source_type_snapshot,
                "sourceName": item.source_name_snapshot, "sourceReference": item.source_reference_snapshot,
                "sourceVersion": item.source_version_snapshot, "sourceRecordId": item.source_record_id_snapshot,
                "verificationStatus": item.verification_status_snapshot,
            } for item in sorted(prescription.items, key=lambda row: row.position)],
        }

    @staticmethod
    def _owned_consultation(db: Session, consultation_id, user):
        consultation = db.query(models.Consultation).filter(models.Consultation.id == str(consultation_id)).first()
        if not consultation:
            raise HTTPException(status_code=404, detail="PRESCRIPTION_CONSULTATION_NOT_FOUND")
        if user.role != "admin" and str(consultation.doctor_id) != str(user.id):
            raise HTTPException(status_code=403, detail="PRESCRIPTION_AUTHORIZATION_DENIED")
        return consultation

    def get_prescription(self, db: Session, consultation_id, user) -> dict | None:
        self._owned_consultation(db, consultation_id, user)
        return self.serialize_prescription(self.repository.get_prescription(db, consultation_id))

    def save_draft(self, db: Session, consultation_id, payload, user) -> dict | None:
        consultation = self._owned_consultation(db, consultation_id, user)
        prescription = self.repository.get_prescription(db, consultation_id)
        if prescription and prescription.status != "draft":
            raise HTTPException(status_code=409, detail="APPROVED_PRESCRIPTION_IMMUTABLE")
        current_version = prescription.version if prescription else 0
        if payload.expected_version != current_version:
            raise HTTPException(status_code=409, detail="PRESCRIPTION_VERSION_CONFLICT")
        medication_ids = [str(item.medication_id) for item in payload.items]
        if len(medication_ids) != len(set(medication_ids)):
            raise HTTPException(status_code=400, detail="PRESCRIPTION_ITEM_DUPLICATE")
        if not payload.items:
            if prescription:
                db.query(models.PrescriptionItem).filter(models.PrescriptionItem.prescription_id == prescription.id).delete()
                db.delete(prescription); db.commit()
            return None
        if not prescription:
            prescription = models.Prescription(
                id=str(uuid.uuid4()), consultation_id=str(consultation.id),
                patient_id=str(consultation.patient_id), doctor_id=str(consultation.doctor_id),
                appointment_id=str(consultation.appointment_id) if consultation.appointment_id else None,
                status="draft", version=1,
            )
            db.add(prescription); db.flush()
        else:
            prescription.version += 1
            prescription.updated_at = datetime.now(timezone.utc)
            db.query(models.PrescriptionItem).filter(models.PrescriptionItem.prescription_id == prescription.id).delete()
        for position, item_input in enumerate(payload.items, start=1):
            medication = self.repository.get_medication(db, item_input.medication_id)
            if not self._is_prescribable(medication):
                db.rollback(); raise HTTPException(status_code=400, detail="MEDICATION_NOT_AVAILABLE")
            if item_input.clinical_preset_id:
                clinical_preset = self.repository.get_standard_preset(db, item_input.medication_id)
                if not clinical_preset or str(clinical_preset.id) != str(item_input.clinical_preset_id):
                    db.rollback(); raise HTTPException(status_code=400, detail="PRESCRIPTION_PRESET_MISMATCH")
            if item_input.doctor_preset_id:
                doctor_preset = self.repository.get_doctor_preset(
                    db, consultation.doctor_id, item_input.medication_id
                )
                if not doctor_preset or str(doctor_preset.id) != str(item_input.doctor_preset_id):
                    db.rollback(); raise HTTPException(status_code=400, detail="PRESCRIPTION_PRESET_MISMATCH")
            item = models.PrescriptionItem(
                id=str(uuid.uuid4()), prescription_id=prescription.id,
                medication_id=str(item_input.medication_id),
                clinical_preset_id=str(item_input.clinical_preset_id) if item_input.clinical_preset_id else None,
                doctor_preset_id=str(item_input.doctor_preset_id) if item_input.doctor_preset_id else None,
                position=position, brand_name_snapshot=item_input.brand_name,
                generic_name_snapshot=_clean(item_input.generic_name), strength_snapshot=item_input.strength,
                dosage_form_snapshot=item_input.dosage_form, route_snapshot=item_input.route,
                dose_snapshot=item_input.dose, frequency_snapshot=item_input.frequency,
                duration_snapshot=item_input.duration, instructions_snapshot=_clean(item_input.instructions),
                doctor_notes_snapshot=_clean(item_input.doctor_notes), source_type_snapshot=medication.source_type,
                source_name_snapshot=medication.source_name, source_reference_snapshot=medication.source_reference,
                source_version_snapshot=medication.source_version, source_record_id_snapshot=medication.source_record_id,
                verification_status_snapshot=medication.verification_status,
            )
            db.add(item)
        db.commit()
        return self.serialize_prescription(self.repository.get_prescription(db, consultation_id))

    def approve(self, db: Session, prescription_id, payload, user) -> dict:
        prescription = self.repository.get_prescription_by_id(db, prescription_id)
        if not prescription:
            raise HTTPException(status_code=404, detail="PRESCRIPTION_NOT_FOUND")
        self._owned_consultation(db, prescription.consultation_id, user)
        if str(prescription.doctor_id) != str(user.id) and user.role != "admin":
            raise HTTPException(status_code=403, detail="PRESCRIPTION_AUTHORIZATION_DENIED")
        if prescription.status != "draft":
            raise HTTPException(status_code=409, detail="APPROVED_PRESCRIPTION_IMMUTABLE")
        if prescription.version != payload.expected_version:
            raise HTTPException(status_code=409, detail="PRESCRIPTION_VERSION_CONFLICT")
        if not prescription.items:
            raise HTTPException(status_code=400, detail="PRESCRIPTION_EMPTY")
        prescription.status = "approved"; prescription.approved_by = str(user.id)
        prescription.approved_at = datetime.now(timezone.utc); prescription.version += 1
        prescription.updated_at = prescription.approved_at
        db.commit()
        return self.serialize_prescription(self.repository.get_prescription_by_id(db, prescription.id))


class MedicationImportService:
    UPSERT_FIELDS = (
        "identity_key", "brand_name", "generic_name", "strength", "dosage_form", "route",
        "category", "manufacturer", "country", "source_version", "source_reference",
        "verification_status", "is_active",
    )

    def __init__(self, repository: MedicationRepository | None = None):
        self.repository = repository or MedicationRepository()

    def run(self, db: Session, payload, user) -> dict:
        if user.role != "admin":
            raise HTTPException(status_code=403, detail="MEDICATION_IMPORT_AUTHORIZATION_DENIED")
        if isinstance(payload.content, str) and len(payload.content.encode("utf-8")) > 10_000_000:
            raise HTTPException(status_code=413, detail="MEDICATION_IMPORT_TOO_LARGE")
        source_name = normalize_text(payload.source_name)
        market = normalize_text(payload.market)
        country = normalize_text(payload.country)
        source_version = normalize_text(payload.source_version)
        source_reference = normalize_text(payload.source_reference)
        try:
            raw_rows = parse_import_content(payload.input_format, payload.content)
            if len(raw_rows) > 50_000:
                raise ValueError("Import is limited to 50000 rows")
            rows, rejected_rows = normalize_import_rows(raw_rows, market=market, country=country)
        except (ValueError, TypeError) as error:
            raise HTTPException(status_code=400, detail=str(error)) from error
        now = datetime.now(timezone.utc)
        summary = {"total_rows": len(raw_rows), "inserted": 0, "updated": 0, "unchanged": 0,
                   "rejected": sum(not row.duplicate for row in rejected_rows),
                   "duplicates": sum(row.duplicate for row in rejected_rows)}
        classifications = []
        for row in rows:
            desired = {
                **row.values,
                "source_version": source_version,
                "source_reference": source_reference,
            }
            existing = self.repository.find_imported(
                db, source_name, market,
                row.values["source_record_id"], row.values["identity_key"],
            )
            changed = existing and any(getattr(existing, field) != desired.get(field) for field in self.UPSERT_FIELDS)
            action = "updated" if changed else "unchanged" if existing else "inserted"
            summary[action] += 1
            classifications.append((row, existing, action, desired))
        rejection_details = [{"row_number": row.row_number, "source_record_id": row.source_record_id,
            "reasons": row.reasons, "duplicate": row.duplicate} for row in rejected_rows]
        if payload.preview:
            return {**summary, "preview": True, "rejections": rejection_details}

        batch = models.MedicationImportBatch(
            id=str(uuid.uuid4()), source_name=source_name,
            source_version=source_version, source_reference=source_reference,
            market=market, input_format=payload.input_format, status="processing",
            total_rows=len(raw_rows), imported_by=str(user.id),
        )
        db.add(batch); db.flush()
        for rejected in rejected_rows:
            db.add(models.MedicationImportRejection(
                id=str(uuid.uuid4()), batch_id=batch.id, row_number=rejected.row_number,
                source_record_id=rejected.source_record_id, raw_payload=rejected.raw,
                reasons=rejected.reasons,
            ))
        for row, existing, action, values in classifications:
            if not existing:
                existing = models.DentalMedication(
                    id=str(uuid.uuid4()), catalog_scope="global", source_type="structured_import",
                    source_name=source_name, market=market,
                    source_record_id=values["source_record_id"], imported_at=now,
                )
                db.add(existing)
            if action != "unchanged":
                for field in self.UPSERT_FIELDS:
                    setattr(existing, field, values.get(field))
                existing.source_name = source_name
                existing.source_reference = source_reference
                existing.source_version = source_version
                existing.import_batch_id = batch.id
                existing.imported_at = now
                existing.updated_at = now
                existing.last_verified_at = now if values["verification_status"] == "verified" else None
        batch.inserted_count = summary["inserted"]; batch.updated_count = summary["updated"]
        batch.unchanged_count = summary["unchanged"]; batch.rejected_count = summary["rejected"]
        batch.duplicate_count = summary["duplicates"]; batch.status = "completed"; batch.completed_at = now
        try:
            db.commit()
        except IntegrityError as error:
            db.rollback()
            raise HTTPException(status_code=409, detail="MEDICATION_IMPORT_UNIQUENESS_CONFLICT") from error
        return {**summary, "preview": False, "batch_id": batch.id, "rejections": rejection_details}
