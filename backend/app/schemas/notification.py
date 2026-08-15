from typing import Optional
from pydantic import BaseModel

class NotificationResponse(BaseModel):
    id: Optional[str] = None
    title: str
    body: str
    type: str
    read: bool
    created_at: str
