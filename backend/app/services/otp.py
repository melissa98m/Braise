import logging
from datetime import datetime, timedelta, timezone

import redis
from fastapi import HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.security import generate_otp_code, hash_otp_code, otp_code_matches
from app.models.otp_challenge import OtpChallenge
from app.models.user import User

logger = logging.getLogger(__name__)

OTP_TTL_MINUTES = 10

# Un code à 6 chiffres (10^6 possibilités) valable 10 minutes se force par brute force sans
# limite d'essais : MAX_OTP_ATTEMPTS neutralise le code courant après ce nombre d'échecs (même un
# code correct ne passe plus ensuite — sinon la limite ne ferait que ralentir l'attaque).
MAX_OTP_ATTEMPTS = 5
# Délai minimum entre deux codes pour la même adresse : sans lui, redemander un code remettrait
# le compteur d'essais à zéro aussi vite qu'on veut.
MIN_RESEND_INTERVAL_SECONDS = 30
# Plafond horaire par adresse : protège la boîte de quelqu'un contre un envoi en rafale (et le
# quota gratuit du fournisseur d'email contre l'épuisement), au-delà du simple délai ci-dessus.
MAX_REQUESTS_PER_EMAIL_PER_HOUR = 5

_IP_WINDOW_SECONDS = 3600


def _check_ip_rate_limit(client_ip: str | None) -> None:
    """Plafond par IP (Settings.otp_requests_per_ip_per_hour), compté dans Redis.

    Contre un attaquant qui ferait tourner les adresses email pour contourner les limites par
    adresse. Redis plutôt que Postgres : un simple compteur expirant (INCR + EXPIRE), partagé
    entre instances backend, sans table de plus. Si Redis est injoignable, on laisse passer en
    journalisant : les limites par adresse et par code (en base) restent en place, et refuser
    toute connexion pendant une panne Redis serait pire que perdre ce plafond secondaire.
    """
    limit = get_settings().otp_requests_per_ip_per_hour
    if limit <= 0 or not client_ip:
        return
    key = f"bresonne:otp:ip:{client_ip}"
    try:
        client = redis.Redis.from_url(get_settings().redis_url, socket_timeout=2)
        with client:
            count = client.incr(key)
            if count == 1:
                client.expire(key, _IP_WINDOW_SECONDS)
    except redis.RedisError:
        logger.exception("Plafond OTP par IP indisponible (Redis), demande laissée passer")
        return
    if count > limit:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Trop de demandes de code depuis cette connexion. Réessayez dans une heure.",
        )


def request_otp(db: Session, email: str, client_ip: str | None = None) -> str:
    """Prépare un nouveau code pour `email` et le renvoie (l'appelant se charge de l'envoyer).

    Ne crée jamais de `User` : seul `verify_otp` le fait, après un code correct. Le comportement
    est strictement identique qu'un compte existe ou non pour cette adresse — rien dans la
    réponse ne permet de savoir si quelqu'un y est déjà inscrit.
    """
    _check_ip_rate_limit(client_ip)

    now = datetime.now(timezone.utc)
    challenge = db.query(OtpChallenge).filter(OtpChallenge.email == email).one_or_none()
    if challenge is None:
        challenge = OtpChallenge(email=email, requested_at=now, window_started_at=now, window_count=0)
        db.add(challenge)
    else:
        elapsed = (now - challenge.requested_at).total_seconds()
        if elapsed < MIN_RESEND_INTERVAL_SECONDS:
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                f"Merci de patienter {round(MIN_RESEND_INTERVAL_SECONDS - elapsed)} secondes "
                "avant de redemander un code.",
            )
        if (now - challenge.window_started_at).total_seconds() >= 3600:
            challenge.window_started_at = now
            challenge.window_count = 0
        if challenge.window_count >= MAX_REQUESTS_PER_EMAIL_PER_HOUR:
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                "Trop de codes demandés pour cette adresse. Réessayez dans une heure.",
            )

    code = generate_otp_code()
    challenge.code_hash = hash_otp_code(email, code)
    challenge.expires_at = now + timedelta(minutes=OTP_TTL_MINUTES)
    challenge.requested_at = now
    challenge.attempts = 0
    challenge.window_count += 1
    try:
        db.commit()
    except IntegrityError:
        # Deux premières demandes simultanées pour la même adresse : la perdante n'a qu'à
        # réessayer — même réponse qu'un délai de renvoi non écoulé, aucun état incohérent.
        db.rollback()
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            f"Merci de patienter {MIN_RESEND_INTERVAL_SECONDS} secondes avant de redemander un code.",
        )
    return code


def verify_otp(db: Session, email: str, code: str) -> User | None:
    challenge = db.query(OtpChallenge).filter(OtpChallenge.email == email).one_or_none()
    if challenge is None or challenge.code_hash is None:
        return None
    if challenge.expires_at is None or challenge.expires_at < datetime.now(timezone.utc):
        return None
    if challenge.attempts >= MAX_OTP_ATTEMPTS:
        challenge.code_hash = None
        db.commit()
        return None

    if not otp_code_matches(email, code, challenge.code_hash):
        challenge.attempts += 1
        if challenge.attempts >= MAX_OTP_ATTEMPTS:
            challenge.code_hash = None
        db.commit()
        return None

    user = db.query(User).filter(User.email == email).one_or_none()
    if user is None:
        user = User(email=email)
        db.add(user)
    user.is_verified = True
    # Le code a servi : la ligne disparaît (usage unique), et avec elle les compteurs de débit —
    # sans effet de bord, une nouvelle demande légitime repart simplement de zéro.
    db.delete(challenge)
    try:
        db.commit()
    except IntegrityError:
        # Deux vérifications simultanées du même code correct pour une nouvelle adresse : les
        # deux tentent de créer le compte, la perdante relit celui que l'autre vient d'insérer.
        db.rollback()
        return db.query(User).filter(User.email == email).one_or_none()
    return user


def delete_challenge(db: Session, email: str) -> None:
    # Suppression de compte (services/account.py) : ne laisser aucun code en attente rattaché à
    # l'adresse d'un compte qu'on vient d'anonymiser.
    db.query(OtpChallenge).filter(OtpChallenge.email == email).delete(synchronize_session=False)
