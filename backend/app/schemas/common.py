from typing import List
from pydantic import BaseModel

class ChatMessage(BaseModel):
    role: str
    text: str

class ChatRequest(BaseModel):
    messages: List[ChatMessage]

class InsightStats(BaseModel):
    patients: int
    today_appointments: int
    completed: int
    pending: int

class InsightResponse(BaseModel):
    summary: str
    stats: InsightStats
    recommendations: List[str]

class DiagnosisRequest(BaseModel):
    symptoms: str
    history: str
    tooth_data: dict

class DiagnosisResponse(BaseModel):
    diagnosis: str
    conditions: List[str]
    treatment_plan: List[str]
