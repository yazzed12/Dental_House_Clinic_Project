from collections.abc import Callable

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.schemas.finance import ConsultationProceduresSave, PaymentCorrection, PaymentCreate, ProcedureCreate, ProcedureUpdate
from app.services.finance_service import FinanceService
from app.finance.capabilities import (
    BILLING_READ, CATALOG_MANAGE, CATALOG_READ, PATIENT_HISTORY_READ,
    PAYMENT_CORRECT, PAYMENT_RECORD, require_finance_capability,
)


def create_finance_router(*, get_db_dependency: Callable, authenticated_dependency: Callable) -> APIRouter:
    router = APIRouter()
    service = FinanceService()
    catalog_read = require_finance_capability(CATALOG_READ, authenticated_dependency)
    catalog_manage = require_finance_capability(CATALOG_MANAGE, authenticated_dependency)
    billing_read = require_finance_capability(BILLING_READ, authenticated_dependency)
    payment_record = require_finance_capability(PAYMENT_RECORD, authenticated_dependency)
    payment_correct = require_finance_capability(PAYMENT_CORRECT, authenticated_dependency)
    history_read = require_finance_capability(PATIENT_HISTORY_READ, authenticated_dependency)

    @router.get("/api/clinic-procedures")
    def list_procedures(active_only: bool = Query(False), db: Session = Depends(get_db_dependency), user=Depends(catalog_read)):
        return service.list_procedures(db, active_only)

    @router.post("/api/clinic-procedures", status_code=201)
    def create_procedure(payload: ProcedureCreate, db: Session = Depends(get_db_dependency), user=Depends(catalog_manage)):
        return service.create_procedure(db, payload)

    @router.patch("/api/clinic-procedures/{procedure_id}")
    def update_procedure(procedure_id: str, payload: ProcedureUpdate, db: Session = Depends(get_db_dependency), user=Depends(catalog_manage)):
        return service.update_procedure(db, procedure_id, payload)

    @router.get("/api/consultations/{patient_id}/procedures")
    def get_consultation_procedures(patient_id: str, db: Session = Depends(get_db_dependency), user=Depends(billing_read)):
        return service.get_selections(db, patient_id)

    @router.put("/api/consultations/{patient_id}/procedures")
    def save_consultation_procedures(patient_id: str, payload: ConsultationProceduresSave, db: Session = Depends(get_db_dependency), user=Depends(catalog_manage)):
        return service.save_selections(db, patient_id, payload, user)

    @router.get("/api/finance/billing")
    def list_billing(db: Session = Depends(get_db_dependency), user=Depends(billing_read)):
        return service.list_billing(db)

    @router.get("/api/finance/patient-summaries")
    def patient_summaries(db: Session = Depends(get_db_dependency), user=Depends(history_read)):
        return service.patient_summaries(db)

    @router.get("/api/finance/patients/{patient_id}/history")
    def patient_history(patient_id: str, db: Session = Depends(get_db_dependency), user=Depends(history_read)):
        return service.patient_history(db, patient_id)

    @router.get("/api/finance/patients/{patient_id}/outstanding")
    def patient_outstanding(patient_id: str, db: Session = Depends(get_db_dependency), user=Depends(history_read)):
        return service.patient_outstanding(db, patient_id)

    @router.post("/api/finance/consultations/{consultation_id}/payments", status_code=201)
    def add_payment(consultation_id: str, payload: PaymentCreate, db: Session = Depends(get_db_dependency), user=Depends(payment_record)):
        return service.add_payment(db, consultation_id, payload, user)

    @router.post("/api/finance/payments/{payment_id}/corrections", status_code=201)
    def correct_payment(payment_id: str, payload: PaymentCorrection, db: Session = Depends(get_db_dependency), user=Depends(payment_correct)):
        return service.correct_payment(db, payment_id, payload, user)

    return router
