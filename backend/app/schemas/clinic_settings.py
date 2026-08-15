from typing import Optional
from pydantic import BaseModel

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

class ClinicSettingsUpdate(BaseModel):
    name: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    address: Optional[str] = None
    working_hours: Optional[str] = None
    appointment_duration: Optional[int] = None
    services: Optional[str] = None
    notification_settings: Optional[str] = None
