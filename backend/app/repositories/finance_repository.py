import uuid

from sqlalchemy import func, inspect
from sqlalchemy.orm import Session

import models


class FinanceRepository:
    @staticmethod
    def schema_available(db: Session) -> bool:
        inspector = inspect(db.get_bind())
        tables = set(inspector.get_table_names())
        if not {"clinic_procedures", "consultation_procedures"} <= tables:
            return False
        consultation_columns = {
            column["name"] for column in inspector.get_columns("consultations")
        }
        return "procedures_version" in consultation_columns

    @staticmethod
    def ledger_schema_available(db: Session) -> bool:
        inspector = inspect(db.get_bind())
        tables = set(inspector.get_table_names())
        if not {
            "financial_payment_records",
            "financial_payment_allocations",
            "financial_charge_adjustments",
        } <= tables:
            return False
        return "billing_version" in {
            column["name"] for column in inspector.get_columns("consultations")
        }

    def list_procedures(self, db: Session, *, active_only: bool = False):
        query = db.query(models.ClinicProcedure)
        if active_only:
            query = query.filter(models.ClinicProcedure.is_active.is_(True))
        return query.order_by(models.ClinicProcedure.name.asc()).all()

    def get_procedure(self, db: Session, procedure_id: str):
        return db.query(models.ClinicProcedure).filter(models.ClinicProcedure.id == procedure_id).first()

    def get_procedure_by_name(self, db: Session, name: str):
        return db.query(models.ClinicProcedure).filter(func.lower(models.ClinicProcedure.name) == name.strip().lower()).first()

    def create_procedure(self, db: Session, *, name: str, price):
        row = models.ClinicProcedure(id=str(uuid.uuid4()), name=name, price=price, is_active=True)
        db.add(row)
        db.commit()
        db.refresh(row)
        return row

    def get_consultation(self, db: Session, patient_id):
        from app.repositories.consultation_repository import ConsultationRepository
        repository = ConsultationRepository()
        appointment = repository.get_active_appointment(db, patient_id)
        consultation = repository.get_for_appointment(db, appointment.id) if appointment else repository.get_latest_by_patient_id(db, patient_id)
        return consultation, appointment

    def get_consultation_for_update(self, db: Session, consultation_id: str):
        return db.query(models.Consultation).filter(models.Consultation.id == consultation_id).with_for_update().first()

    def list_consultation_procedures(self, db: Session, consultation_id: str):
        return db.query(models.ConsultationProcedure).filter(models.ConsultationProcedure.consultation_id == consultation_id).order_by(models.ConsultationProcedure.created_at.asc(), models.ConsultationProcedure.id.asc()).all()

    def replace_consultation_procedures(self, db: Session, consultation_id: str, rows):
        db.query(models.ConsultationProcedure).filter(models.ConsultationProcedure.consultation_id == consultation_id).delete(synchronize_session=False)
        db.add_all(rows)

    def list_billing_consultations(self, db: Session, patient_id=None):
        query = db.query(models.Consultation).join(
            models.ConsultationProcedure,
            models.ConsultationProcedure.consultation_id == models.Consultation.id,
        )
        if patient_id is not None:
            query = query.filter(models.Consultation.patient_id == patient_id)
        return query.distinct().order_by(models.Consultation.created_at.desc(), models.Consultation.id.desc()).all()

    def get_consultation_by_id(self, db: Session, consultation_id, *, for_update=False):
        query = db.query(models.Consultation).filter(models.Consultation.id == consultation_id)
        if for_update:
            query = query.with_for_update()
        return query.first()

    def get_patient(self, db: Session, patient_id):
        return db.query(models.Patient).filter(models.Patient.id == patient_id).first()

    def list_adjustments(self, db: Session, procedure_ids):
        if not procedure_ids:
            return []
        return db.query(models.FinancialChargeAdjustment).filter(
            models.FinancialChargeAdjustment.consultation_procedure_id.in_(procedure_ids)
        ).order_by(models.FinancialChargeAdjustment.created_at.asc(), models.FinancialChargeAdjustment.id.asc()).all()

    def list_payment_records(self, db: Session, consultation_ids):
        if not consultation_ids:
            return []
        return db.query(models.FinancialPaymentRecord).filter(
            models.FinancialPaymentRecord.consultation_id.in_(consultation_ids)
        ).order_by(
            models.FinancialPaymentRecord.paid_at.asc(),
            models.FinancialPaymentRecord.payment_id.asc(),
            models.FinancialPaymentRecord.revision_number.asc(),
        ).all()

    def list_allocations(self, db: Session, payment_record_ids):
        if not payment_record_ids:
            return []
        return db.query(models.FinancialPaymentAllocation).filter(
            models.FinancialPaymentAllocation.payment_record_id.in_(payment_record_ids)
        ).all()

    def get_latest_payment_record(self, db: Session, payment_id):
        return db.query(models.FinancialPaymentRecord).filter(
            models.FinancialPaymentRecord.payment_id == payment_id
        ).order_by(models.FinancialPaymentRecord.revision_number.desc()).with_for_update().first()

    def add_payment_record(self, db: Session, row):
        db.add(row)
        db.flush()
        return row

    def add_allocations(self, db: Session, rows):
        db.add_all(rows)
        db.flush()

    def has_payment_history(self, db: Session, consultation_id):
        return db.query(models.FinancialPaymentRecord.id).filter(
            models.FinancialPaymentRecord.consultation_id == consultation_id
        ).first() is not None
