from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.config import get_settings
from app.core.security import create_access_token
from app.db.session import get_db
from app.models.user import User
from app.schemas.auth import (
    ConsentIn,
    ConsentOut,
    OTPRequest,
    OTPRequestResponse,
    OTPVerify,
    TokenResponse,
)
from app.services import account as account_service
from app.services import consent as consent_service
from app.services import email as email_service
from app.services import otp as otp_service

router = APIRouter(prefix="/auth", tags=["auth"])
settings = get_settings()


@router.post("/request-otp", response_model=OTPRequestResponse)
def request_otp(
    payload: OTPRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
):
    client_ip = request.client.host if request.client else None
    code = otp_service.request_otp(db, payload.email, client_ip=client_ip)
    # Envoi en tâche de fond, après la réponse : la durée de la requête ne dépend jamais du
    # fournisseur d'email (ni ne laisse deviner quoi que ce soit), et une panne SMTP ne se voit
    # pas côté client — même réponse dans tous les cas, voir services/email.send_otp_email.
    background_tasks.add_task(email_service.send_otp_email, payload.email, code, otp_service.OTP_TTL_MINUTES)
    return OTPRequestResponse(
        message="Si l'adresse est valide, un code vient d'y être envoyé.",
        debug_code=code if settings.debug_otp else None,
    )


@router.post("/verify-otp", response_model=TokenResponse)
def verify_otp(payload: OTPVerify, db: Session = Depends(get_db)):
    user = otp_service.verify_otp(db, payload.email, payload.code)
    if user is None:
        raise HTTPException(status_code=400, detail="Code invalide ou expiré.")
    token = create_access_token(subject=str(user.id))
    return TokenResponse(access_token=token)


@router.get("/me")
def read_me(user: User = Depends(get_current_user)):
    return {
        "id": str(user.id),
        "email": user.email,
        "is_verified": user.is_verified,
        "consents_given": consent_service.consents_complete(user),
    }


@router.post("/consent", response_model=ConsentOut)
def submit_consent(
    payload: ConsentIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    user = consent_service.record_consent(db, user, payload)
    return ConsentOut(
        consents_given=consent_service.consents_complete(user),
        consent_age_at=user.consent_age_at.isoformat() if user.consent_age_at else None,
        consent_cgu_at=user.consent_cgu_at.isoformat() if user.consent_cgu_at else None,
        consent_privacy_at=user.consent_privacy_at.isoformat() if user.consent_privacy_at else None,
        consent_sensitive_data_at=(
            user.consent_sensitive_data_at.isoformat() if user.consent_sensitive_data_at else None
        ),
    )


@router.get("/me/export")
def export_my_data(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return account_service.export_my_data(db, user)


@router.delete("/me")
def delete_my_account(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    account_service.delete_my_account(db, user)
    return {"message": "Compte supprimé."}
