from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class MedicationSchema(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)


class CustomMedicationCreate(MedicationSchema):
    brand_name: str = Field(min_length=1, max_length=300)
    generic_name: str | None = Field(default=None, max_length=500)
    strength: str = Field(min_length=1, max_length=200)
    dosage_form: str = Field(min_length=1, max_length=200)
    route: str = Field(min_length=1, max_length=200)
    category: str | None = Field(default=None, max_length=300)
    manufacturer: str | None = Field(default=None, max_length=300)


class DoctorMedicationPresetUpsert(MedicationSchema):
    dose: str | None = Field(default=None, max_length=300)
    frequency: str | None = Field(default=None, max_length=300)
    duration: str | None = Field(default=None, max_length=300)
    instructions: str | None = Field(default=None, max_length=4000)
    doctor_notes: str | None = Field(default=None, max_length=4000)


class PrescriptionItemInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, str_strip_whitespace=True)

    medication_id: UUID = Field(alias="medicationId")
    clinical_preset_id: UUID | None = Field(default=None, alias="clinicalPresetId")
    doctor_preset_id: UUID | None = Field(default=None, alias="doctorPresetId")
    brand_name: str = Field(alias="brandName", min_length=1, max_length=300)
    generic_name: str | None = Field(default=None, alias="genericName", max_length=500)
    strength: str = Field(min_length=1, max_length=200)
    dosage_form: str = Field(alias="dosageForm", min_length=1, max_length=200)
    route: str = Field(min_length=1, max_length=200)
    dose: str = Field(min_length=1, max_length=300)
    frequency: str = Field(min_length=1, max_length=300)
    duration: str = Field(min_length=1, max_length=300)
    instructions: str | None = Field(default=None, max_length=4000)
    doctor_notes: str | None = Field(default=None, alias="doctorNotes", max_length=4000)


class PrescriptionDraftSave(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    expected_version: int = Field(alias="expectedVersion", ge=0)
    items: list[PrescriptionItemInput] = Field(max_length=50)


class PrescriptionApprove(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    expected_version: int = Field(alias="expectedVersion", ge=1)


class MedicationImportRequest(MedicationSchema):
    source_name: str = Field(min_length=1, max_length=300)
    source_version: str | None = Field(default=None, max_length=200)
    source_reference: str | None = Field(default=None, max_length=2000)
    market: str = Field(min_length=1, max_length=100)
    country: str | None = Field(default=None, max_length=100)
    input_format: Literal["csv", "json"]
    content: str | list[dict[str, Any]] | dict[str, Any]
    preview: bool = False
