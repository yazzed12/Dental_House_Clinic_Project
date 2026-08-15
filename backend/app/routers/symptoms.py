from collections.abc import Callable

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.schemas.symptom import SymptomCreate
from app.services.symptom_service import SymptomService


def create_symptom_router(
    *, get_db_dependency: Callable, auth_dependency: Callable
) -> APIRouter:
    router = APIRouter()
    service = SymptomService()

    @router.get("/api/clinical/symptoms", dependencies=[Depends(auth_dependency)])
    def get_symptoms(db: Session = Depends(get_db_dependency)):
        return service.list_active(db)

    @router.post("/api/clinical/symptoms")
    def create_symptom(
        payload: SymptomCreate,
        db: Session = Depends(get_db_dependency),
        user=Depends(auth_dependency),
    ):
        return service.create(db, payload.name, user)

    return router
