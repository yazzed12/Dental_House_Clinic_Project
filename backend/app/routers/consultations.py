from collections.abc import Callable

from fastapi import APIRouter, BackgroundTasks, Depends
from sqlalchemy.orm import Session

from app.schemas.consultation import ConsultationPayload
from app.services.consultation_service import ConsultationService


def create_consultation_router(
    *,
    get_db_dependency: Callable,
    doctor_dependency: Callable,
    audit_logger: Callable,
    report_generator: Callable,
    logger,
) -> APIRouter:
    router = APIRouter()
    service = ConsultationService(
        audit_logger=audit_logger,
        report_generator=report_generator,
        logger=logger,
    )

    @router.get("/api/consultations/{patient_id}")
    def get_consultation(
        patient_id: int | str,
        db: Session = Depends(get_db_dependency),
        user=Depends(doctor_dependency),
    ):
        return service.get_consultation(db, patient_id)

    @router.post("/api/consultations/{patient_id}")
    def save_consultation(
        patient_id: int | str,
        payload: ConsultationPayload,
        background_tasks: BackgroundTasks,
        db: Session = Depends(get_db_dependency),
        user=Depends(doctor_dependency),
    ):
        return service.save_consultation(
            db, patient_id, payload, user, background_tasks
        )

    @router.get("/api/consultations/{patient_id}/history")
    def get_consultation_history(
        patient_id: int | str,
        db: Session = Depends(get_db_dependency),
        user=Depends(doctor_dependency),
    ):
        return service.get_patient_history(db, patient_id)

    return router


def create_consultation_history_router(
    *, get_db_dependency: Callable, doctor_dependency: Callable
) -> APIRouter:
    router = APIRouter()
    service = ConsultationService()

    @router.get("/api/doctor/consultations/history")
    def get_doctor_consultations_history(
        db: Session = Depends(get_db_dependency),
        user=Depends(doctor_dependency),
    ):
        return service.get_doctor_history(db, user)

    return router
