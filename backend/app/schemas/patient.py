from typing import Optional
from pydantic import BaseModel

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
