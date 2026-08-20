"""Compatibility exports for Medication and Prescription ORM models."""
from models import (
    DentalMedication,
    DoctorMedicationPreset,
    MedicationClinicalPreset,
    MedicationImportBatch,
    MedicationImportRejection,
    Prescription,
    PrescriptionItem,
)

__all__ = [
    "DentalMedication",
    "MedicationClinicalPreset",
    "DoctorMedicationPreset",
    "MedicationImportBatch",
    "MedicationImportRejection",
    "Prescription",
    "PrescriptionItem",
]
