from __future__ import annotations

from sqlalchemy import func, or_
from sqlalchemy.orm import Session, joinedload

import models


class MedicationRepository:
    @staticmethod
    def search(db: Session, query: str, limit: int = 20):
        term = f"{query.casefold()}%"
        return db.query(models.DentalMedication).filter(
            models.DentalMedication.is_active.is_(True),
            or_(
                (models.DentalMedication.catalog_scope == "clinic")
                & (models.DentalMedication.verification_status == "unverified"),
                (models.DentalMedication.catalog_scope == "global")
                & (models.DentalMedication.verification_status == "verified")
                & (models.DentalMedication.licensing_status == "approved"),
            ),
            or_(
                func.lower(models.DentalMedication.brand_name).like(term),
                func.lower(func.coalesce(models.DentalMedication.generic_name, "")).like(term),
                func.lower(models.DentalMedication.strength).like(term),
                func.lower(models.DentalMedication.dosage_form).like(term),
                func.lower(func.coalesce(models.DentalMedication.category, "")).like(term),
            ),
        ).order_by(
            func.lower(models.DentalMedication.brand_name),
            func.lower(models.DentalMedication.strength),
            func.lower(models.DentalMedication.dosage_form),
            models.DentalMedication.id,
        ).limit(limit).all()

    @staticmethod
    def get_medication(db: Session, medication_id):
        return db.query(models.DentalMedication).filter(models.DentalMedication.id == str(medication_id)).first()

    @staticmethod
    def get_custom_by_identity(db: Session, identity_key: str):
        return db.query(models.DentalMedication).filter(
            models.DentalMedication.catalog_scope == "clinic",
            models.DentalMedication.identity_key == identity_key,
        ).first()

    @staticmethod
    def get_standard_preset(db: Session, medication_id):
        return db.query(models.MedicationClinicalPreset).filter(
            models.MedicationClinicalPreset.medication_id == str(medication_id),
            models.MedicationClinicalPreset.is_active.is_(True),
            models.MedicationClinicalPreset.review_status == "approved",
        ).order_by(models.MedicationClinicalPreset.preset_version.desc()).first()

    @staticmethod
    def get_doctor_preset(db: Session, doctor_id, medication_id):
        return db.query(models.DoctorMedicationPreset).filter(
            models.DoctorMedicationPreset.doctor_id == str(doctor_id),
            models.DoctorMedicationPreset.medication_id == str(medication_id),
        ).first()

    @staticmethod
    def get_prescription(db: Session, consultation_id, *, with_items=True):
        query = db.query(models.Prescription)
        if with_items:
            query = query.options(joinedload(models.Prescription.items))
        return query.filter(models.Prescription.consultation_id == str(consultation_id)).first()

    @staticmethod
    def get_prescription_by_id(db: Session, prescription_id, *, with_items=True):
        query = db.query(models.Prescription)
        if with_items:
            query = query.options(joinedload(models.Prescription.items))
        return query.filter(models.Prescription.id == str(prescription_id)).first()

    @staticmethod
    def find_imported(db: Session, source_name: str, market: str, source_record_id: str, identity_key: str):
        return db.query(models.DentalMedication).filter(
            models.DentalMedication.catalog_scope == "global",
            func.lower(models.DentalMedication.source_name) == source_name.casefold(),
            func.lower(models.DentalMedication.market) == market.casefold(),
            or_(
                models.DentalMedication.source_record_id == source_record_id,
                models.DentalMedication.identity_key == identity_key,
            ),
        ).first()
