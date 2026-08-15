from collections.abc import Callable
from typing import Union

from fastapi import APIRouter, BackgroundTasks, Depends
from sqlalchemy.orm import Session

from app.schemas.appointment import AppointmentCreate
from app.services.appointment_service import AppointmentService


def _service(
    *, audit_logger: Callable, reminder_callable: Callable, logger
) -> AppointmentService:
    return AppointmentService(
        audit_logger=audit_logger,
        reminder_callable=reminder_callable,
        logger=logger,
    )


def create_today_appointments_router(
    *,
    get_db_dependency: Callable,
    auth_dependency: Callable,
    audit_logger: Callable,
    reminder_callable: Callable,
    logger,
) -> APIRouter:
    router = APIRouter()
    service = _service(
        audit_logger=audit_logger,
        reminder_callable=reminder_callable,
        logger=logger,
    )

    @router.get("/appointments/today", dependencies=[Depends(auth_dependency)])
    def get_today_appointments(db: Session = Depends(get_db_dependency)):
        return service.list_today(db)

    return router


def create_appointment_crud_router(
    *,
    get_db_dependency: Callable,
    auth_dependency: Callable,
    staff_dependency: Callable,
    audit_logger: Callable,
    reminder_callable: Callable,
    logger,
) -> APIRouter:
    router = APIRouter()
    service = _service(
        audit_logger=audit_logger,
        reminder_callable=reminder_callable,
        logger=logger,
    )

    @router.get("/api/appointments", dependencies=[Depends(auth_dependency)])
    def get_appointments(db: Session = Depends(get_db_dependency)):
        return service.list_appointments(db)

    @router.post("/api/appointments")
    def create_appointment(
        payload: AppointmentCreate,
        background_tasks: BackgroundTasks,
        db: Session = Depends(get_db_dependency),
        user=Depends(staff_dependency),
    ):
        return service.create_appointment(db, payload, background_tasks)

    @router.put("/api/appointments/{appointment_id}/status")
    def update_appointment_status(
        appointment_id: Union[int, str],
        status_update: dict,
        db: Session = Depends(get_db_dependency),
        user=Depends(staff_dependency),
    ):
        return service.update_status(db, appointment_id, status_update)

    @router.put("/api/appointments/{appointment_id}")
    def update_appointment(
        appointment_id: Union[int, str],
        payload: dict,
        db: Session = Depends(get_db_dependency),
        user=Depends(staff_dependency),
    ):
        return service.update_appointment(db, appointment_id, payload, user)

    @router.delete("/api/appointments/{appointment_id}")
    def delete_appointment(
        appointment_id: Union[int, str],
        db: Session = Depends(get_db_dependency),
        user=Depends(staff_dependency),
    ):
        return service.delete_appointment(db, appointment_id)

    return router


def create_appointment_completion_router(
    *,
    get_db_dependency: Callable,
    doctor_dependency: Callable,
    audit_logger: Callable,
    reminder_callable: Callable,
    logger,
) -> APIRouter:
    router = APIRouter()
    service = _service(
        audit_logger=audit_logger,
        reminder_callable=reminder_callable,
        logger=logger,
    )

    @router.post("/api/appointments/finish-by-patient/{patient_id}")
    def finish_appointment_by_patient(
        patient_id: Union[int, str],
        db: Session = Depends(get_db_dependency),
        user=Depends(doctor_dependency),
    ):
        return service.finish_by_patient(db, patient_id, user)

    @router.put("/appointments/{appointment_id}/finish")
    def finish_appointment(
        appointment_id: Union[int, str],
        db: Session = Depends(get_db_dependency),
        user=Depends(doctor_dependency),
    ):
        return service.finish_by_id(db, appointment_id, user)

    return router
