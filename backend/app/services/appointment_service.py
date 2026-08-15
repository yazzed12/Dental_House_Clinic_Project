from collections.abc import Callable
from datetime import date
from typing import Optional, Union
import uuid

from fastapi import BackgroundTasks, HTTPException
from sqlalchemy.orm import Session

import models
from app.repositories.appointment_repository import AppointmentRepository


def normalize_appointment_type(raw_type: Optional[str]) -> str:
    if not raw_type:
        return "consultation"
    value = raw_type.lower().strip().replace("-", "_").replace(" ", "_")
    if "check" in value or "norm" in value:
        return "normal"
    if "urg" in value or "emerg" in value:
        return "urgent"
    if "follow" in value:
        return "follow_up"
    if "consult" in value:
        return "consultation"
    if value in ["normal", "urgent", "follow_up", "consultation"]:
        return value
    return "consultation"


def normalize_appointment_status(raw_status: Optional[str]) -> str:
    if not raw_status:
        return "pending"
    value = raw_status.lower().strip().replace("-", "_").replace(" ", "_")
    if value in {"complete", "completed", "finished"}:
        return "completed"
    if value in [
        "pending",
        "scheduled",
        "confirmed",
        "cancelled",
        "no_show",
    ]:
        return value
    return "pending"


class AppointmentService:
    def __init__(
        self,
        repository: AppointmentRepository | None = None,
        audit_logger: Callable | None = None,
        reminder_callable: Callable | None = None,
        logger=None,
    ):
        self.repository = repository or AppointmentRepository()
        self.audit_logger = audit_logger
        self.reminder_callable = reminder_callable
        self.logger = logger

    @staticmethod
    def _serialize(appointment, patient_name: str) -> dict:
        return {
            "id": appointment.id,
            "patient_id": appointment.patient_id,
            "patient": patient_name,
            "date": str(appointment.date),
            "time": appointment.time,
            "type": appointment.type,
            "status": appointment.status,
            "condition": appointment.condition
            if appointment.condition
            else "Routine Checkup",
        }

    def list_appointments(self, db: Session) -> list[dict]:
        return [
            self._serialize(
                appointment,
                appointment.patient.name if appointment.patient else "Unknown",
            )
            for appointment in self.repository.get_all(db)
        ]

    def list_today(self, db: Session) -> list[dict]:
        try:
            appointments = self.repository.get_today(db, date.today())
            return [
                {
                    "id": appointment.id,
                    "patient_id": appointment.patient_id,
                    "patient_name": appointment.patient.name
                    if appointment.patient
                    else "Unknown",
                    "time": appointment.time,
                    "type": appointment.type,
                    "status": appointment.status,
                }
                for appointment in appointments
            ]
        except Exception as error:
            if self.logger:
                self.logger.error(f"Error fetching today's appointments: {error}")
            raise HTTPException(
                status_code=500, detail="Failed to fetch appointments"
            )

    def create_appointment(
        self,
        db: Session,
        payload,
        background_tasks: BackgroundTasks,
    ) -> dict:
        try:
            appointment_date = date.fromisoformat(payload.date)
        except ValueError:
            raise HTTPException(
                status_code=400, detail="Invalid date format, use YYYY-MM-DD"
            )

        patient_id = str(payload.patient_id)
        appointment = self.repository.create(
            db,
            models.Appointment(
                id=str(uuid.uuid4()),
                patient_id=patient_id,
                date=appointment_date,
                time=payload.time,
                type=normalize_appointment_type(payload.type),
                status=normalize_appointment_status(payload.status),
                condition=payload.condition
                if payload.condition
                else "Routine Checkup",
            ),
        )
        patient = self.repository.get_patient_by_id(db, payload.patient_id)
        if self.reminder_callable:
            background_tasks.add_task(self.reminder_callable, appointment.id)
        return self._serialize(
            appointment, patient.name if patient else "Unknown"
        )

    def update_status(
        self,
        db: Session,
        appointment_id: Union[int, str],
        status_update: dict,
    ) -> dict:
        appointment = self.repository.get_by_id(db, appointment_id)
        if not appointment:
            raise HTTPException(status_code=404, detail="Appointment not found")

        new_status = status_update.get("status")
        if new_status:
            old_status = str(appointment.status)
            appointment.status = normalize_appointment_status(new_status)
            if new_status.lower() == "arrived" and old_status.lower() != "arrived":
                patient_name = (
                    appointment.patient.name if appointment.patient else "A patient"
                )
                self.repository.add(
                    db,
                    models.Notification(
                        id=str(uuid.uuid4()),
                        title="Patient Arrived",
                        body=f"{patient_name} has arrived for their {appointment.time} appointment.",
                        type="success",
                        read=0,
                    ),
                )
            appointment = self.repository.update(db, appointment)
        return {"status": "success", "new_status": appointment.status}

    def update_appointment(
        self,
        db: Session,
        appointment_id: Union[int, str],
        payload: dict,
        user,
    ) -> dict:
        appointment = self.repository.get_by_id(db, appointment_id)
        if not appointment:
            raise HTTPException(status_code=404, detail="Appointment not found")

        if "date" in payload:
            try:
                appointment.date = date.fromisoformat(payload["date"])
            except ValueError:
                raise HTTPException(status_code=400, detail="Invalid date format")
        if "time" in payload:
            appointment.time = payload["time"]
        if "type" in payload:
            appointment.type = normalize_appointment_type(payload["type"])
        if "status" in payload:
            appointment.status = normalize_appointment_status(payload["status"])
        if "notes" in payload:
            appointment.notes = payload.get("notes", "")
        if "condition" in payload:
            appointment.condition = payload["condition"]

        appointment_key = str(appointment_id)
        if self.audit_logger:
            self.audit_logger(
                db,
                f"Appointment {appointment_key} updated by {user.username}",
                doctor_id=user.id,
                patient_id=appointment.patient_id,
            )
        appointment = self.repository.update(db, appointment)
        patient = self.repository.get_patient_by_id(db, appointment.patient_id)
        response = self._serialize(
            appointment, patient.name if patient else "Unknown"
        )
        response["notes"] = getattr(appointment, "notes", "")
        return response

    def delete_appointment(
        self, db: Session, appointment_id: Union[int, str]
    ) -> dict:
        appointment = self.repository.get_by_id(db, appointment_id)
        if not appointment:
            raise HTTPException(status_code=404, detail="Appointment not found")
        self.repository.delete(db, appointment)
        return {"status": "success"}

    def finish_by_patient(
        self, db: Session, patient_id: Union[int, str], user
    ) -> dict:
        patient_key = str(patient_id)
        appointment = self.repository.get_active_by_patient_id(
            db, patient_id, date.today()
        )
        if not appointment:
            raise HTTPException(
                status_code=404,
                detail="No active appointment found for this patient today",
            )
        appointment.status = "completed"
        if self.audit_logger:
            self.audit_logger(
                db,
                f"Clinical session finished for patient {patient_key}",
                doctor_id=user.id,
                patient_id=patient_key,
            )
        self.repository.commit(db)
        return {"status": "success"}

    def finish_by_id(
        self, db: Session, appointment_id: Union[int, str], user
    ) -> dict:
        appointment_key = str(appointment_id)
        appointment = self.repository.get_by_id(db, appointment_id)
        if not appointment:
            raise HTTPException(status_code=404, detail="Appointment not found")
        appointment.status = "completed"
        if self.audit_logger:
            self.audit_logger(
                db,
                f"Appointment {appointment_key} marked completed.",
                doctor_id=user.id,
            )
        self.repository.commit(db)
        return {"status": "success"}
