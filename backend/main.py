from __future__ import annotations

from fastapi import FastAPI, Depends, HTTPException, Request, Response, status, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from sqlalchemy.orm import Session, joinedload
from pydantic import BaseModel, Field
import json
import time
from datetime import date, datetime, timedelta
from sqlalchemy import Column, Integer, String, DateTime, Date, ForeignKey, Text, func
import logging
from jose import JWTError, jwt
from passlib.context import CryptContext
from typing import List, Optional, Union
import uuid

import sys
import os
from ai_service import generate_clinical_report, humanize_report as humanize_report_ai

# Ensure the backend directory is in the python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import models
import ai_prompt
import pending_store
import email_service
import hashlib
from database import DATABASE_CONFIG, engine, get_db, Base, SessionLocal
from app.core.config import (
    CORS_ORIGIN_REGEX,
    CORS_ORIGINS,
    SupabaseAuthSettings,
    get_auth_mode,
)
from app.identity.auth_dependencies import AuthDependencies
from app.identity.supabase_auth_provider import SupabaseJwtProvider
from app.identity.user_resolver import ApplicationUserResolver
from app.repositories.user_repository import UserRepository
from app.services.auth_service import AuthService

def get_clinic_email(username: str, role: str) -> str:
    clean = "".join(c for c in username.replace(" ", "_") if c.isalnum() or c == "_").lower()
    if not clean:
        clean = "user"
    return f"{clean}@{role.lower()}.com"


# ── Initialization ───────────────────────────────────────────────────────────
F1_MIGRATION_MANAGED_TABLES = frozenset({
    "clinic_procedures",
    "consultation_procedures",
    "financial_payment_records",
    "financial_payment_allocations",
    "financial_charge_adjustments",
})


def create_runtime_schema(
    bind=engine,
    *,
    allow_schema_bootstrap=DATABASE_CONFIG.allow_schema_bootstrap,
):
    """Create local/test schema only when explicitly opted in; never on PostgreSQL."""
    if bind.dialect.name == "postgresql" or not allow_schema_bootstrap:
        return False
    Base.metadata.create_all(bind=bind)
    return True


create_runtime_schema()
app = FastAPI(title="Smart Dental Clinic Enterprise API")

# Configure Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ── Security Configuration ──────────────────────────────────────────────────
SECRET_KEY = "enterprise_secret_key_change_in_production"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 480

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="api/auth/login")
AUTH_MODE = get_auth_mode()
auth_service = AuthService()

if AUTH_MODE == "supabase":
    supabase_identity_provider = SupabaseJwtProvider(SupabaseAuthSettings.from_env())
    auth_dependencies = AuthDependencies(
        mode=AUTH_MODE,
        get_db_dependency=get_db,
        token_dependency=oauth2_scheme,
        auth_service=auth_service,
        identity_provider=supabase_identity_provider,
        user_resolver=ApplicationUserResolver(UserRepository()),
    )
else:
    auth_dependencies = AuthDependencies(
        mode=AUTH_MODE,
        get_db_dependency=get_db,
        token_dependency=oauth2_scheme,
        auth_service=auth_service,
        secret_key=SECRET_KEY,
        algorithm=ALGORITHM,
        is_blacklisted=pending_store.is_token_blacklisted,
    )

get_current_user = auth_dependencies.get_current_user
require_role = auth_dependencies.require_role
require_staff_role = auth_dependencies.require_staff_role

# ── Rate Limiting State ──────────────────────────────────────────────────────
user_request_counts = {} # {ip: [timestamps]}

@app.middleware("http")
async def rate_limit_middleware(request: Request, call_next):
    client_ip = request.client.host
    now = time.time()
    
    if client_ip not in user_request_counts:
        user_request_counts[client_ip] = []
    
    # Keep only last 1 second of requests
    user_request_counts[client_ip] = [t for t in user_request_counts[client_ip] if now - t < 1]
    
    if len(user_request_counts[client_ip]) >= 100: # 100 req/sec limit for production-grade dashboard
        return Response(content="Rate limit exceeded", status_code=429)
    
    user_request_counts[client_ip].append(now)
    return await call_next(request)


@app.middleware("http")
async def safe_error_boundary(request: Request, call_next):
    """Keep unhandled failures JSON-shaped without logging request bodies."""

    try:
        return await call_next(request)
    except Exception as error:
        logger.error(
            "Unhandled backend error for %s %s (%s)",
            request.method,
            request.url.path,
            type(error).__name__,
        )
        return JSONResponse(
            status_code=500,
            content={"detail": "Internal server error"},
        )


# Register CORS last so it wraps the rate limiter and safe error boundary.
app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_origin_regex=CORS_ORIGIN_REGEX,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)

# ── Pydantic Models ─────────────────────────────────────────────────────────
class Token(BaseModel):
    access_token: str
    token_type: str

class UserProfile(BaseModel):
    id: Optional[str] = None
    username: str
    role: str
    full_name: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    specialization: Optional[str] = None

class UserProfileUpdate(BaseModel):
    full_name: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    specialization: Optional[str] = None
    password: Optional[str] = None

class ClinicSettingsBase(BaseModel):
    name: str
    email: Optional[str] = None
    phone: Optional[str] = None
    address: Optional[str] = None
    working_hours: Optional[str] = None
    appointment_duration: int = 30
    services: Optional[str] = None
    notification_settings: Optional[str] = None

class ClinicSettingsResponse(ClinicSettingsBase):
    id: Optional[str] = None


class UserCreate(BaseModel):
    username: str
    password: str
    full_name: str
    email: str
    role: str # doctor or receptionist
    phone: Optional[str] = None
    specialization: Optional[str] = None
    personal_email: Optional[str] = None


class UserStaffUpdate(BaseModel):
    full_name: Optional[str] = None
    username: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    specialization: Optional[str] = None
    role: Optional[str] = None
    is_active: Optional[int] = None
    password: Optional[str] = None
    personal_email: Optional[str] = None


class PatientCreate(BaseModel):
    name: str
    age: Optional[int] = None
    phone: Optional[str] = None
    gender: Optional[str] = "Unknown"
    status: Optional[str] = "Active"
    condition: Optional[str] = "Routine Checkup"
    last_visit: Optional[str] = None
    blood_type: Optional[str] = "Unknown"

class PatientUpdate(BaseModel):
    name: Optional[str] = None
    age: Optional[int] = None
    phone: Optional[str] = None
    gender: Optional[str] = None
    status: Optional[str] = None
    condition: Optional[str] = None
    blood_type: Optional[str] = None

class AppointmentCreate(BaseModel):
    patient_id: Optional[str] = None
    date: str
    time: str
    type: Optional[str] = "Normal"
    condition: Optional[str] = "Routine Checkup"
    status: Optional[str] = "pending"

class AppointmentConditionResponse(BaseModel):
    id: Optional[str] = None
    name: str
    created_by: Optional[str] = None
    is_active: int
    created_at: datetime

    class Config:
        orm_mode = True

class ConsultationPayload(BaseModel):
    toothData: dict
    version: int

class ToothUpdatePayload(BaseModel):
    updates: dict
    version: int

class NotificationResponse(BaseModel):
    id: Optional[str] = None
    title: str
    body: str
    type: str
    read: bool
    created_at: str

class SymptomCreate(BaseModel):
    name: str

class SymptomResponse(BaseModel):
    id: Optional[str] = None
    name: str
    created_by: Optional[str] = None
    is_active: int
    created_at: datetime

# ── Helper Functions ────────────────────────────────────────────────────────
def log_event(db: Session, message: str, doctor_id=None, patient_id=None, before=None, after=None):
    try:
        new_log = models.Log(
            id=str(uuid.uuid4()),
            message=message,
            doctor_id=str(doctor_id) if doctor_id else None,
            patient_id=str(patient_id) if patient_id else None,
            before_state=json.dumps(before) if before else None,
            after_state=json.dumps(after) if after else None
        )
        db.add(new_log)
        db.commit()
    except Exception as error:
        logger.error("Failed to log event (%s)", type(error).__name__)

# ── Background Tasks ────────────────────────────────────────────────────────
def generate_clinical_report_task(patient_id: int):
    """Simulates background clinical report generation and AI auditing."""
    logger.info(f"[TASK] Starting report generation for patient {patient_id}")
    time.sleep(2) # Simulate heavy processing
    logger.info(f"[TASK] Report finalized and stored for patient {patient_id}")

def send_appointment_reminder_task(appointment_id: int):
    """Simulates sending a reminder via email/SMS."""
    logger.info(f"[TASK] Sending automated reminder for appointment {appointment_id}")
    time.sleep(1) # Simulate network call
    logger.info(f"[TASK] Reminder sent successfully for appointment {appointment_id}")

def bootstrap_default_users(auth_mode: str | None = None):
    """
    Ensure demo users exist for local/dev login flows.
    This runs only when the users table is empty.
    """
    if (auth_mode or AUTH_MODE) != "legacy":
        return
    db = SessionLocal()
    try:
        if db.query(models.User).count() > 0:
            return

        demo_users = [
            models.User(
                username="doctor1",
                hashed_password=pwd_context.hash("password123"),
                full_name="DR Yehia El-ameir",
                email="doctor1@doctor.com",
                role="doctor"
            ),
            models.User(
                username="admin",
                hashed_password=pwd_context.hash("password123"),
                full_name="Clinic Admin",
                email="admin@admin.com",
                role="admin"
            ),
            models.User(
                username="receptionist1",
                hashed_password=pwd_context.hash("password123"),
                full_name="Front Desk",
                email="receptionist1@receptionist.com",
                role="receptionist"
            ),
        ]
        db.add_all(demo_users)
        db.commit()

        # Seed default mappings
        pending_store.save_email_mapping("doctor1@doctor.com", "doctor1@clinic.com")
        pending_store.save_email_mapping("admin@admin.com", "admin@clinic.com")
        pending_store.save_email_mapping("receptionist1@receptionist.com", "receptionist1@clinic.com")

        # Add initial notifications
        if db.query(models.Notification).count() == 0:
            initial_notifications = [
                models.Notification(title="System Ready", body="Backend-driven clinical system is now active.", type="success"),
                models.Notification(title="Daily Schedule", body="Your appointments for today have been synced.", type="info"),
                models.Notification(title="AI Module", body="Practice insights and clinical diagnosis engine online.", type="info"),
            ]
            db.add_all(initial_notifications)
            db.commit()
            
        # Seed default clinic settings
        if db.query(models.ClinicSettings).count() == 0:
            default_settings = models.ClinicSettings(
                name="Smart Dental Clinic",
                email="info@smartclinic.com",
                phone="+1 555-9000",
                address="1200 Health Blvd, Suite 400, New York, NY 10001",
                working_hours="09:00 - 17:00",
                appointment_duration=30,
                services='["Consultation", "Cleaning", "Root Canal", "Extraction"]',
                notification_settings='{"appointmentReminders": true, "criticalAlerts": true, "emailReports": false}'
            )
            db.add(default_settings)
            db.commit()

        logger.info("Bootstrapped default demo users and settings.")
    except Exception as e:
        db.rollback()
        logger.error(f"Failed to bootstrap default users: {e}")
    finally:
        db.close()

def migrate_existing_users_to_clinic_emails(
    db: Session, auth_mode: str | None = None
):
    """
    Ensures all existing users in the main DB have their email set to their auto-generated clinic email.
    Saves their old email as their personal email in the mapping table.
    """
    if (auth_mode or AUTH_MODE) != "legacy":
        return
    try:
        linked_user_ids = auth_service.linked_user_ids(db)
        users = db.query(models.User).all()
        for u in users:
            if str(u.id) in linked_user_ids:
                continue
            role = u.role or "doctor"
            clinic_email = get_clinic_email(u.username, role)
            
            # Check if there is an existing mapping
            personal_email = pending_store.get_personal_email_by_clinic_email(clinic_email)
            if not personal_email:
                old_email = u.email
                if old_email and "@" in old_email:
                    personal_email = old_email
                else:
                    personal_email = f"{u.username.replace(' ', '_').lower()}@personal.com"
                
                # Save mapping
                pending_store.save_email_mapping(clinic_email, personal_email)
            
            # Update user email in DB to the clinic email
            if u.email != clinic_email:
                u.email = clinic_email
                logger.info(f"Migrated user '{u.username}' email to clinic email '{clinic_email}'")
        
        db.commit()
    except Exception as e:
        db.rollback()
        logger.error(f"Failed to migrate existing users to clinic emails: {e}")

@app.on_event("startup")
def startup_bootstrap():
    if AUTH_MODE == "legacy":
        bootstrap_default_users()
    db = SessionLocal()
    try:
        if AUTH_MODE == "supabase":
            auth_service.validate_supabase_identity_schema(db)
        else:
            migrate_existing_users_to_clinic_emails(db)
        pending_store.cleanup_expired_records()
    finally:
        db.close()


# ── Authentication Endpoints ─────────────────────────────────────────────────
def send_verification_email(personal_email: str, clinic_email: str, code: str):
    pending_store.log_email_sent(personal_email)
    email_service.send_verification_email(personal_email, code)

class VerifyPayload(BaseModel):
    code: str
    personal_email: Optional[str] = None
    username: Optional[str] = None


def require_legacy_auth_mode():
    if AUTH_MODE != "legacy":
        raise HTTPException(status_code=404, detail="Not found")

@app.post(
    "/api/auth/login",
    response_model=Token,
    dependencies=[Depends(require_legacy_auth_mode)],
)
async def login(request: Request, db: Session = Depends(get_db)):
    content_type = request.headers.get("content-type", "")
    email_val = None
    password_val = None
    
    if "application/json" in content_type:
        try:
            body = await request.json()
            email_val = body.get("email") or body.get("username")
            password_val = body.get("password")
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid JSON payload")
    else:
        try:
            form_data = await request.form()
            email_val = form_data.get("username") or form_data.get("email")
            password_val = form_data.get("password")
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid form data")
            
    if not email_val or not password_val:
        raise HTTPException(status_code=400, detail="Invalid credentials")
        
    clinic_email = email_val.strip().lower()
    print(f"[LOGIN REQUEST RECEIVED]: email_val='{email_val}', clinic_email='{clinic_email}'", flush=True)
    
    try:
        user = db.query(models.User).populate_existing().filter(
            func.trim(func.lower(models.User.email)) == clinic_email
        ).first()
        
        if not user:
            print(f"[LOGIN FAIL]: User '{clinic_email}' not found in database", flush=True)
            raise HTTPException(status_code=400, detail="Invalid credentials")

        is_match = pwd_context.verify(password_val, user.hashed_password)

        if not is_match:
            print(f"[LOGIN FAIL]: Password mismatch for user '{clinic_email}'", flush=True)
            raise HTTPException(status_code=400, detail="Invalid credentials")

    except HTTPException:
        raise
    except Exception as login_err:
        print(f"[LOGIN ERROR EXCEPTION]: {login_err}", flush=True)
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=400, detail="Invalid credentials")
    
    access_token = jwt.encode(
        {"sub": user.email, "exp": datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)},
        SECRET_KEY, algorithm=ALGORITHM
    )
    return {"access_token": access_token, "token_type": "bearer"}


@app.post("/api/auth/register", dependencies=[Depends(require_legacy_auth_mode)])
def register(payload: UserCreate, db: Session = Depends(get_db)):
    import re
    import secrets
    
    # 1. Role must be doctor or receptionist ONLY for standard registration
    role_clean = payload.role.strip().lower()
    if role_clean not in ["doctor", "receptionist"]:
        raise HTTPException(
            status_code=400,
            detail="Registration is only allowed for doctor or receptionist accounts."
        )
        
    # 2. Username Normalization and Regex Validation
    username_clean = payload.username.strip().lower()
    if not re.match(r"^[a-zA-Z0-9_]+$", username_clean):
        raise HTTPException(
            status_code=400,
            detail="Username must contain only letters, numbers, or underscores"
        )
        
    # 3. Password Validation
    if len(payload.password) < 8 or not any(c.isupper() for c in payload.password) or not any(c.isdigit() for c in payload.password):
        raise HTTPException(
            status_code=400,
            detail="Password must be at least 8 characters long and contain at least one uppercase letter and one number"
        )
        
    # 4. Personal Email Format Validation
    personal_email_clean = payload.personal_email.strip().lower() if payload.personal_email else None
    if not personal_email_clean:
        if payload.email and not any(payload.email.strip().lower().endswith(f"@{r}.com") for r in ["doctor", "receptionist", "admin"]):
            personal_email_clean = payload.email.strip().lower()
        else:
            personal_email_clean = f"{username_clean}@personal.com"
            
    if not re.match(r"[^@]+@[^@]+\.[^@]+", personal_email_clean):
        raise HTTPException(status_code=400, detail="Invalid email format")
            
    # 5. Clinic Email Generation
    clinic_email = get_clinic_email(username_clean, role_clean)
    
    # 6. Generic Response
    reply = {
        "status": "success",
        "message": "If an account exists, a code has been sent",
        "personal_email": personal_email_clean
    }

    # 7. Rate Limiting Check (3 emails / minute) - Check FIRST to prevent side-channel leaks
    if pending_store.get_email_sent_count_last_minute(personal_email_clean) >= 3:
        raise HTTPException(
            status_code=429,
            detail="Rate limit exceeded. Please wait a minute before requesting another email."
        )

    # 8. Check if account already exists (either active in DB, personal email mapped, or pending registration)
    existing_user = db.query(models.User).filter(
        (func.lower(models.User.username) == username_clean) |
        (func.lower(models.User.email) == clinic_email)
    ).first()
    
    is_pending = pending_store.is_username_or_email_pending(username_clean, personal_email_clean)
    
    if existing_user or pending_store.is_personal_email_exists(personal_email_clean) or is_pending:
        return reply

    # 9. Generate secure 6-digit verification code
    verification_code = "".join(secrets.choice("0123456789") for _ in range(6))
    hashed_code = hashlib.sha256(verification_code.encode()).hexdigest()
    
    # Hash password securely
    hashed_pwd = pwd_context.hash(payload.password)
    
    # Save pending registration details
    pending_store.save_pending_registration(
        personal_email=personal_email_clean,
        username=username_clean,
        password=hashed_pwd,
        full_name=payload.full_name,
        role=role_clean,
        phone=payload.phone,
        specialization=payload.specialization,
        verification_code=hashed_code
    )
    
    # Send verification code
    send_verification_email(personal_email_clean, clinic_email, verification_code)
    
    return reply

@app.post(
    "/api/auth/verify",
    response_model=Token,
    dependencies=[Depends(require_legacy_auth_mode)],
)
def verify(payload: VerifyPayload, db: Session = Depends(get_db)):
    code = payload.code.strip()
    
    if payload.username:
        pending = pending_store.get_pending_registration_by_username(payload.username)
    elif payload.personal_email:
        pending = pending_store.get_pending_registration(payload.personal_email)
    else:
        raise HTTPException(status_code=400, detail="Must provide username or personal_email")
        
    if not pending:
        raise HTTPException(status_code=400, detail="Invalid or expired verification code")
        
    personal_email = pending.get("personal_email")
    
    # Check attempts count (Max 5)
    hashed_code = hashlib.sha256(code.encode()).hexdigest()
    if pending["verification_code"] != hashed_code:
        attempts = pending_store.increment_registration_attempts(personal_email)
        if attempts >= 5:
            pending_store.delete_pending_registration(personal_email)
            raise HTTPException(status_code=400, detail="Too many incorrect attempts. Signup restarted.")
        raise HTTPException(status_code=400, detail="Invalid verification code")
        
    # Check expiration
    if pending["expires_at"] < datetime.utcnow():
        pending_store.delete_pending_registration(personal_email)
        raise HTTPException(status_code=400, detail="Invalid or expired verification code")
        
    # Generate clinic email
    clinic_email = get_clinic_email(pending["username"], pending["role"])
    
    # Double check username/email uniqueness in database
    existing_user = db.query(models.User).filter(
        (func.lower(models.User.username) == pending["username"]) |
        (func.lower(models.User.email) == clinic_email)
    ).first()
    
    if existing_user:
        pending_store.delete_pending_registration(personal_email)
        raise HTTPException(status_code=400, detail="Account already exists")
        
    # Create the user account
    new_user = models.User(
        username=pending["username"],
        hashed_password=pending["password"], # Already hashed
        full_name=pending["full_name"],
        email=clinic_email,
        role=pending["role"],
        phone=pending["phone"],
        specialization=pending["specialization"],
        is_active=1
    )
    
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    
    # Save mapping permanently
    pending_store.save_email_mapping(clinic_email, personal_email)
    
    # Delete pending registration entry
    pending_store.delete_pending_registration(personal_email)
    
    # Generate access token
    access_token = jwt.encode(
        {"sub": new_user.username, "exp": datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)},
        SECRET_KEY, algorithm=ALGORITHM
    )
    return {"access_token": access_token, "token_type": "bearer"}



class ForgotPasswordPayload(BaseModel):
    clinic_email: str

class ResetPasswordPayload(BaseModel):
    token: str
    new_password: str
    clinic_email: Optional[str] = None

def send_reset_password_email(personal_email: str, clinic_email: str, token: str):
    pending_store.log_email_sent(personal_email)
    email_service.send_reset_email(personal_email, token)

@app.post("/api/auth/logout", dependencies=[Depends(require_legacy_auth_mode)])
def logout(token: str = Depends(oauth2_scheme)):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        exp = payload.get("exp")
        if exp:
            expires_at = datetime.utcfromtimestamp(exp)
        else:
            expires_at = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
        pending_store.blacklist_token(token, expires_at)
    except JWTError:
        pass
    return {"status": "success", "message": "Successfully logged out"}

@app.post(
    "/api/auth/forgot-password", dependencies=[Depends(require_legacy_auth_mode)]
)
def forgot_password(payload: ForgotPasswordPayload, db: Session = Depends(get_db)):
    clinic_email = payload.clinic_email.strip().lower()
    
    # ALWAYS return standard reply for privacy
    reply = {
        "status": "success",
        "message": "If an account exists, a code has been sent"
    }
    
    # Rate Limiting Check (3 emails / minute) on clinic email to prevent side-channel leaks
    if pending_store.get_email_sent_count_last_minute(clinic_email) >= 3:
        raise HTTPException(
            status_code=429,
            detail="Rate limit exceeded. Please wait a minute before requesting another email."
        )
    pending_store.log_email_sent(clinic_email)
    
    # Case-insensitive lookup on clinic email
    user = db.query(models.User).filter(
        func.lower(models.User.email) == clinic_email
    ).first()
    
    if not user:
        return reply
        
    personal_email = pending_store.get_personal_email_by_clinic_email(user.email)
    if not personal_email:
        personal_email = f"{user.username.replace(' ', '_').lower()}@personal.com"
        pending_store.save_email_mapping(user.email, personal_email)
        
    # Rate Limiting Check (3 emails / minute) on personal email
    if pending_store.get_email_sent_count_last_minute(personal_email) >= 3:
        raise HTTPException(
            status_code=429,
            detail="Rate limit exceeded. Please wait a minute before requesting another email."
        )

    import secrets
    # 6-digit reset code
    code = "".join(secrets.choice("0123456789") for _ in range(6))
    hashed_code = hashlib.sha256(code.encode()).hexdigest()
    
    # Invalidate old resets for this user first
    try:
        import sqlite3
        conn = sqlite3.connect(pending_store.DB_PATH)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM password_resets WHERE clinic_email = ?", (user.email.strip().lower(),))
        conn.commit()
        conn.close()
    except Exception as e:
        logger.error(f"Failed to invalidate old reset tokens: {e}")

    pending_store.save_password_reset(user.email, personal_email, hashed_code)
    
    send_reset_password_email(personal_email, user.email, code)
    
    # Keep personal_email in response strictly for testing verification if needed
    reply["personal_email"] = personal_email
    return reply

@app.post(
    "/api/auth/reset-password", dependencies=[Depends(require_legacy_auth_mode)]
)
def reset_password(payload: ResetPasswordPayload, db: Session = Depends(get_db)):
    if len(payload.new_password) < 8 or not any(c.isupper() for c in payload.new_password) or not any(c.isdigit() for c in payload.new_password):
        raise HTTPException(
            status_code=400,
            detail="Password must be at least 8 characters long and contain at least one uppercase letter and one number"
        )
        
    hashed_token = hashlib.sha256(payload.token.strip().encode()).hexdigest()
        
    # Attempt Protection: Lookup reset request by token
    reset_record = None
    if payload.clinic_email:
        # Search resets to see if the clinic email has a reset request
        import sqlite3
        conn = sqlite3.connect(pending_store.DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT reset_token, personal_email, expires_at, attempts FROM password_resets WHERE clinic_email = ?", (payload.clinic_email.strip().lower(),))
        row = cursor.fetchone()
        conn.close()
        if row:
            reset_record = {
                "reset_token": row[0],
                "clinic_email": payload.clinic_email.strip().lower(),
                "personal_email": row[1],
                "expires_at": datetime.fromisoformat(row[2]) if isinstance(row[2], str) else row[2],
                "attempts": row[3]
            }
            
    if not reset_record:
        # Fallback to direct lookup by token (code) if no clinic_email was provided
        reset_record = pending_store.get_password_reset(hashed_token)
        
    if not reset_record:
        raise HTTPException(status_code=400, detail="Invalid or expired verification code")
        
    # Check attempts count (Max 5)
    if reset_record.get("reset_token") != hashed_token:
        # Increment attempts
        attempts = pending_store.increment_reset_attempts(reset_record["reset_token"])
        if attempts >= 5:
            pending_store.delete_password_reset(reset_record["reset_token"])
            raise HTTPException(status_code=400, detail="Too many incorrect attempts. Password reset request expired.")
        raise HTTPException(status_code=400, detail="Invalid verification code")
        
    # Check expiry
    if reset_record["expires_at"] < datetime.utcnow():
        pending_store.delete_password_reset(reset_record["reset_token"])
        raise HTTPException(status_code=400, detail="Invalid or expired verification code")
        
    user = db.query(models.User).filter(
        func.lower(models.User.email) == reset_record["clinic_email"]
    ).first()
    
    if not user:
        raise HTTPException(status_code=400, detail="User not found")
        
    user.hashed_password = pwd_context.hash(payload.new_password)
    db.commit()
    
    pending_store.delete_password_reset(reset_record["reset_token"])
    
    return {"status": "success", "message": "Password successfully updated"}



from app.routers.auth import create_auth_router

app.include_router(
    create_auth_router(
        auth_dependency=get_current_user,
        auth_service=auth_service,
    )
)

# ── Dashboard & Stats ───────────────────────────────────────────────────────
from app.routers.appointments import create_today_appointments_router

app.include_router(
    create_today_appointments_router(
        get_db_dependency=get_db,
        auth_dependency=get_current_user,
        audit_logger=log_event,
        reminder_callable=lambda appointment_id: send_appointment_reminder_task(
            appointment_id
        ),
        logger=logger,
    )
)

# ── Notifications Endpoints ────────────────────────────────────────────────
from app.routers.notifications import create_notification_router

app.include_router(
    create_notification_router(
        get_db_dependency=get_db,
        auth_dependency=get_current_user,
    )
)

# ── Core Data Endpoints ───────────────────────────────────────────────────────
from app.routers.patients import create_patient_router

app.include_router(
    create_patient_router(
        get_db_dependency=get_db,
        auth_dependency=get_current_user,
        staff_dependency=require_staff_role(),
        doctor_dependency=require_role("doctor"),
        audit_logger=log_event,
    )
)

from app.routers.appointments import create_appointment_crud_router
from app.services.appointment_service import (
    normalize_appointment_status,
    normalize_appointment_type,
)

app.include_router(
    create_appointment_crud_router(
        get_db_dependency=get_db,
        auth_dependency=get_current_user,
        staff_dependency=require_staff_role(),
        audit_logger=log_event,
        reminder_callable=lambda appointment_id: send_appointment_reminder_task(
            appointment_id
        ),
        logger=logger,
    )
)

from app.routers.staff import create_staff_router

app.include_router(
    create_staff_router(
        get_db_dependency=get_db,
        authenticated_dependency=get_current_user,
        admin_dependency=require_role("admin"),
        password_hasher=pwd_context.hash,
        clinic_email_factory=get_clinic_email,
        pending_store_module=pending_store,
    )
)

# ── Clinical Endpoints ──────────────────────────────────────────────────────
from app.routers.consultations import (
    create_consultation_history_router,
    create_consultation_router,
)

from app.routers.finance import create_finance_router

app.include_router(
    create_finance_router(
        get_db_dependency=get_db,
        authenticated_dependency=get_current_user,
    )
)

app.include_router(
    create_consultation_router(
        get_db_dependency=get_db,
        doctor_dependency=require_role("doctor"),
        audit_logger=log_event,
        report_generator=lambda patient_id: generate_clinical_report_task(patient_id),
        logger=logger,
    )
)

from app.routers.medications import create_medication_router

app.include_router(
    create_medication_router(
        get_db_dependency=get_db,
        doctor_dependency=require_role("doctor"),
        admin_dependency=require_role("admin"),
    )
)

from app.routers.appointments import create_appointment_completion_router

app.include_router(
    create_appointment_completion_router(
        get_db_dependency=get_db,
        doctor_dependency=require_role("doctor"),
        audit_logger=log_event,
        reminder_callable=lambda appointment_id: send_appointment_reminder_task(
            appointment_id
        ),
        logger=logger,
    )
)

def generate_pdf_report_file(report: models.ClinicalReport, db: Session):
    """Generate a clean, beautiful medical-themed PDF clinical report."""
    try:
        from reportlab.lib.pagesizes import letter
        from reportlab.lib import colors
        from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
        from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
        
        base_dir = os.path.dirname(os.path.abspath(__file__))
        reports_dir = os.path.join(base_dir, "static_reports")
        os.makedirs(reports_dir, exist_ok=True)
        
        pdf_filename = f"report_{report.id}_{int(time.time())}.pdf"
        pdf_filepath = os.path.join(reports_dir, pdf_filename)
        
        doc = SimpleDocTemplate(
            pdf_filepath,
            pagesize=letter,
            rightMargin=36,
            leftMargin=36,
            topMargin=36,
            bottomMargin=36
        )
        
        styles = getSampleStyleSheet()
        
        # Premium medical styles
        title_style = ParagraphStyle(
            'ClinicTitle',
            parent=styles['Heading1'],
            fontName='Helvetica-Bold',
            fontSize=20,
            textColor=colors.HexColor('#FFFFFF'),
            spaceAfter=4
        )
        
        subtitle_style = ParagraphStyle(
            'ClinicSubtitle',
            parent=styles['Normal'],
            fontName='Helvetica',
            fontSize=9.5,
            textColor=colors.HexColor('#E0F2FE'),
            spaceAfter=2,
            leading=13
        )
        
        h1_style = ParagraphStyle(
            'SectionHeader',
            parent=styles['Heading2'],
            fontName='Helvetica-Bold',
            fontSize=13,
            textColor=colors.HexColor('#0f766e'), # Medical Dark Teal
            spaceBefore=12,
            spaceAfter=6
        )
        
        label_style = ParagraphStyle(
            'InfoLabel',
            parent=styles['Normal'],
            fontName='Helvetica-Bold',
            fontSize=9,
            textColor=colors.HexColor('#475569')
        )
        
        val_style = ParagraphStyle(
            'InfoVal',
            parent=styles['Normal'],
            fontName='Helvetica',
            fontSize=9,
            textColor=colors.HexColor('#1E293B')
        )
        
        body_style = ParagraphStyle(
            'ReportBody',
            parent=styles['Normal'],
            fontName='Helvetica',
            fontSize=9.5,
            textColor=colors.HexColor('#1E293B'),
            leading=14,
            spaceAfter=6
        )
        
        footer_style = ParagraphStyle(
            'FooterText',
            parent=styles['Normal'],
            fontName='Helvetica-Oblique',
            fontSize=8,
            textColor=colors.HexColor('#94A3B8'),
            alignment=1
        )

        # Fetch dynamic clinic settings from database if available
        clinic_settings = db.query(models.ClinicSettings).first()
        clinic_name = clinic_settings.name if (clinic_settings and clinic_settings.name) else "SMART DENTAL CLINIC"
        clinic_email = clinic_settings.email if (clinic_settings and clinic_settings.email) else "info@smartclinic.com"
        clinic_phone = clinic_settings.phone if (clinic_settings and clinic_settings.phone) else "+1 555-9000"
        clinic_address = clinic_settings.address if (clinic_settings and clinic_settings.address) else "1200 Health Blvd, NY"

        elements = []
        
        # 1. Header Banner
        header_data = [
            [
                Paragraph(clinic_name.upper(), title_style),
                Paragraph(f"<b>Email:</b> {clinic_email}<br/><b>Phone:</b> {clinic_phone}<br/><b>Address:</b> {clinic_address}", subtitle_style)
            ]
        ]
        header_table = Table(header_data, colWidths=[300, 240])
        header_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, -1), colors.HexColor('#0f766e')),
            ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
            ('PADDING', (0, 0), (-1, -1), 14),
            ('ALIGN', (1, 0), (1, 0), 'RIGHT'),
        ]))
        elements.append(header_table)
        elements.append(Spacer(1, 14))
        
        # Helper to append solid lines
        def add_separator():
            line_table = Table([[""]], colWidths=[540], rowHeights=[1])
            line_table.setStyle(TableStyle([
                ('LINEABOVE', (0,0), (-1,-1), 1, colors.HexColor('#E2E8F0')),
                ('BOTTOMPADDING', (0,0), (-1,-1), 0),
                ('TOPPADDING', (0,0), (-1,-1), 0),
            ]))
            elements.append(line_table)
            elements.append(Spacer(1, 6))
            
        # 2. Document Info
        patient = report.patient
        doctor = report.doctor
        created_time = report.created_at.strftime("%Y-%m-%d %I:%M %p") if report.created_at else datetime.utcnow().strftime("%Y-%m-%d %I:%M %p")
        
        info_data = [
            [
                Paragraph("<b>Patient Name:</b>", label_style), Paragraph(patient.name if patient else "N/A", val_style),
                Paragraph("<b>Doctor Name:</b>", label_style), Paragraph(doctor.full_name if doctor else "N/A", val_style)
            ],
            [
                Paragraph("<b>Age / Gender:</b>", label_style), Paragraph(f"{patient.age if patient else 'N/A'}y / {patient.gender if patient else 'N/A'}", val_style),
                Paragraph("<b>Specialization:</b>", label_style), Paragraph(doctor.specialization if doctor and doctor.specialization else "General Dentistry", val_style)
            ],
            [
                Paragraph("<b>Phone / Blood Type:</b>", label_style), Paragraph(f"{patient.phone if patient else 'N/A'} (Blood: {patient.blood_type if patient else 'Unknown'})", val_style),
                Paragraph("<b>Consultation Time:</b>", label_style), Paragraph(created_time, val_style)
            ]
        ]
        
        info_table = Table(info_data, colWidths=[100, 170, 100, 170])
        info_table.setStyle(TableStyle([
            ('VALIGN', (0, 0), (-1, -1), 'TOP'),
            ('PADDING', (0, 0), (-1, -1), 4),
            ('BACKGROUND', (0, 0), (-1, -1), colors.HexColor('#F8FAFC')),
            ('BOX', (0, 0), (-1, -1), 0.5, colors.HexColor('#E2E8F0')),
        ]))
        elements.append(info_table)
        elements.append(Spacer(1, 10))
        
        # 3. Tooth & Diagnosis section
        elements.append(Paragraph("Consultation Parameters", h1_style))
        add_separator()
        
        symptoms_list = []
        if report.symptoms:
            try:
                symptoms_list = json.loads(report.symptoms)
            except:
                symptoms_list = [report.symptoms]
        symptoms_str = ", ".join(symptoms_list) if symptoms_list else "None Reported"
        
        param_data = [
            [Paragraph("<b>Target Tooth ID:</b>", label_style), Paragraph(report.tooth_id or "General / Non-Specific", val_style)],
            [Paragraph("<b>Tooth Condition:</b>", label_style), Paragraph(report.tooth_status or "N/A", val_style)],
            [Paragraph("<b>Reported Symptoms:</b>", label_style), Paragraph(symptoms_str, val_style)]
        ]
        param_table = Table(param_data, colWidths=[120, 420])
        param_table.setStyle(TableStyle([
            ('VALIGN', (0, 0), (-1, -1), 'TOP'),
            ('PADDING', (0, 0), (-1, -1), 4),
        ]))
        elements.append(param_table)
        elements.append(Spacer(1, 10))
        
        # 4. Clinical Findings / Approved Report
        elements.append(Paragraph("Final Clinical Findings & Diagnosis", h1_style))
        add_separator()
        
        findings_text = report.final_medical_report or report.ai_draft_report or "No clinical report notes documented."
        elements.append(Paragraph(findings_text.replace("\n", "<br/>"), body_style))
        elements.append(Spacer(1, 10))
        
        # 5. Doctor's Private Notes
        if report.doctor_notes:
            elements.append(Paragraph("Doctor's Additional Notes", h1_style))
            add_separator()
            elements.append(Paragraph(report.doctor_notes.replace("\n", "<br/>"), body_style))
            elements.append(Spacer(1, 10))
            
        # 6. Patient Friendly Explanations (Humanized)
        if report.humanized_report:
            elements.append(Paragraph("Patient-Friendly Advice & Explanation", h1_style))
            add_separator()
            elements.append(Paragraph(report.humanized_report.replace("\n", "<br/>"), body_style))
            elements.append(Spacer(1, 10))
            
        # 7. Signature area
        elements.append(Spacer(1, 20))
        sig_data = [
            [
                Paragraph("", val_style),
                Paragraph("___________________________<br/><b>DR. Signature</b>", val_style)
            ]
        ]
        sig_table = Table(sig_data, colWidths=[340, 200])
        sig_table.setStyle(TableStyle([
            ('ALIGN', (1, 0), (1, 0), 'CENTER'),
            ('VALIGN', (0, 0), (-1, -1), 'BOTTOM'),
        ]))
        elements.append(sig_table)
        
        # 8. Footer text
        elements.append(Spacer(1, 24))
        elements.append(Paragraph(f"This is an official clinical record generated automatically by Smart Dental Clinic on {created_time}.", footer_style))
        
        doc.build(elements)
        
        # Update model
        report.pdf_path = pdf_filepath
        db.commit()
        logger.info(f"Successfully generated PDF report at {pdf_filepath}")
        return pdf_filepath
    except Exception as e:
        logger.error(f"Failed to generate PDF: {e}")
        return None

# ── Clinical Reports (AI + CRUD) ────────────────────────────────────────────
app.include_router(
    create_consultation_history_router(
        get_db_dependency=get_db,
        doctor_dependency=require_role("doctor"),
    )
)

from app.routers.reports import create_report_router

app.include_router(
    create_report_router(
        get_db_dependency=get_db,
        auth_dependency=get_current_user,
        doctor_dependency=require_role("doctor"),
        pdf_generator=lambda report, db: generate_pdf_report_file(report, db),
        report_ai=lambda payload: generate_clinical_report(payload),
        humanize_ai=lambda report, patient_name: humanize_report_ai(
            report, patient_name
        ),
        audit_logger=log_event,
        logger=logger,
    )
)

# ── AI Configuration ─────────────────────────────────────────────────────────
from app.ai.ollama_provider import (
    OLLAMA_BASE_URL,
    OLLAMA_MODEL,
    create_ollama_client,
)

def _get_ollama(temperature=0.2, format=None):
    return create_ollama_client(temperature=temperature, format=format)

# ── AI Endpoints ────────────────────────────────────────────────────────────
from app.routers.common import create_common_router

app.include_router(
    create_common_router(
        get_db_dependency=get_db,
        auth_dependency=get_current_user,
        staff_dependency=require_staff_role(),
        ai_factory=lambda temperature=0.2, format=None: _get_ollama(
            temperature=temperature, format=format
        ),
        logger=logger,
    )
)

# ── Settings Endpoints ───────────────────────────────────────────────────────
from app.routers.clinic_settings import create_clinic_settings_router

app.include_router(
    create_clinic_settings_router(
        get_db_dependency=get_db,
        auth_dependency=get_current_user,
        password_hasher=lambda password: pwd_context.hash(password),
        pending_store_module=pending_store,
    )
)


# ── Clinical Symptoms Endpoints ──────────────────────────────────────────────
from app.routers.symptoms import create_symptom_router

app.include_router(
    create_symptom_router(
        get_db_dependency=get_db,
        auth_dependency=get_current_user,
    )
)

# Database connected to Supabase PostgreSQL live
