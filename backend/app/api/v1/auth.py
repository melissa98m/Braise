from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.config import get_settings
from app.core.security import create_access_token
from app.db.session import get_db
from app.models.user import User
from app.schemas.auth import OTPRequest, OTPRequestResponse, OTPVerify, TokenResponse
from app.services import account as account_service
from app.services import otp as otp_service

router = APIRouter(prefix="/auth", tags=["auth"])
settings = get_settings()


@router.post("/request-otp", response_model=OTPRequestResponse)
def request_otp(payload: OTPRequest, db: Session = Depends(get_db)):
    code = otp_service.request_otp(db, payload.phone)
    return OTPRequestResponse(
        message="Code envoyé (voir les logs du backend en local).",
        debug_code=code if settings.debug_otp else None,
    )


@router.post("/verify-otp", response_model=TokenResponse)
def verify_otp(payload: OTPVerify, db: Session = Depends(get_db)):
    user = otp_service.verify_otp(db, payload.phone, payload.code)
    if user is None:
        raise HTTPException(status_code=400, detail="Code invalide ou expiré.")
    token = create_access_token(subject=str(user.id))
    return TokenResponse(access_token=token)


@router.get("/me")
def read_me(user: User = Depends(get_current_user)):
    return {"id": str(user.id), "phone": user.phone, "is_verified": user.is_verified}


@router.get("/me/export")
def export_my_data(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return account_service.export_my_data(db, user)


@router.delete("/me")
def delete_my_account(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    account_service.delete_my_account(db, user)
    return {"message": "Compte supprimé."}
