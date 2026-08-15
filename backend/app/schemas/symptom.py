from typing import Optional
from datetime import datetime
from pydantic import BaseModel

class SymptomCreate(BaseModel):
    name: str

class SymptomResponse(BaseModel):
    id: Optional[str] = None
    name: str
    created_by: Optional[str] = None
    is_active: int
    created_at: datetime
