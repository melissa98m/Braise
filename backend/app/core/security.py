import secrets
from datetime import datetime, timedelta, timezone

from jose import jwt

from app.core.config import get_settings

settings = get_settings()


def generate_otp_code() -> str:
    # secrets.randbelow (pas random.randint) : le code OTP est le seul secret qui protège la
    # prise de contrôle d'un compte (services/otp.py), donc il lui faut un générateur
    # cryptographiquement sûr — random.random utilise Mersenne Twister, prévisible si son état
    # interne est un jour reconstruit à partir d'assez de sorties observées.
    return f"{secrets.randbelow(1_000_000):06d}"


def create_access_token(subject: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.access_token_expire_minutes
    )
    payload = {"sub": subject, "exp": expire}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> dict:
    return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
