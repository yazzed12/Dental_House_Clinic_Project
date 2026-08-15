from collections.abc import Callable

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.schemas.appointment import AppointmentConditionCreate
from app.schemas.common import ChatRequest, DiagnosisRequest, DiagnosisResponse, InsightResponse
from app.services.common_service import CommonService


def create_common_router(
    *,
    get_db_dependency: Callable,
    auth_dependency: Callable,
    staff_dependency: Callable,
    ai_factory: Callable,
    logger,
) -> APIRouter:
    router = APIRouter()
    service = CommonService(ai_factory=ai_factory, logger=logger)

    @router.get("/dashboard")
    def get_dashboard(db: Session = Depends(get_db_dependency), user=Depends(auth_dependency)):
        return service.dashboard(db)

    @router.get("/api/dashboard")
    def get_api_dashboard(db: Session = Depends(get_db_dependency), user=Depends(auth_dependency)):
        return service.dashboard(db)

    @router.get("/logs")
    def get_logs(db: Session = Depends(get_db_dependency), user=Depends(auth_dependency)):
        return service.logs(db)

    @router.get("/api/records")
    def get_records(db: Session = Depends(get_db_dependency), user=Depends(auth_dependency)):
        return service.records(db)

    @router.get("/api/appointment-conditions")
    def get_appointment_conditions(db: Session = Depends(get_db_dependency), user=Depends(auth_dependency)):
        return service.appointment_conditions(db)

    @router.post("/api/appointment-conditions")
    def create_appointment_condition(
        payload: AppointmentConditionCreate,
        db: Session = Depends(get_db_dependency),
        user=Depends(staff_dependency),
    ):
        return service.create_appointment_condition(db, payload, user)

    @router.get("/api/ai/insights", response_model=InsightResponse)
    async def get_ai_insights(db: Session = Depends(get_db_dependency), user=Depends(auth_dependency)):
        return await service.insights(db)

    @router.post("/api/ai/diagnosis", response_model=DiagnosisResponse)
    async def ai_diagnosis(payload: DiagnosisRequest, user=Depends(auth_dependency)):
        return await service.diagnosis(payload)

    @router.post("/api/ai/chat")
    async def ai_chat(
        request: ChatRequest,
        db: Session = Depends(get_db_dependency),
        user=Depends(auth_dependency),
    ):
        return await service.chat(db, request)

    @router.get("/")
    def health_check():
        return service.health()

    return router
