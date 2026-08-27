from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.core.security import generate_otp_code
from app.models.user import User

OTP_TTL_MINUTES = 10


def request_otp(db: Session, phone: str) -> str:
    user = db.query(User).filter(User.phone == phone).one_or_none()
    if user is None:
        user = User(phone=phone)
        db.add(user)

    code = generate_otp_code()
    user.otp_code = code
    user.otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=OTP_TTL_MINUTES)
    db.commit()

    # Stub gratuit/local : en attendant un vrai opérateur SMS, le code part dans les logs.
    print(f"[DEBUG_OTP] code pour {phone} : {code}")
    return code


def verify_otp(db: Session, phone: str, code: str) -> User | None:
    user = db.query(User).filter(User.phone == phone).one_or_none()
    if user is None or user.otp_code != code:
        return None
    if user.otp_expires_at is None or user.otp_expires_at < datetime.now(timezone.utc):
        return None

    user.is_verified = True
    user.otp_code = None
    user.otp_expires_at = None
    db.commit()
    return user
