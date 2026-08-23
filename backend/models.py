from sqlalchemy import Boolean, CheckConstraint, Column, Computed, Date, DateTime, ForeignKey, Index, Integer, JSON, Numeric, String, Text, Time, UniqueConstraint, Uuid, func, text
from sqlalchemy.orm import relationship, validates
from datetime import datetime, date as date_cls, time as time_cls
from database import Base


def uuid_string_type():
    """Native PostgreSQL UUID with legacy string compatibility for SQLite tests."""
    return Uuid(as_uuid=False).with_variant(String(), "sqlite")

def parse_time_string(time_str):
    if not time_str:
        return None
    if isinstance(time_str, time_cls):
        return time_str
    
    time_str = str(time_str).strip()
    formats = [
        "%H:%M:%S",
        "%H:%M",
        "%I:%M %p",
        "%I:%M%p",
        "%I %p",
        "%I%p",
        "%H:%M:%S.%f"
    ]
    for fmt in formats:
        try:
            return datetime.strptime(time_str, fmt).time()
        except ValueError:
            pass
            
    try:
        parts = time_str.split(":")
        if len(parts) >= 2:
            h = int(parts[0])
            m = int(parts[1])
            s = 0
            if len(parts) >= 3:
                sec_part = parts[2].split(".")[0].split()[0]
                s = int(sec_part)
            return time_cls(h, m, s)
    except Exception:
        pass
        
    return time_cls(9, 0)

class User(Base):
    __tablename__ = "users"

    id = Column(uuid_string_type(), primary_key=True, index=True)
    username = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    full_name = Column(String)
    email = Column(String, unique=True, index=True)
    role = Column(String, default="doctor") # admin / doctor / receptionist
    is_active = Column(Integer, default=1)
    phone = Column(String, nullable=True)
    specialization = Column(String, nullable=True)

class ClinicSettings(Base):
    __tablename__ = "clinic_settings"

    id = Column(String, primary_key=True, index=True)
    name = Column(String, nullable=False, default="Smart Dental Clinic")
    email = Column(String, nullable=True)
    phone = Column(String, nullable=True)
    address = Column(String, nullable=True)
    working_hours = Column(String, nullable=True)
    appointment_duration = Column(Integer, default=30)
    services = Column(Text, nullable=True) # JSON array of services
    notification_settings = Column(Text, nullable=True) # JSON object
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class Patient(Base):
    __tablename__ = "patients"

    id = Column(uuid_string_type(), primary_key=True, index=True, server_default=text("gen_random_uuid()"))
    name = Column(String, nullable=False)
    age = Column(Integer)
    phone = Column(String)
    gender = Column(String, default="Unknown")
    status = Column(String, default="Active")
    condition = Column(String, default="Routine Checkup")
    last_visit = Column(String, nullable=True)
    blood_type = Column(String, default="Unknown")

    appointments = relationship("Appointment", back_populates="patient")
    records = relationship("Record", back_populates="patient")

class Appointment(Base):
    __tablename__ = "appointments"

    id = Column(uuid_string_type(), primary_key=True, index=True)
    patient_id = Column(uuid_string_type(), ForeignKey("patients.id"))
    doctor_id = Column(uuid_string_type(), ForeignKey("users.id"), nullable=True)
    date = Column(Date, nullable=True)
    time = Column(String, nullable=True)
    appointment_date = Column(Date, nullable=True)
    appointment_time = Column(Time, nullable=True)
    status = Column(String, default="Pending")  # Pending / Completed
    type = Column(String, default="Normal")    # Urgent / Normal
    condition = Column(String, default="Routine Checkup")

    patient = relationship("Patient", back_populates="appointments")

    @validates("date")
    def validate_date(self, key, value):
        self.appointment_date = value
        return value

    @validates("time")
    def validate_time(self, key, value):
        if value:
            self.appointment_time = parse_time_string(value)
        return value

class Record(Base):
    __tablename__ = "records"

    id = Column(String, primary_key=True, index=True)
    patient_id = Column(uuid_string_type(), ForeignKey("patients.id"))
    tooth = Column(String)
    diagnosis = Column(String)

    patient = relationship("Patient", back_populates="records")

class Log(Base):
    __tablename__ = "logs"

    id = Column(String, primary_key=True, index=True)
    message = Column(String, nullable=False)
    doctor_id = Column(uuid_string_type(), ForeignKey("users.id"), nullable=True)
    patient_id = Column(uuid_string_type(), ForeignKey("patients.id"), nullable=True)
    before_state = Column(Text, nullable=True) # JSON
    after_state = Column(Text, nullable=True)  # JSON
    created_at = Column(DateTime, default=datetime.utcnow)

class Consultation(Base):
    __tablename__ = "consultations"
    __table_args__ = (
        CheckConstraint(
            "procedures_version >= 0",
            name="consultations_procedures_version_nonnegative_ck",
        ),
        CheckConstraint(
            "billing_version >= 0",
            name="consultations_billing_version_nonnegative_ck",
        ),
    )

    id = Column(uuid_string_type(), primary_key=True, index=True)
    patient_id = Column(uuid_string_type(), ForeignKey("patients.id"), index=True)
    doctor_id = Column(uuid_string_type(), ForeignKey("users.id"), nullable=True, index=True)
    appointment_id = Column(uuid_string_type(), ForeignKey("appointments.id"), nullable=True, index=True)
    data = Column(Text, nullable=False) # JSON
    session_note = Column(Text, nullable=True)
    version = Column(Integer, default=1) # Optimistic Locking
    procedures_version = Column(Integer, nullable=False, default=0)
    billing_version = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)
    last_updated = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    patient = relationship("Patient")


class ClinicProcedure(Base):
    __tablename__ = "clinic_procedures"

    id = Column(uuid_string_type(), primary_key=True)
    name = Column(Text, nullable=False)
    price = Column(Numeric(12, 2), nullable=False)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)
    __table_args__ = (
        CheckConstraint(
            "trim(name) <> ''",
            name="clinic_procedures_name_nonempty_ck",
        ),
        CheckConstraint(
            "price >= 0",
            name="clinic_procedures_price_nonnegative_ck",
        ),
        Index(
            "clinic_procedures_name_ci_uq",
            func.lower(func.trim(name)),
            unique=True,
        ),
    )


class ConsultationProcedure(Base):
    __tablename__ = "consultation_procedures"
    __table_args__ = (
        UniqueConstraint(
            "consultation_id",
            "procedure_id",
            name="consultation_procedures_consultation_procedure_uq",
        ),
        CheckConstraint(
            "trim(procedure_name_snapshot) <> ''",
            name="consultation_procedures_name_nonempty_ck",
        ),
        CheckConstraint(
            "quantity BETWEEN 1 AND 999",
            name="consultation_procedures_quantity_ck",
        ),
        CheckConstraint(
            "unit_price_snapshot >= 0",
            name="consultation_procedures_unit_price_nonnegative_ck",
        ),
        Index(
            "consultation_procedures_consultation_idx",
            "consultation_id",
        ),
        Index(
            "consultation_procedures_procedure_idx",
            "procedure_id",
        ),
    )

    id = Column(uuid_string_type(), primary_key=True)
    consultation_id = Column(uuid_string_type(), ForeignKey("consultations.id", ondelete="RESTRICT", name="consultation_procedures_consultation_fk"), nullable=False)
    procedure_id = Column(uuid_string_type(), ForeignKey("clinic_procedures.id", ondelete="RESTRICT", name="consultation_procedures_procedure_fk"), nullable=False)
    procedure_name_snapshot = Column(Text, nullable=False)
    unit_price_snapshot = Column(Numeric(12, 2), nullable=False)
    quantity = Column(Integer, nullable=False)
    line_total = Column(
        Numeric(15, 2),
        Computed("unit_price_snapshot * quantity", persisted=True),
        nullable=False,
    )
    created_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)


class FinancialPaymentRecord(Base):
    __tablename__ = "financial_payment_records"
    __table_args__ = (
        UniqueConstraint("payment_id", "revision_number", name="financial_payment_records_payment_revision_uq"),
        CheckConstraint("revision_number >= 1", name="financial_payment_records_revision_positive_ck"),
        CheckConstraint("amount > 0", name="financial_payment_records_amount_positive_ck"),
        CheckConstraint("(revision_number = 1 AND correction_reason IS NULL) OR (revision_number > 1 AND trim(coalesce(correction_reason, '')) <> '')", name="financial_payment_records_reason_ck"),
        Index("financial_payment_records_consultation_idx", "consultation_id", "payment_id", "revision_number"),
    )

    id = Column(uuid_string_type(), primary_key=True)
    payment_id = Column(uuid_string_type(), nullable=False)
    consultation_id = Column(uuid_string_type(), ForeignKey("consultations.id", ondelete="RESTRICT"), nullable=False)
    revision_number = Column(Integer, nullable=False)
    amount = Column(Numeric(15, 2), nullable=False)
    paid_at = Column(DateTime(timezone=True), nullable=False)
    correction_reason = Column(Text, nullable=True)
    created_by = Column(uuid_string_type(), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)


class FinancialPaymentAllocation(Base):
    __tablename__ = "financial_payment_allocations"
    __table_args__ = (
        UniqueConstraint("payment_record_id", "consultation_procedure_id", name="financial_payment_allocations_record_procedure_uq"),
        CheckConstraint("allocated_amount > 0", name="financial_payment_allocations_amount_positive_ck"),
        Index("financial_payment_allocations_procedure_idx", "consultation_procedure_id"),
    )

    id = Column(uuid_string_type(), primary_key=True)
    payment_record_id = Column(uuid_string_type(), ForeignKey("financial_payment_records.id", ondelete="RESTRICT"), nullable=False)
    consultation_procedure_id = Column(uuid_string_type(), ForeignKey("consultation_procedures.id", ondelete="RESTRICT"), nullable=False)
    allocated_amount = Column(Numeric(15, 2), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)


class FinancialChargeAdjustment(Base):
    __tablename__ = "financial_charge_adjustments"
    __table_args__ = (
        CheckConstraint("quantity_delta <> 0", name="financial_charge_adjustments_delta_nonzero_ck"),
        CheckConstraint("unit_price_snapshot >= 0", name="financial_charge_adjustments_price_nonnegative_ck"),
        CheckConstraint("trim(reason) <> ''", name="financial_charge_adjustments_reason_nonempty_ck"),
        Index("financial_charge_adjustments_procedure_idx", "consultation_procedure_id", "created_at", "id"),
    )

    id = Column(uuid_string_type(), primary_key=True)
    consultation_procedure_id = Column(uuid_string_type(), ForeignKey("consultation_procedures.id", ondelete="RESTRICT"), nullable=False)
    quantity_delta = Column(Integer, nullable=False)
    unit_price_snapshot = Column(Numeric(12, 2), nullable=False)
    line_total_delta = Column(Numeric(15, 2), Computed("unit_price_snapshot * quantity_delta", persisted=True), nullable=True)
    reason = Column(Text, nullable=False)
    created_by = Column(uuid_string_type(), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)


class PatientDentalState(Base):
    __tablename__ = "patient_dental_state"

    patient_id = Column(uuid_string_type(), ForeignKey("patients.id", ondelete="CASCADE"), primary_key=True)
    data = Column(Text, nullable=False)
    version = Column(Integer, nullable=False, default=1)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)

class Notification(Base):
    __tablename__ = "notifications"

    id = Column(String, primary_key=True, index=True)
    title = Column(String)
    body = Column(String)
    type = Column(String, default="info") # urgent / info / success / warning
    read = Column(Integer, default=0) # 0 for false, 1 for true
    created_at = Column(DateTime, default=datetime.utcnow)
    user_id = Column(uuid_string_type(), ForeignKey("users.id"), nullable=True)

class ClinicalReport(Base):
    __tablename__ = "clinical_reports"

    id = Column(String, primary_key=True, index=True)
    patient_id = Column(uuid_string_type(), ForeignKey("patients.id"), nullable=False)
    doctor_id = Column(uuid_string_type(), ForeignKey("users.id"), nullable=True)
    appointment_id = Column(uuid_string_type(), ForeignKey("appointments.id"), nullable=True)
    tooth_id = Column(String, nullable=True)
    tooth_status = Column(String, nullable=True)
    symptoms = Column(Text, nullable=True)  # JSON array
    doctor_notes = Column(Text, nullable=True)
    ai_draft_report = Column(Text, nullable=True)
    final_medical_report = Column(Text, nullable=True)
    humanized_report = Column(Text, nullable=True)
    status = Column(String, default="draft")  # draft / approved / finalized
    pdf_path = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    patient = relationship("Patient")
    doctor = relationship("User")


class MedicationImportBatch(Base):
    __tablename__ = "medication_import_batches"

    id = Column(uuid_string_type(), primary_key=True, server_default=text("gen_random_uuid()"))
    source_name = Column(Text, nullable=False)
    source_version = Column(Text)
    source_reference = Column(Text)
    market = Column(Text, nullable=False)
    input_format = Column(Text, nullable=False)
    status = Column(Text, nullable=False, default="processing")
    total_rows = Column(Integer, nullable=False, default=0)
    inserted_count = Column(Integer, nullable=False, default=0)
    updated_count = Column(Integer, nullable=False, default=0)
    unchanged_count = Column(Integer, nullable=False, default=0)
    rejected_count = Column(Integer, nullable=False, default=0)
    duplicate_count = Column(Integer, nullable=False, default=0)
    imported_by = Column(uuid_string_type(), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    started_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)
    completed_at = Column(DateTime(timezone=True))


class MedicationImportRejection(Base):
    __tablename__ = "medication_import_rejections"
    __table_args__ = (UniqueConstraint("batch_id", "row_number", name="medication_import_rejections_batch_row_uq"),)

    id = Column(uuid_string_type(), primary_key=True, server_default=text("gen_random_uuid()"))
    batch_id = Column(uuid_string_type(), ForeignKey("medication_import_batches.id", ondelete="RESTRICT"), nullable=False)
    row_number = Column(Integer, nullable=False)
    source_record_id = Column(Text)
    raw_payload = Column(JSON, nullable=False)
    reasons = Column(JSON, nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)


class DentalMedication(Base):
    __tablename__ = "dental_medications"

    id = Column(uuid_string_type(), primary_key=True, server_default=text("gen_random_uuid()"))
    catalog_scope = Column(Text, nullable=False)
    identity_key = Column(Text, nullable=False)
    brand_name = Column(Text, nullable=False)
    generic_name = Column(Text)
    strength = Column(Text, nullable=False)
    dosage_form = Column(Text, nullable=False)
    route = Column(Text, nullable=False)
    category = Column(Text)
    manufacturer = Column(Text)
    market = Column(Text, nullable=False)
    country = Column(Text)
    source_type = Column(Text, nullable=False)
    source_name = Column(Text, nullable=False)
    source_reference = Column(Text)
    source_version = Column(Text)
    source_record_id = Column(Text)
    verification_status = Column(Text, nullable=False, default="pending")
    imported_at = Column(DateTime(timezone=True))
    last_verified_at = Column(DateTime(timezone=True))
    is_active = Column(Boolean, nullable=False, default=True)
    created_by = Column(uuid_string_type(), ForeignKey("users.id", ondelete="RESTRICT"))
    import_batch_id = Column(uuid_string_type(), ForeignKey("medication_import_batches.id", ondelete="RESTRICT"))
    created_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)


class MedicationClinicalPreset(Base):
    __tablename__ = "medication_clinical_presets"

    id = Column(uuid_string_type(), primary_key=True, server_default=text("gen_random_uuid()"))
    medication_id = Column(uuid_string_type(), ForeignKey("dental_medications.id", ondelete="RESTRICT"), nullable=False)
    default_dose = Column(Text)
    default_frequency = Column(Text)
    default_duration = Column(Text)
    default_instructions = Column(Text)
    clinical_context = Column(Text, nullable=False, default="general_dental")
    source = Column(Text, nullable=False)
    source_reference = Column(Text)
    source_version = Column(Text)
    reviewed_by = Column(uuid_string_type(), ForeignKey("users.id", ondelete="RESTRICT"))
    reviewed_at = Column(DateTime(timezone=True))
    preset_version = Column(Integer, nullable=False, default=1)
    review_status = Column(Text, nullable=False, default="pending")
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)


class DoctorMedicationPreset(Base):
    __tablename__ = "doctor_medication_presets"
    __table_args__ = (UniqueConstraint("doctor_id", "medication_id", name="doctor_medication_presets_doctor_medication_uq"),)

    id = Column(uuid_string_type(), primary_key=True, server_default=text("gen_random_uuid()"))
    doctor_id = Column(uuid_string_type(), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    medication_id = Column(uuid_string_type(), ForeignKey("dental_medications.id", ondelete="RESTRICT"), nullable=False)
    default_dose = Column(Text)
    default_frequency = Column(Text)
    default_duration = Column(Text)
    default_instructions = Column(Text)
    doctor_notes = Column(Text)
    created_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)


class Prescription(Base):
    __tablename__ = "prescriptions"
    __table_args__ = (UniqueConstraint("consultation_id", name="prescriptions_consultation_uq"),)

    id = Column(uuid_string_type(), primary_key=True, server_default=text("gen_random_uuid()"))
    consultation_id = Column(uuid_string_type(), ForeignKey("consultations.id", ondelete="RESTRICT"), nullable=False)
    patient_id = Column(uuid_string_type(), ForeignKey("patients.id", ondelete="RESTRICT"), nullable=False)
    doctor_id = Column(uuid_string_type(), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    appointment_id = Column(uuid_string_type(), ForeignKey("appointments.id", ondelete="RESTRICT"))
    status = Column(Text, nullable=False, default="draft")
    version = Column(Integer, nullable=False, default=1)
    approved_by = Column(uuid_string_type(), ForeignKey("users.id", ondelete="RESTRICT"))
    approved_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)
    items = relationship("PrescriptionItem", order_by="PrescriptionItem.position")


class PrescriptionItem(Base):
    __tablename__ = "prescription_items"
    __table_args__ = (
        UniqueConstraint("prescription_id", "position", name="prescription_items_position_uq"),
        UniqueConstraint("prescription_id", "medication_id", name="prescription_items_medication_uq"),
    )

    id = Column(uuid_string_type(), primary_key=True, server_default=text("gen_random_uuid()"))
    prescription_id = Column(uuid_string_type(), ForeignKey("prescriptions.id", ondelete="RESTRICT"), nullable=False)
    medication_id = Column(uuid_string_type(), ForeignKey("dental_medications.id", ondelete="RESTRICT"))
    clinical_preset_id = Column(uuid_string_type(), ForeignKey("medication_clinical_presets.id", ondelete="RESTRICT"))
    doctor_preset_id = Column(uuid_string_type(), ForeignKey("doctor_medication_presets.id", ondelete="RESTRICT"))
    position = Column(Integer, nullable=False)
    brand_name_snapshot = Column(Text, nullable=False)
    generic_name_snapshot = Column(Text)
    strength_snapshot = Column(Text, nullable=False)
    dosage_form_snapshot = Column(Text, nullable=False)
    route_snapshot = Column(Text, nullable=False)
    dose_snapshot = Column(Text, nullable=False)
    frequency_snapshot = Column(Text, nullable=False)
    duration_snapshot = Column(Text, nullable=False)
    instructions_snapshot = Column(Text)
    doctor_notes_snapshot = Column(Text)
    source_type_snapshot = Column(Text)
    source_name_snapshot = Column(Text)
    source_reference_snapshot = Column(Text)
    source_version_snapshot = Column(Text)
    source_record_id_snapshot = Column(Text)
    verification_status_snapshot = Column(Text)
    created_at = Column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)

class Symptom(Base):
    __tablename__ = "symptoms"

    id = Column(String, primary_key=True, index=True)
    name = Column(String, unique=True, index=True, nullable=False)
    created_by = Column(uuid_string_type(), ForeignKey("users.id"), nullable=True)
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime, default=datetime.utcnow)

    creator = relationship("User")

class AppointmentCondition(Base):
    __tablename__ = "appointment_conditions"

    id = Column(String, primary_key=True, index=True)
    name = Column(String, unique=True, index=True, nullable=False)
    created_by = Column(uuid_string_type(), ForeignKey("users.id"), nullable=True)
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime, default=datetime.utcnow)

    creator = relationship("User")
