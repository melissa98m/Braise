from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.core.security import generate_otp_code
from app.models.user import User

OTP_TTL_MINUTES = 10

# P6.1 : le code OTP fait 6 chiffres (10^6 possibilités) et reste valide 10 minutes — sans limite
# de tentatives, un attaquant qui connaît le numéro d'une victime peut le forcer par brute force.
# MAX_OTP_ATTEMPTS neutralise le code courant après ce nombre d'essais ratés (l'utilisateur doit
# redemander un code) ; MIN_RESEND_INTERVAL_SECONDS empêche de régénérer un nouveau code (et donc
# de relancer un compteur d'essais à zéro) plus vite que ça.
MAX_OTP_ATTEMPTS = 5
MIN_RESEND_INTERVAL_SECONDS = 30


def request_otp(db: Session, phone: str) -> str:
    user = db.query(User).filter(User.phone == phone).one_or_none()
    if user is None:
        user = User(phone=phone)
        db.add(user)

    now = datetime.now(timezone.utc)
    if user.otp_requested_at is not None:
        elapsed = (now - user.otp_requested_at).total_seconds()
        if elapsed < MIN_RESEND_INTERVAL_SECONDS:
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                f"Merci de patienter {round(MIN_RESEND_INTERVAL_SECONDS - elapsed)} secondes "
                "avant de redemander un code.",
            )

    code = generate_otp_code()
    user.otp_code = code
    user.otp_expires_at = now + timedelta(minutes=OTP_TTL_MINUTES)
    user.otp_requested_at = now
    user.otp_attempts = 0
    db.commit()

    # Stub gratuit/local : en attendant un vrai opérateur SMS, le code part dans les logs.
    print(f"[DEBUG_OTP] code pour {phone} : {code}")
    return code


def verify_otp(db: Session, phone: str, code: str) -> User | None:
    user = db.query(User).filter(User.phone == phone).one_or_none()
    if user is None or user.otp_code is None:
        return None
    if user.otp_expires_at is None or user.otp_expires_at < datetime.now(timezone.utc):
        return None
    if user.otp_attempts >= MAX_OTP_ATTEMPTS:
        # Code neutralisé : même un code correct ne doit plus passer une fois la limite
        # atteinte, sinon MAX_OTP_ATTEMPTS ne fait que ralentir l'attaque au lieu de l'arrêter.
        user.otp_code = None
        db.commit()
        return None

    if user.otp_code != code:
        user.otp_attempts += 1
        db.commit()
        return None

    user.is_verified = True
    user.otp_code = None
    user.otp_expires_at = None
    user.otp_attempts = 0
    db.commit()
    return user
