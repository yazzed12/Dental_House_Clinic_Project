from typing import Optional
from pydantic import BaseModel

class Token(BaseModel):
    access_token: str
    token_type: str

class VerifyPayload(BaseModel):
    code: str
    personal_email: Optional[str] = None
    username: Optional[str] = None

class ForgotPasswordPayload(BaseModel):
    clinic_email: str

class ResetPasswordPayload(BaseModel):
    token: str
    new_password: str
    clinic_email: Optional[str] = None
