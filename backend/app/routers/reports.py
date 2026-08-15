from collections.abc import Callable

from fastapi import APIRouter, Depends
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.services.report_service import ReportService


def create_report_router(
    *,
    get_db_dependency: Callable,
    auth_dependency: Callable,
    doctor_dependency: Callable,
    pdf_generator: Callable,
    report_ai: Callable,
    humanize_ai: Callable,
    audit_logger: Callable,
    logger,
) -> APIRouter:
    router = APIRouter()
    service = ReportService(
        pdf_generator=pdf_generator,
        report_ai=report_ai,
        humanize_ai=humanize_ai,
        audit_logger=audit_logger,
        logger=logger,
    )

    @router.post("/api/ai/generate-report")
    async def generate_ai_report(
        payload: dict,
        db: Session = Depends(get_db_dependency),
        user=Depends(doctor_dependency),
    ):
        return await service.generate_ai_report(payload, user)

    @router.post("/api/ai/humanize-report")
    async def humanize_report(
        payload: dict,
        db: Session = Depends(get_db_dependency),
        user=Depends(doctor_dependency),
    ):
        return await service.humanize_report(payload)

    @router.post("/api/reports")
    def save_report(
        payload: dict,
        db: Session = Depends(get_db_dependency),
        user=Depends(doctor_dependency),
    ):
        return service.save_report(db, payload, user)

    @router.get("/api/reports/patient/{patient_id}")
    def get_patient_reports(
        patient_id: int | str,
        db: Session = Depends(get_db_dependency),
        user=Depends(auth_dependency),
    ):
        return service.get_patient_reports(db, patient_id)

    @router.get("/api/reports/{report_id}/download")
    def download_report(
        report_id: int | str,
        db: Session = Depends(get_db_dependency),
        user=Depends(auth_dependency),
    ):
        path, filename = service.prepare_download(db, report_id)
        return FileResponse(path=path, media_type="application/pdf", filename=filename)

    @router.put("/api/reports/{report_id}")
    def update_report(
        report_id: int | str,
        payload: dict,
        db: Session = Depends(get_db_dependency),
        user=Depends(doctor_dependency),
    ):
        return service.update_report(db, report_id, payload, user)

    return router
