from collections.abc import Callable
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.schemas.medication import (
    CustomMedicationCreate, DoctorMedicationPresetUpsert, MedicationImportRequest,
    PrescriptionApprove, PrescriptionDraftSave,
)
from app.services.medication_service import MedicationImportService, MedicationService


def create_medication_router(*, get_db_dependency: Callable, doctor_dependency: Callable,
                             admin_dependency: Callable) -> APIRouter:
    router = APIRouter(prefix="/api")
    service = MedicationService(); importer = MedicationImportService()

    @router.get("/medications")
    def search_medications(q: str = Query(min_length=1, max_length=200), limit: int = Query(20, ge=1, le=50),
                           db: Session = Depends(get_db_dependency), user=Depends(doctor_dependency)):
        return service.search(db, q, limit)

    @router.post("/medications/custom")
    def create_custom_medication(payload: CustomMedicationCreate,
                                 db: Session = Depends(get_db_dependency), user=Depends(doctor_dependency)):
        return service.create_custom(db, payload, user)

    @router.get("/medications/{medication_id}")
    def get_medication_details(medication_id: UUID, db: Session = Depends(get_db_dependency),
                               user=Depends(doctor_dependency)):
        return service.details(db, medication_id)

    @router.get("/medications/{medication_id}/effective-preset")
    def get_effective_preset(medication_id: UUID, db: Session = Depends(get_db_dependency),
                             user=Depends(doctor_dependency)):
        return service.effective_preset(db, medication_id, user)

    @router.put("/medications/{medication_id}/doctor-preset")
    def save_doctor_preset(medication_id: UUID, payload: DoctorMedicationPresetUpsert,
                           db: Session = Depends(get_db_dependency), user=Depends(doctor_dependency)):
        return service.upsert_doctor_preset(db, medication_id, payload, user)

    @router.delete("/medications/{medication_id}/doctor-preset")
    def delete_doctor_preset(medication_id: UUID, db: Session = Depends(get_db_dependency),
                             user=Depends(doctor_dependency)):
        return service.delete_doctor_preset(db, medication_id, user)

    @router.get("/consultations/{consultation_id}/prescription")
    def get_prescription(consultation_id: UUID, db: Session = Depends(get_db_dependency),
                         user=Depends(doctor_dependency)):
        return service.get_prescription(db, consultation_id, user)

    @router.put("/consultations/{consultation_id}/prescription/draft")
    def save_prescription_draft(consultation_id: UUID, payload: PrescriptionDraftSave,
                                db: Session = Depends(get_db_dependency), user=Depends(doctor_dependency)):
        return service.save_draft(db, consultation_id, payload, user)

    @router.post("/prescriptions/{prescription_id}/approve")
    def approve_prescription(prescription_id: UUID, payload: PrescriptionApprove,
                             db: Session = Depends(get_db_dependency), user=Depends(doctor_dependency)):
        return service.approve(db, prescription_id, payload, user)

    @router.post("/admin/medications/import")
    def import_medications(payload: MedicationImportRequest, db: Session = Depends(get_db_dependency),
                           user=Depends(admin_dependency)):
        return importer.run(db, payload, user)

    return router
