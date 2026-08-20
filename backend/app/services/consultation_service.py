from collections.abc import Callable
import json

from fastapi import BackgroundTasks, HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.repositories.consultation_repository import ConsultationRepository


class ConsultationService:
    def __init__(
        self,
        repository: ConsultationRepository | None = None,
        audit_logger: Callable | None = None,
        report_generator: Callable | None = None,
        logger=None,
    ):
        self.repository = repository or ConsultationRepository()
        self.audit_logger = audit_logger
        self.report_generator = report_generator
        self.logger = logger

    @staticmethod
    def _serialize_prescription(prescription):
        if not prescription:
            return None
        return {
            "id": prescription.id,
            "consultationId": prescription.consultation_id,
            "status": prescription.status,
            "version": prescription.version,
            "approvedAt": prescription.approved_at.isoformat() if prescription.approved_at else None,
            "items": [{
                "id": item.id, "medicationId": item.medication_id,
                "position": item.position, "brandName": item.brand_name_snapshot,
                "genericName": item.generic_name_snapshot, "strength": item.strength_snapshot,
                "dosageForm": item.dosage_form_snapshot, "route": item.route_snapshot,
                "dose": item.dose_snapshot, "frequency": item.frequency_snapshot,
                "duration": item.duration_snapshot, "instructions": item.instructions_snapshot,
                "doctorNotes": item.doctor_notes_snapshot,
            } for item in sorted(prescription.items, key=lambda row: row.position)],
        }

    @staticmethod
    def _serialize_last_note(consultation):
        if not consultation:
            return None
        return {
            "consultationId": consultation.id,
            "sessionNote": consultation.session_note,
            "date": (
                consultation.last_updated.isoformat() + "Z"
                if consultation.last_updated
                else None
            ),
        }

    def _serialize_consultation(
        self, consultation, last_note=None, dental_state_version=None
    ) -> dict:
        response = {
            "consultationId": consultation.id,
            "patientId": consultation.patient_id,
            "doctorId": consultation.doctor_id,
            "appointmentId": consultation.appointment_id,
            "toothData": json.loads(consultation.data),
            "sessionNote": consultation.session_note,
            "version": consultation.version,
            "createdAt": (
                consultation.created_at.isoformat() + "Z"
                if consultation.created_at
                else None
            ),
            "lastUpdated": (
                consultation.last_updated.isoformat() + "Z"
                if consultation.last_updated
                else None
            ),
            "lastConsultationNote": self._serialize_last_note(last_note),
        }
        if dental_state_version is not None:
            response["dentalStateVersion"] = dental_state_version
        return response

    def get_consultation(self, db: Session, patient_id) -> dict:
        appointment = self.repository.get_active_appointment(db, patient_id)
        consultation = None
        if appointment:
            consultation = self.repository.get_for_appointment(db, appointment.id)
        else:
            consultation = self.repository.get_latest_by_patient_id(db, patient_id)
        dental_state = self.repository.get_dental_state(db, patient_id)
        dental_state_version = dental_state.version if dental_state else 0

        if not consultation:
            if appointment and self.repository.get_patient(db, patient_id):
                last_note = self.repository.get_latest_meaningful_note(
                    db, patient_id
                )
                inherited_data = dental_state.data if dental_state else "{}"
                return {
                    "consultationId": None,
                    "patientId": str(patient_id),
                    "doctorId": None,
                    "appointmentId": str(appointment.id),
                    "toothData": json.loads(inherited_data),
                    "sessionNote": None,
                    "version": 0,
                    "dentalStateVersion": dental_state_version,
                    "createdAt": None,
                    "lastUpdated": None,
                    "lastConsultationNote": self._serialize_last_note(last_note),
                }
            raise HTTPException(status_code=404, detail="Consultation not found")
        last_note = self.repository.get_latest_meaningful_note(
            db, patient_id, consultation.id
        )
        return self._serialize_consultation(
            consultation, last_note, dental_state_version
        )

    def save_consultation(
        self,
        db: Session,
        patient_id,
        payload,
        user,
        background_tasks: BackgroundTasks,
    ) -> dict:
        creating_dental_state = False
        try:
            pid = str(patient_id)
            appointment = self.repository.get_active_appointment(db, patient_id)
            dental_state = self.repository.get_dental_state_for_update(
                db, patient_id
            )
            current_dental_version = dental_state.version if dental_state else 0
            submitted_dental_version = payload.dentalStateVersion
            if submitted_dental_version is None:
                submitted_dental_version = 0
            consultation = (
                self.repository.get_for_appointment(db, appointment.id)
                if appointment
                else self.repository.get_latest_by_patient_id(db, patient_id)
            )
            before_state = None
            session_note_supplied = "sessionNote" in payload.model_fields_set
            data_json = json.dumps(payload.toothData)

            if consultation:
                if consultation.version != payload.version:
                    raise HTTPException(
                        status_code=409,
                        detail="Version conflict. Please refresh.",
                    )
                if submitted_dental_version != current_dental_version:
                    raise HTTPException(
                        status_code=409,
                        detail="Dental state version conflict. Please refresh.",
                    )
                before_state = json.loads(consultation.data)
                consultation = self.repository.update_data(
                    consultation,
                    data_json,
                    session_note_supplied=session_note_supplied,
                    session_note=payload.sessionNote,
                )
            else:
                if submitted_dental_version != current_dental_version:
                    raise HTTPException(
                        status_code=409,
                        detail="Dental state version conflict. Please refresh.",
                    )
                consultation = self.repository.create(
                    db,
                    pid,
                    data_json,
                    doctor_id=user.id,
                    appointment_id=appointment.id if appointment else None,
                    session_note=payload.sessionNote if session_note_supplied else None,
                )

            if dental_state:
                dental_state = self.repository.update_dental_state(
                    dental_state, data_json
                )
            else:
                creating_dental_state = True
                dental_state = self.repository.create_dental_state(
                    db, pid, data_json
                )

            consultation, dental_state = (
                self.repository.commit_consultation_and_dental_state(
                    db, consultation, dental_state
                )
            )
            self.audit_logger(
                db,
                f"Consultation updated for patient {pid}",
                doctor_id=user.id,
                patient_id=pid,
                before=before_state,
                after=payload.toothData,
            )
            background_tasks.add_task(self.report_generator, pid)
            last_note = self.repository.get_latest_meaningful_note(
                db, patient_id, consultation.id
            )
            response = {
                "status": "success",
                "version": consultation.version,
                "dentalStateVersion": dental_state.version,
                "consultationId": consultation.id,
                "appointmentId": consultation.appointment_id,
                "sessionNote": consultation.session_note,
                "lastConsultationNote": self._serialize_last_note(last_note),
            }
            return response
        except HTTPException:
            self.repository.rollback(db)
            raise
        except IntegrityError as error:
            self.repository.rollback(db)
            database_code = getattr(error.orig, "pgcode", None) or getattr(
                error.orig, "sqlstate", None
            )
            duplicate_state = (
                database_code == "23505"
                and "patient_dental_state" in str(error.orig)
            ) or "UNIQUE constraint failed: patient_dental_state.patient_id" in str(
                error.orig
            )
            if creating_dental_state and duplicate_state:
                raise HTTPException(
                    status_code=409,
                    detail="Dental state version conflict. Please refresh.",
                ) from error
            self.logger.error(
                "Error saving consultation (%s)", type(error).__name__
            )
            raise HTTPException(status_code=500, detail="Internal server error")
        except Exception as error:
            self.repository.rollback(db)
            self.logger.error(
                "Error saving consultation (%s)", type(error).__name__
            )
            raise HTTPException(status_code=500, detail="Internal server error")

    def get_patient_history(self, db: Session, patient_id) -> list[dict]:
        result = []
        for consultation in self.repository.get_history(db, patient_id):
            item = self._serialize_consultation(consultation)
            item["prescription"] = self._serialize_prescription(
                self.repository.get_approved_prescription(db, consultation.id)
            )
            result.append(item)
        return result

    def get_doctor_history(self, db: Session, user) -> list[dict]:
        reports = self.repository.get_doctor_history(db, user.id)
        response = []
        for report in reports:
            consultation = self.repository.find_session_for_report(db, report)
            response.append(
                {
                    "id": report.id,
                    "patient_id": report.patient_id,
                    "patient_name": report.patient.name if report.patient else "Unknown",
                    "doctor_id": report.doctor_id,
                    "tooth_id": report.tooth_id,
                    "tooth_status": report.tooth_status,
                    "symptoms": json.loads(report.symptoms) if report.symptoms else [],
                    "doctor_notes": report.doctor_notes,
                    "ai_draft_report": report.ai_draft_report,
                    "final_medical_report": report.final_medical_report,
                    "humanized_report": report.humanized_report,
                    "status": report.status,
                    "created_at": (
                        report.created_at.isoformat() + "Z"
                        if report.created_at
                        else None
                    ),
                    "updated_at": (
                        report.updated_at.isoformat() + "Z"
                        if report.updated_at
                        else None
                    ),
                    "consultationId": consultation.id if consultation else None,
                    "sessionNote": (
                        consultation.session_note if consultation else None
                    ),
                    "procedures": (
                        [
                            {
                                "id": row.id,
                                "name": row.procedure_name_snapshot,
                                "unitPrice": format(row.unit_price_snapshot, ".2f"),
                                "quantity": row.quantity,
                                "lineTotal": format(row.line_total, ".2f"),
                            }
                            for row in self.repository.list_procedures(db, consultation.id)
                        ]
                        if consultation else []
                    ),
                    "prescription": self._serialize_prescription(
                        self.repository.get_approved_prescription(db, consultation.id)
                        if consultation else None
                    ),
                }
            )
        return response
