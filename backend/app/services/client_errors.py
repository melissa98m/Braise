import hashlib
import logging
import re
import uuid
from datetime import datetime, timedelta, timezone

import redis
from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.client_error import ClientError
from app.schemas.feedback import ClientErrorIn

logger = logging.getLogger(__name__)

MESSAGE_MAX = 1000
STACK_MAX = 8000
# Endpoint ouvert sans authentification (une erreur peut survenir avant la connexion) : plafond
# par IP pour qu'il ne serve jamais à remplir la base. Une app qui plante en boucle n'a de toute
# façon pas besoin de plus — le client se limite lui-même (lib/telemetry/).
MAX_REPORTS_PER_IP_PER_HOUR = 60
RETENTION_DAYS = 90

# Ce qui varie d'une occurrence à l'autre d'une même erreur (identifiants, nombres, adresses)
# ne doit pas créer une empreinte différente à chaque fois.
_VOLATILE = re.compile(r"[0-9a-f]{8}-[0-9a-f-]{27}|0x[0-9a-f]+|\d+", re.IGNORECASE)


def _fingerprint(source: str, message: str, stack: str | None) -> str:
    first_frame = next((line.strip() for line in (stack or "").splitlines() if line.strip()), "")
    normalized = _VOLATILE.sub("#", f"{source}|{message[:300]}|{first_frame[:300]}")
    return hashlib.sha256(normalized.encode()).hexdigest()


def _check_ip_limit(client_ip: str | None) -> None:
    if not client_ip:
        return
    try:
        client = redis.Redis.from_url(get_settings().redis_url, socket_timeout=1)
        with client:
            key = f"bresonne:client-errors:ip:{client_ip}"
            count = client.incr(key)
            if count == 1:
                client.expire(key, 3600)
    except redis.RedisError:
        return
    if count > MAX_REPORTS_PER_IP_PER_HOUR:
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Trop de rapports d'erreur.")


def record_client_error(
    db: Session,
    payload: ClientErrorIn,
    user_id: uuid.UUID | None,
    client_ip: str | None,
    user_agent: str | None,
) -> None:
    _check_ip_limit(client_ip)
    message = payload.message[:MESSAGE_MAX]
    stack = payload.stack[:STACK_MAX] if payload.stack else None
    # Jamais la query string : elle peut porter un identifiant (`?match=<id>`, etc.).
    path = payload.path.split("?", 1)[0][:200] if payload.path else None
    fingerprint = _fingerprint(payload.source, message, stack)
    now = datetime.now(timezone.utc)

    existing = db.query(ClientError).filter(ClientError.fingerprint == fingerprint).one_or_none()
    if existing is None:
        db.add(
            ClientError(
                fingerprint=fingerprint,
                message=message,
                stack=stack,
                source=payload.source,
                path=path,
                user_agent=(user_agent or "")[:255] or None,
                last_user_id=user_id,
                first_seen_at=now,
                last_seen_at=now,
            )
        )
    else:
        existing.occurrences += 1
        existing.last_seen_at = now
        existing.last_user_id = user_id or existing.last_user_id
        existing.user_agent = (user_agent or "")[:255] or existing.user_agent
        # Erreur déjà marquée traitée qui revient : c'est une régression, elle repasse en tête.
        existing.status = "new"
    try:
        db.commit()
    except Exception:
        # Deux premières occurrences simultanées de la même erreur : la perdante n'apporte rien.
        db.rollback()


def purge_old_client_errors(db: Session) -> int:
    cutoff = datetime.now(timezone.utc) - timedelta(days=RETENTION_DAYS)
    deleted = db.query(ClientError).filter(ClientError.last_seen_at < cutoff).delete()
    db.commit()
    return deleted
