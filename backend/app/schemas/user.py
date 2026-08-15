from typing import Optional
from pydantic import BaseModel

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
