from typing import Optional
from datetime import datetime
from pydantic import BaseModel

class AppointmentCreate(BaseModel):
    patient_id: Optional[str] = None
    date: str
    time: str
    type: Optional[str] = "Normal"
    condition: Optional[str] = "Routine Checkup"
    status: Optional[str] = "pending"

class AppointmentConditionCreate(BaseModel):
    name: str

class AppointmentConditionResponse(BaseModel):
    id: Optional[str] = None
    name: str
    created_by: Optional[str] = None
    is_active: int
    created_at: datetime

    class Config:
        orm_mode = True
        from_attributes = True
