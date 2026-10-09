import hashlib
import hmac
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


def hash_otp_code(email: str, code: str) -> str:
    # Le code OTP n'est jamais stocké en clair (services/otp.py) : une fuite de la base ne doit
    # livrer aucun code utilisable. HMAC plutôt qu'un simple SHA-256 : un code à 6 chiffres n'a
    # que 10^6 valeurs, un hash non salé se renverserait par force brute en une fraction de
    # seconde — sans la clé, impossible. Clé dérivée de JWT_SECRET avec séparation de domaine
    # ("otp:") plutôt qu'un secret de plus à gérer ; l'email entre dans le message pour qu'un
    # même code ne donne jamais le même hash pour deux adresses.
    key = hashlib.sha256(b"otp:" + settings.jwt_secret.encode()).digest()
    return hmac.new(key, f"{email}:{code}".encode(), hashlib.sha256).hexdigest()


def otp_code_matches(email: str, code: str, expected_hash: str) -> bool:
    # compare_digest : temps constant, la durée de la comparaison ne révèle rien du hash attendu.
    return hmac.compare_digest(hash_otp_code(email, code), expected_hash)


def create_access_token(subject: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.access_token_expire_minutes
    )
    payload = {"sub": subject, "exp": expire}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> dict:
    return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
