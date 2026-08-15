from typing import Optional

from pydantic import BaseModel

class ConsultationPayload(BaseModel):
    toothData: dict
    version: int
    sessionNote: Optional[str] = None
    dentalStateVersion: Optional[int] = None

class ToothUpdatePayload(BaseModel):
    updates: dict
    version: int
