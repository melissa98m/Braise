import json
import logging
import uuid
from datetime import datetime, timezone
from urllib.parse import urlparse

from fastapi import HTTPException, status
from pywebpush import WebPushException, webpush
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db.session import SessionLocal
from app.models.match import Match
from app.models.profile import PublicProfile
from app.models.push_subscription import PushSubscription
from app.models.user import User
from app.schemas.notifications import PushSubscribeIn

logger = logging.getLogger(__name__)

# `endpoint` est entièrement fourni par le client à l'inscription et sera plus tard utilisé par ce
# serveur comme cible d'une requête HTTP *sortante* (send_push_to_user, via pywebpush) — accepter
# n'importe quel hôte en `https://` ne suffit pas à s'en protéger (n'importe quel service HTTPS
# joignable depuis ce conteneur resterait une cible valide, y compris à l'intérieur du réseau
# Docker) : c'est un SSRF potentiel, pas juste une validation de forme. Liste blanche des hôtes des
# services de push connus des navigateurs actuels, à tenir à jour si un nouveau navigateur majeur
# change de service.
_ALLOWED_PUSH_HOSTS = {
    "fcm.googleapis.com",  # Chrome, Edge et tout navigateur basé Chromium
    "updates.push.services.mozilla.com",  # Firefox
    "web.push.apple.com",  # Safari 16.4+
}


def _validate_endpoint(endpoint: str) -> None:
    parsed = urlparse(endpoint)
    if parsed.scheme != "https" or parsed.hostname not in _ALLOWED_PUSH_HOSTS:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Endpoint de notification invalide.")


def upsert_subscription(db: Session, user: User, payload: PushSubscribeIn) -> PushSubscription:
    _validate_endpoint(payload.endpoint)
    existing = (
        db.query(PushSubscription).filter(PushSubscription.endpoint == payload.endpoint).one_or_none()
    )
    if existing is None:
        existing = PushSubscription(endpoint=payload.endpoint)
        db.add(existing)
    # Réaffectation explicite même si la ligne existait déjà : sur un appareil partagé, un second
    # compte qui se connecte et réabonne ce même navigateur doit hériter de la ligne plutôt que se
    # la voir refuser ou créer un doublon (voir docstring de PushSubscription).
    existing.user_id = user.id
    existing.p256dh = payload.keys.p256dh
    existing.auth = payload.keys.auth
    existing.user_agent = payload.user_agent
    existing.notify_match = payload.notify_match
    existing.notify_question = payload.notify_question
    existing.notify_messages = payload.notify_messages
    db.commit()
    db.refresh(existing)
    return existing


def _get_owned_subscription_or_404(db: Session, user: User, endpoint: str) -> PushSubscription:
    # Un endpoint inexistant et un endpoint qui existe mais n'appartient pas à l'appelant renvoient
    # la même erreur générique — même logique anti-énumération que get_match_or_404.
    sub = db.query(PushSubscription).filter(PushSubscription.endpoint == endpoint).one_or_none()
    if sub is None or sub.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Abonnement introuvable.")
    return sub


def delete_subscription(db: Session, user: User, endpoint: str) -> None:
    sub = _get_owned_subscription_or_404(db, user, endpoint)
    db.delete(sub)
    db.commit()


def delete_all_subscriptions_for_user(db: Session, user_id: uuid.UUID) -> None:
    db.query(PushSubscription).filter(PushSubscription.user_id == user_id).delete()


def _is_subscription_dead(status_code: int | None) -> bool:
    """404/410 signifient que le service de push a définitivement invalidé cet abonnement (le
    navigateur ne le reverra jamais) — toute autre erreur (timeout, 5xx transitoire...) doit être
    journalisée et réessayée au prochain envoi, jamais supprimer la ligne. Factorisée à part exprès
    : c'est la seule portion de ce module testable sans jamais appeler pywebpush pour de vrai (voir
    tests/test_notifications.py) — ce projet n'utilise de mock nulle part, cette fonction pure
    permet de garder cette convention pour la logique de nettoyage aussi.
    """
    return status_code in (404, 410)


# Associe chaque catégorie à la colonne de préférence qui la gate — voir la docstring de
# PushSubscription pour pourquoi ce filtrage vit ici plutôt que côté client (Service Worker).
_CATEGORY_COLUMNS = {
    "match": PushSubscription.notify_match,
    "question": PushSubscription.notify_question,
    "messages": PushSubscription.notify_messages,
}


def send_push_to_user(
    user_id: uuid.UUID, *, title: str, body: str, category: str, url: str | None = None
) -> None:
    """N'échoue jamais vers l'appelant (comme services/question_llm.py) : un envoi push cassé ne
    doit jamais faire échouer la création d'un match ou l'envoi d'un message. Ouvre sa propre
    session plutôt que de recevoir celle de l'appelant — même raisonnement que chat_ws (session
    fraîche par opération), et ça évite de dépendre d'un ordre de fermeture entre BackgroundTasks
    et Depends(get_db) qui n'est garanti nulle part dans ce code."""
    settings = get_settings()
    if not settings.push_enabled:
        return
    with SessionLocal() as db:
        query = db.query(PushSubscription).filter(PushSubscription.user_id == user_id)
        category_column = _CATEGORY_COLUMNS.get(category)
        if category_column is not None:
            query = query.filter(category_column.is_(True))
        subs = query.all()
        dead_ids: list[uuid.UUID] = []
        for sub in subs:
            try:
                webpush(
                    subscription_info={
                        "endpoint": sub.endpoint,
                        "keys": {"p256dh": sub.p256dh, "auth": sub.auth},
                    },
                    data=json.dumps({"title": title, "body": body, "category": category, "url": url}),
                    vapid_private_key=settings.vapid_private_key,
                    vapid_claims={"sub": settings.vapid_subject},
                    timeout=5,
                )
                sub.last_seen_at = datetime.now(timezone.utc)
            except WebPushException as exc:
                response_status = exc.response.status_code if exc.response is not None else None
                if _is_subscription_dead(response_status):
                    dead_ids.append(sub.id)
                else:
                    logger.warning("Envoi push échoué pour l'abonnement %s : %s", sub.id, exc)
        if dead_ids:
            db.query(PushSubscription).filter(PushSubscription.id.in_(dead_ids)).delete(
                synchronize_session=False
            )
        db.commit()


def notify_new_match(swiper_id: uuid.UUID, recipient_id: uuid.UUID) -> None:
    if not get_settings().push_enabled:
        return
    with SessionLocal() as db:
        profile = db.get(PublicProfile, swiper_id)
        name = profile.display_name if profile and profile.display_name else "quelqu'un"
    send_push_to_user(
        recipient_id,
        title="Braise commune !",
        body=f"Vous avez matché avec {name}.",
        category="match",
    )


def notify_new_message(match_id: uuid.UUID, sender_id: uuid.UUID, body: str) -> None:
    if not get_settings().push_enabled:
        return
    with SessionLocal() as db:
        match = db.get(Match, match_id)
        if match is None:
            return
        recipient_id = match.user_b_id if match.user_a_id == sender_id else match.user_a_id
        profile = db.get(PublicProfile, sender_id)
        name = profile.display_name if profile and profile.display_name else "quelqu'un"
    send_push_to_user(
        recipient_id,
        title=f"Nouveau message de {name}",
        body=body[:120],
        category="messages",
        url=f"/matches/{match_id}",
    )
