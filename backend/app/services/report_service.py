from collections.abc import Callable
from datetime import datetime, timezone
import json
import os
import uuid

from fastapi import HTTPException
from sqlalchemy.orm import Session

import models
from app.repositories.report_repository import ReportRepository
from app.repositories.consultation_repository import ConsultationRepository


class ReportService:
    def __init__(
        self,
        *,
        repository: ReportRepository | None = None,
        consultation_repository: ConsultationRepository | None = None,
        pdf_generator: Callable,
        report_ai: Callable,
        humanize_ai: Callable,
        audit_logger: Callable,
        logger,
        path_exists: Callable[[str], bool] = os.path.exists,
    ):
        self.repository = repository or ReportRepository()
        self.consultation_repository = (
            consultation_repository or ConsultationRepository()
        )
        self.pdf_generator = pdf_generator
        self.report_ai = report_ai
        self.humanize_ai = humanize_ai
        self.audit_logger = audit_logger
        self.logger = logger
        self.path_exists = path_exists

    async def generate_ai_report(self, payload: dict, user) -> dict:
        try:
            authoritative_payload = dict(payload)
            authoritative_payload["doctor"] = {
                "name": (getattr(user, "full_name", None) or "").strip() or None,
                "specialty": (
                    getattr(user, "specialization", None) or ""
                ).strip() or None,
            }
            authoritative_payload["reportDate"] = datetime.now(
                timezone.utc
            ).date().isoformat()
            report_text = await self.report_ai(authoritative_payload)
            return {"status": "success", "report": report_text}
        except Exception as error:
            self.logger.error(f"AI Report Generation Error: {error}")
            raise HTTPException(
                status_code=500,
                detail=f"AI report generation failed: {str(error)}",
            )

    async def humanize_report(self, payload: dict) -> dict:
        medical_report = payload.get("report", "")
        patient_name = payload.get("patient_name", "Patient")
        if not medical_report:
            raise HTTPException(status_code=400, detail="Report text is required")
        try:
            humanized = await self.humanize_ai(medical_report, patient_name)
            return {"status": "success", "humanized_report": humanized}
        except Exception as error:
            self.logger.error(f"Report Humanization Error: {error}")
            raise HTTPException(
                status_code=500, detail=f"Humanization failed: {str(error)}"
            )

    def save_report(self, db: Session, payload: dict, user) -> dict:
        patient_id = payload.get("patient_id")
        if patient_id is None or not str(patient_id).strip():
            raise HTTPException(status_code=400, detail="patient_id is required")

        appointment = self.consultation_repository.get_active_appointment(
            db, patient_id
        )
        appointment_id = payload.get("appointment_id")
        if appointment:
            if appointment_id is not None and str(appointment_id) != str(appointment.id):
                raise HTTPException(
                    status_code=409,
                    detail="Report does not match the active consultation session.",
                )
            appointment_id = appointment.id
            consultation = self.consultation_repository.get_for_appointment(
                db, appointment.id
            )
            if consultation is None:
                dental_state = self.consultation_repository.get_dental_state(
                    db, patient_id
                )
                inherited_data = dental_state.data if dental_state else "{}"
                consultation = self.consultation_repository.create(
                    db,
                    str(patient_id),
                    inherited_data,
                    doctor_id=user.id,
                    appointment_id=appointment.id,
                )
                self.consultation_repository.commit(db, consultation)

        report = models.ClinicalReport(
            id=str(uuid.uuid4()),
            patient_id=str(patient_id),
            doctor_id=user.id,
            appointment_id=(
                str(appointment_id) if appointment_id is not None else None
            ),
            tooth_id=payload.get("tooth_id"),
            tooth_status=payload.get("tooth_status"),
            symptoms=json.dumps(payload.get("symptoms", [])),
            doctor_notes=payload.get("doctor_notes", ""),
            ai_draft_report=payload.get("ai_draft_report", ""),
            final_medical_report=payload.get("final_medical_report", ""),
            humanized_report=payload.get("humanized_report", ""),
            status=payload.get("status", "approved"),
        )
        self.repository.add(db, report)
        self.audit_logger(
            db,
            f"Clinical report saved for patient {payload.get('patient_id')}",
            doctor_id=user.id,
            patient_id=payload.get("patient_id"),
        )
        report = self.repository.commit(db, report)
        self.pdf_generator(report, db)
        return {
            "id": report.id,
            "patient_id": report.patient_id,
            "status": report.status,
            "tooth_id": report.tooth_id,
            "created_at": (
                report.created_at.isoformat() + "Z" if report.created_at else None
            ),
        }

    def get_patient_reports(self, db: Session, patient_id) -> list[dict]:
        reports = self.repository.get_by_patient_id(db, patient_id)
        return [self._serialize_patient_report(report) for report in reports]

    def prepare_download(self, db: Session, report_id) -> tuple[str, str]:
        report = self.repository.get_by_id(db, report_id)
        if not report:
            raise HTTPException(status_code=404, detail="Clinical report not found")
        if not report.pdf_path or not self.path_exists(report.pdf_path):
            self.pdf_generator(report, db)
        if not report.pdf_path or not self.path_exists(report.pdf_path):
            raise HTTPException(
                status_code=404,
                detail="PDF file could not be generated on this server",
            )
        patient_name = report.patient.name if report.patient else "Patient"
        clean_name = "".join(
            char
            for char in patient_name
            if char.isalnum() or char in (" ", "_", "-")
        ).strip()
        filename = f"Clinical_Report_{clean_name}_{report.tooth_id or 'General'}.pdf"
        return report.pdf_path, filename

    def update_report(self, db: Session, report_id, payload: dict, user) -> dict:
        report = self.repository.get_by_id(db, report_id)
        if not report:
            raise HTTPException(status_code=404, detail="Report not found")
        if str(report.doctor_id) != str(user.id):
            raise HTTPException(
                status_code=403, detail="Not authorized to edit this report"
            )
        for field in (
            "final_medical_report",
            "humanized_report",
            "status",
            "doctor_notes",
            "tooth_id",
            "tooth_status",
            "symptoms",
        ):
            if field in payload:
                value = (
                    json.dumps(payload[field])
                    if field == "symptoms" and isinstance(payload[field], list)
                    else payload[field]
                )
                setattr(report, field, value)
        report = self.repository.commit(db, report)
        self.pdf_generator(report, db)
        return {
            "id": report.id,
            "status": report.status,
            "updated_at": (
                report.updated_at.isoformat() + "Z" if report.updated_at else None
            ),
        }

    @staticmethod
    def _serialize_patient_report(report) -> dict:
        return {
            "id": report.id,
            "patient_id": report.patient_id,
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
                report.created_at.isoformat() + "Z" if report.created_at else None
            ),
            "updated_at": (
                report.updated_at.isoformat() + "Z" if report.updated_at else None
            ),
            "doctor": (
                report.doctor.full_name or report.doctor.username
                if report.doctor
                else "Unknown"
            ),
            "pdf_url": (
                f"/api/reports/{report.id}/download" if report.pdf_path else None
            ),
        }
