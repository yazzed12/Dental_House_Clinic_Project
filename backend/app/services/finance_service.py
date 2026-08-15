import json
import uuid
from decimal import Decimal
from collections import defaultdict

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

import models
from app.repositories.finance_repository import FinanceRepository
from app.repositories.consultation_repository import ConsultationRepository


class FinanceService:
    def __init__(self, repository=None):
        self.repository = repository or FinanceRepository()

    @staticmethod
    def _money(value) -> str:
        return format(Decimal(value).quantize(Decimal("0.01")), ".2f")

    @staticmethod
    def _payment_sort_key(row):
        return (row.paid_at.isoformat(), str(row.payment_id))

    def ensure_schema(self, db: Session) -> None:
        if not self.repository.schema_available(db):
            raise HTTPException(
                status_code=503,
                detail=(
                    "Phase F1 financial schema is not installed. "
                    "Apply migration 003 before enabling financial features."
                ),
            )

    def ensure_ledger_schema(self, db: Session) -> None:
        if not self.repository.ledger_schema_available(db):
            raise HTTPException(503, "Financial ledger schema is not installed. Apply migration 004 before enabling Billing.")

    def serialize_procedure(self, row):
        return {"id": row.id, "name": row.name, "price": self._money(row.price), "isActive": bool(row.is_active), "createdAt": row.created_at.isoformat() + "Z" if row.created_at else None, "updatedAt": row.updated_at.isoformat() + "Z" if row.updated_at else None}

    def list_procedures(self, db, active_only=False):
        self.ensure_schema(db)
        return [self.serialize_procedure(row) for row in self.repository.list_procedures(db, active_only=active_only)]

    def create_procedure(self, db, payload):
        self.ensure_schema(db)
        name = payload.name.strip()
        if not name:
            raise HTTPException(400, "Procedure name cannot be empty")
        if self.repository.get_procedure_by_name(db, name):
            raise HTTPException(409, "A procedure with this name already exists")
        try:
            return self.serialize_procedure(self.repository.create_procedure(db, name=name, price=payload.price))
        except IntegrityError as error:
            db.rollback()
            raise HTTPException(409, "A procedure with this name already exists") from error

    def update_procedure(self, db, procedure_id, payload):
        self.ensure_schema(db)
        row = self.repository.get_procedure(db, procedure_id)
        if not row:
            raise HTTPException(404, "Procedure not found")
        if payload.name is not None:
            name = payload.name.strip()
            if not name:
                raise HTTPException(400, "Procedure name cannot be empty")
            duplicate = self.repository.get_procedure_by_name(db, name)
            if duplicate and duplicate.id != row.id:
                raise HTTPException(409, "A procedure with this name already exists")
            row.name = name
        if payload.price is not None:
            row.price = payload.price
        if payload.is_active is not None:
            row.is_active = payload.is_active
        try:
            db.commit()
            db.refresh(row)
        except IntegrityError as error:
            db.rollback()
            raise HTTPException(409, "A procedure with this name already exists") from error
        return self.serialize_procedure(row)

    def serialize_selection(self, row):
        return {"id": row.id, "procedureId": row.procedure_id, "name": row.procedure_name_snapshot, "unitPrice": self._money(row.unit_price_snapshot), "quantity": row.quantity, "lineTotal": self._money(row.line_total)}

    def get_selections(self, db, patient_id):
        self.ensure_schema(db)
        consultation, _ = self.repository.get_consultation(db, patient_id)
        if not consultation:
            return {"consultationId": None, "version": 0, "items": [], "total": "0.00"}
        rows = self.repository.list_consultation_procedures(db, consultation.id)
        adjustments = self.repository.list_adjustments(db, [row.id for row in rows]) if self.repository.ledger_schema_available(db) else []
        reductions = defaultdict(int)
        for adjustment in adjustments:
            reductions[adjustment.consultation_procedure_id] += adjustment.quantity_delta
        items = []
        total = Decimal("0.00")
        for row in rows:
            quantity = row.quantity - reductions[row.id]
            if quantity <= 0:
                continue
            line_total = Decimal(row.unit_price_snapshot) * quantity
            total += line_total
            items.append({"id": row.id, "procedureId": row.procedure_id, "name": row.procedure_name_snapshot, "unitPrice": self._money(row.unit_price_snapshot), "quantity": quantity, "lineTotal": self._money(line_total)})
        return {"consultationId": consultation.id, "version": consultation.procedures_version or 0, "items": items, "total": self._money(total)}

    def save_selections(self, db: Session, patient_id, payload, user):
        self.ensure_schema(db)
        ids = [item.procedureId for item in payload.selections]
        if len(ids) != len(set(ids)):
            raise HTTPException(400, "Each procedure may appear only once; use quantity")
        try:
            consultation, appointment = self.repository.get_consultation(db, patient_id)
            if consultation:
                consultation = self.repository.get_consultation_for_update(db, consultation.id)
            else:
                patient = ConsultationRepository.get_patient(db, patient_id)
                if not patient:
                    raise HTTPException(404, "Patient not found")
                dental_state = ConsultationRepository.get_dental_state(db, patient_id)
                consultation = ConsultationRepository.create(db, str(patient_id), dental_state.data if dental_state else "{}", doctor_id=user.id, appointment_id=appointment.id if appointment else None)
                consultation.procedures_version = 0
                db.flush()
            if (consultation.procedures_version or 0) != payload.version:
                raise HTTPException(409, "Procedure selection version conflict. Refresh and try again.")
            existing_rows = {
                row.procedure_id: row
                for row in self.repository.list_consultation_procedures(db, consultation.id)
            }
            catalog = {row.id: row for row in self.repository.list_procedures(db)}
            missing = [
                item.procedureId
                for item in payload.selections
                if item.procedureId not in catalog
                or (not catalog[item.procedureId].is_active and item.procedureId not in existing_rows)
            ]
            if missing:
                raise HTTPException(400, "One or more procedures are inactive or unavailable")
            rows = []
            has_financial_history = self.repository.has_payment_history(db, consultation.id)
            desired = {item.procedureId: item.quantity for item in payload.selections}
            if has_financial_history:
                adjustment_rows = self.repository.list_adjustments(db, [row.id for row in existing_rows.values()])
                reductions = defaultdict(int)
                for adjustment in adjustment_rows:
                    reductions[adjustment.consultation_procedure_id] += adjustment.quantity_delta
                changed = False
                for procedure_id, previous in existing_rows.items():
                    current_quantity = previous.quantity - reductions[previous.id]
                    target_quantity = desired.get(procedure_id, 0)
                    delta = current_quantity - target_quantity
                    if delta:
                        db.add(models.FinancialChargeAdjustment(
                            id=str(uuid.uuid4()), consultation_procedure_id=previous.id,
                            quantity_delta=delta, unit_price_snapshot=previous.unit_price_snapshot,
                            reason="Procedure quantity corrected after payment history",
                            created_by=user.id,
                        ))
                        changed = True
                for item in payload.selections:
                    if item.procedureId not in existing_rows:
                        procedure = catalog[item.procedureId]
                        rows.append(models.ConsultationProcedure(
                            id=str(uuid.uuid4()), consultation_id=consultation.id,
                            procedure_id=procedure.id, procedure_name_snapshot=procedure.name,
                            unit_price_snapshot=Decimal(procedure.price).quantize(Decimal("0.01")),
                            quantity=item.quantity,
                        ))
                        changed = True
                db.add_all(rows)
                if changed:
                    db.flush()
                    self._rebalance(db, consultation, user.id, None)
                    consultation.billing_version = (consultation.billing_version or 0) + 1
            else:
                for item in payload.selections:
                    procedure = catalog[item.procedureId]
                    previous = existing_rows.get(item.procedureId)
                    unit_price = Decimal(previous.unit_price_snapshot if previous else procedure.price).quantize(Decimal("0.01"))
                    snapshot_name = previous.procedure_name_snapshot if previous else procedure.name
                    rows.append(models.ConsultationProcedure(id=str(uuid.uuid4()), consultation_id=consultation.id, procedure_id=procedure.id, procedure_name_snapshot=snapshot_name, unit_price_snapshot=unit_price, quantity=item.quantity))
                self.repository.replace_consultation_procedures(db, consultation.id, rows)
            consultation.procedures_version = (consultation.procedures_version or 0) + 1
            db.commit()
            return self.get_selections(db, patient_id)
        except HTTPException:
            db.rollback()
            raise

    @staticmethod
    def _latest_records(records):
        latest = {}
        for row in records:
            current = latest.get(row.payment_id)
            if current is None or row.revision_number > current.revision_number:
                latest[row.payment_id] = row
        return list(latest.values())

    def _effective_items(self, db, consultation):
        rows = self.repository.list_consultation_procedures(db, consultation.id)
        adjustments = self.repository.list_adjustments(db, [row.id for row in rows])
        reductions = defaultdict(int)
        for adjustment in adjustments:
            reductions[adjustment.consultation_procedure_id] += adjustment.quantity_delta
        items = []
        for row in rows:
            quantity = row.quantity - reductions[row.id]
            line_total = Decimal(row.unit_price_snapshot) * quantity
            if quantity > 0:
                items.append({
                    "id": row.id, "procedureId": row.procedure_id,
                    "name": row.procedure_name_snapshot, "quantity": quantity,
                    "unitPrice": self._money(row.unit_price_snapshot),
                    "lineTotal": self._money(line_total), "_amount": line_total,
                    "_createdAt": row.created_at,
                })
        items.sort(key=lambda item: (item["_createdAt"], str(item["id"])))
        return items

    def _consultation_projection(self, db, consultation, records=None):
        patient = self.repository.get_patient(db, consultation.patient_id)
        items = self._effective_items(db, consultation)
        billed = sum((item["_amount"] for item in items), Decimal("0.00"))
        all_records = records if records is not None else self.repository.list_payment_records(db, [consultation.id])
        latest = sorted(self._latest_records(all_records), key=self._payment_sort_key)
        paid = sum((Decimal(row.amount) for row in latest), Decimal("0.00"))
        remaining_payment = paid
        outstanding = []
        for item in items:
            covered = min(item["_amount"], remaining_payment)
            remaining_payment -= covered
            due = item["_amount"] - covered
            if due > 0:
                outstanding.append({"procedureId": item["id"], "name": item["name"], "remaining": self._money(due)})
        public_items = [{key: value for key, value in item.items() if not key.startswith("_")} for item in items]
        payments = [{
            "paymentId": row.payment_id, "revision": row.revision_number,
            "amount": self._money(row.amount), "paidAt": row.paid_at.isoformat(),
            "corrected": row.revision_number > 1,
            "correctionReason": row.correction_reason,
        } for row in latest]
        return {
            "consultationId": consultation.id,
            "consultationReference": str(consultation.id),
            "consultationDate": consultation.created_at.isoformat() if consultation.created_at else None,
            "appointmentId": consultation.appointment_id,
            "patient": {"id": consultation.patient_id, "name": patient.name if patient else "Unknown"},
            "billingVersion": consultation.billing_version or 0,
            "procedures": public_items, "payments": payments,
            "billedTotal": self._money(billed), "paidTotal": self._money(paid),
            "balance": self._money(paid - billed),
            "outstandingTotal": self._money(max(billed - paid, Decimal("0.00"))),
            "creditTotal": self._money(max(paid - billed, Decimal("0.00"))),
            "outstandingItems": outstanding,
        }

    def list_billing(self, db):
        self.ensure_ledger_schema(db)
        consultations = self.repository.list_billing_consultations(db)
        records = self.repository.list_payment_records(db, [row.id for row in consultations])
        by_consultation = defaultdict(list)
        for row in records:
            by_consultation[row.consultation_id].append(row)
        return [self._consultation_projection(db, row, by_consultation[row.id]) for row in consultations]

    def patient_history(self, db, patient_id):
        self.ensure_ledger_schema(db)
        patient = self.repository.get_patient(db, patient_id)
        if not patient:
            raise HTTPException(404, "Patient not found")
        consultations = self.repository.list_billing_consultations(db, patient_id)
        records = self.repository.list_payment_records(db, [row.id for row in consultations])
        by_consultation = defaultdict(list)
        for row in records:
            by_consultation[row.consultation_id].append(row)
        cards = [self._consultation_projection(db, row, by_consultation[row.id]) for row in consultations]
        billed = sum((Decimal(card["billedTotal"]) for card in cards), Decimal("0.00"))
        paid = sum((Decimal(card["paidTotal"]) for card in cards), Decimal("0.00"))
        return {"patient": {"id": patient.id, "name": patient.name}, "billedTotal": self._money(billed), "paidTotal": self._money(paid), "balance": self._money(paid - billed), "outstandingTotal": self._money(max(billed - paid, Decimal("0.00"))), "creditTotal": self._money(max(paid - billed, Decimal("0.00"))), "consultations": cards}

    def patient_outstanding(self, db, patient_id):
        history = self.patient_history(db, patient_id)
        items = []
        for card in history["consultations"]:
            for item in card["outstandingItems"]:
                items.append({**item, "consultationId": card["consultationId"], "consultationReference": card["consultationReference"], "consultationDate": card["consultationDate"]})
        return {"patient": history["patient"], "totalOutstanding": history["outstandingTotal"], "items": items}

    def patient_summaries(self, db):
        self.ensure_ledger_schema(db)
        consultations = self.repository.list_billing_consultations(db)
        patient_ids = {row.patient_id for row in consultations}
        return {str(patient_id): self.patient_outstanding(db, patient_id) for patient_id in patient_ids}

    def _desired_allocations(self, db, consultation, records):
        items = self._effective_items(db, consultation)
        remaining = {item["id"]: item["_amount"] for item in items}
        desired = {}
        for record in sorted(records, key=self._payment_sort_key):
            amount = Decimal(record.amount)
            allocations = []
            for item in items:
                value = min(remaining[item["id"]], amount)
                if value > 0:
                    allocations.append((item["id"], value))
                    remaining[item["id"]] -= value
                    amount -= value
                if amount <= 0:
                    break
            desired[record.id] = allocations
        return desired

    def _insert_allocations(self, db, record, values):
        self.repository.add_allocations(db, [models.FinancialPaymentAllocation(id=str(uuid.uuid4()), payment_record_id=record.id, consultation_procedure_id=procedure_id, allocated_amount=amount) for procedure_id, amount in values])

    def _rebalance(self, db, consultation, actor_id, newly_inserted=None):
        records = self.repository.list_payment_records(db, [consultation.id])
        current = sorted(self._latest_records(records), key=self._payment_sort_key)
        desired = self._desired_allocations(db, consultation, current)
        existing_allocations = self.repository.list_allocations(db, [row.id for row in current])
        existing = defaultdict(list)
        for row in existing_allocations:
            existing[row.payment_record_id].append((row.consultation_procedure_id, Decimal(row.allocated_amount)))
        for record in current:
            wanted = desired[record.id]
            if sorted(existing[record.id]) == sorted(wanted):
                continue
            target = record
            if (newly_inserted is None or record.id != newly_inserted.id) and existing[record.id]:
                target = models.FinancialPaymentRecord(
                    id=str(uuid.uuid4()), payment_id=record.payment_id,
                    consultation_id=record.consultation_id,
                    revision_number=record.revision_number + 1,
                    amount=record.amount, paid_at=record.paid_at,
                    correction_reason="Automatic allocation rebalance",
                    created_by=actor_id,
                )
                self.repository.add_payment_record(db, target)
            self._insert_allocations(db, target, wanted)

    def add_payment(self, db, consultation_id, payload, user):
        self.ensure_ledger_schema(db)
        try:
            consultation = self.repository.get_consultation_by_id(db, consultation_id, for_update=True)
            if not consultation:
                raise HTTPException(404, "Consultation not found")
            if (consultation.billing_version or 0) != payload.billingVersion:
                raise HTTPException(409, "Billing version conflict. Refresh and try again.")
            if not self.repository.list_consultation_procedures(db, consultation.id):
                raise HTTPException(400, "Consultation has no billed procedures")
            record = models.FinancialPaymentRecord(id=str(uuid.uuid4()), payment_id=str(uuid.uuid4()), consultation_id=consultation.id, revision_number=1, amount=payload.amount, paid_at=payload.paidAt, correction_reason=None, created_by=user.id)
            self.repository.add_payment_record(db, record)
            self._rebalance(db, consultation, user.id, record)
            consultation.billing_version = (consultation.billing_version or 0) + 1
            db.commit()
            return self._consultation_projection(db, consultation)
        except HTTPException:
            db.rollback(); raise
        except Exception:
            db.rollback(); raise

    def correct_payment(self, db, payment_id, payload, user):
        self.ensure_ledger_schema(db)
        try:
            current = self.repository.get_latest_payment_record(db, payment_id)
            if not current:
                raise HTTPException(404, "Payment not found")
            consultation = self.repository.get_consultation_by_id(db, current.consultation_id, for_update=True)
            if (consultation.billing_version or 0) != payload.billingVersion:
                raise HTTPException(409, "Billing version conflict. Refresh and try again.")
            if current.revision_number != payload.expectedRevision:
                raise HTTPException(409, "Payment revision conflict. Refresh and try again.")
            record = models.FinancialPaymentRecord(id=str(uuid.uuid4()), payment_id=current.payment_id, consultation_id=current.consultation_id, revision_number=current.revision_number + 1, amount=payload.amount, paid_at=payload.paidAt, correction_reason=payload.reason, created_by=user.id)
            self.repository.add_payment_record(db, record)
            self._rebalance(db, consultation, user.id, record)
            consultation.billing_version = (consultation.billing_version or 0) + 1
            db.commit()
            return self._consultation_projection(db, consultation)
        except HTTPException:
            db.rollback(); raise
        except Exception:
            db.rollback(); raise
        except Exception:
            db.rollback()
            raise
