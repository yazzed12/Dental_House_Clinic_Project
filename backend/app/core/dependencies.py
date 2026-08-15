from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from jose import JWTError

from database import get_db
import models
import pending_store
from app.core.security import decode_access_token
from app.repositories import UserRepository

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="api/auth/login")
user_repo = UserRepository()

def get_current_user(db: Session = Depends(get_db), token: str = Depends(oauth2_scheme)) -> models.User:
    """FastAPI dependency to extract and validate the authenticated user from JWT bearer token using UserRepository."""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if pending_store.is_token_blacklisted(token):
        raise credentials_exception

    try:
        payload = decode_access_token(token)
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    user = user_repo.get_by_email_or_username(db, username) or user_repo.get_by_id(db, username)
    if user is None:
        raise credentials_exception
    return user

def require_role(role: str):
    """Dependency factory enforcing specific user role authorization (with admin bypass)."""
    def role_checker(user: models.User = Depends(get_current_user)):
        if user.role != role and user.role != 'admin':
            raise HTTPException(status_code=403, detail="Insufficient permissions")
        return user
    return role_checker

def require_staff_role():
    """Dependency factory enforcing clinic staff authorization (doctor, receptionist, admin)."""
    def role_checker(user: models.User = Depends(get_current_user)):
        if user.role not in ['doctor', 'receptionist', 'admin']:
            raise HTTPException(status_code=403, detail="Insufficient permissions")
        return user
    return role_checker
