from collections.abc import Callable
from typing import Union

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.schemas.patient import PatientCreate, PatientUpdate
from app.services.patient_service import PatientService


def create_patient_router(
    *,
    get_db_dependency: Callable,
    auth_dependency: Callable,
    staff_dependency: Callable,
    doctor_dependency: Callable,
    audit_logger: Callable,
) -> APIRouter:
    router = APIRouter()
    service = PatientService(audit_logger=audit_logger)

    @router.get("/api/patients", dependencies=[Depends(auth_dependency)])
    def get_patients(db: Session = Depends(get_db_dependency)):
        return service.list_patients(db)

    @router.post("/api/patients")
    def create_patient(
        payload: PatientCreate,
        db: Session = Depends(get_db_dependency),
        user=Depends(staff_dependency),
    ):
        return service.create_patient(db, payload)

    @router.put("/api/patients/{patient_id}")
    def update_patient(
        patient_id: Union[int, str],
        payload: PatientUpdate,
        db: Session = Depends(get_db_dependency),
        user=Depends(staff_dependency),
    ):
        return service.update_patient(db, patient_id, payload)

    @router.get(
        "/api/patients/{patient_id}", dependencies=[Depends(auth_dependency)]
    )
    def get_patient(
        patient_id: Union[int, str], db: Session = Depends(get_db_dependency)
    ):
        return service.get_patient(db, patient_id)

    @router.delete("/api/patients/{patient_id}")
    def delete_patient(
        patient_id: Union[int, str],
        db: Session = Depends(get_db_dependency),
        user=Depends(doctor_dependency),
    ):
        return service.delete_patient(db, patient_id, user)

    return router
