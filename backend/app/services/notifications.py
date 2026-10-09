import json
import logging
import uuid
from datetime import date, datetime, timezone
from urllib.parse import urlparse

import redis
from fastapi import HTTPException, status
from pywebpush import WebPushException, webpush
from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db.session import SessionLocal
from app.models.daily_question import DailyQuestion
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
    user_id: uuid.UUID,
    *,
    title: str,
    body: str,
    category: str,
    url: str | None = None,
    tag: str | None = None,
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
                    data=json.dumps(
                        {"title": title, "body": body, "category": category, "url": url, "tag": tag}
                    ),
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
            except Exception:
                # Clés illisibles, erreur de chiffrement... : un seul abonnement corrompu ne doit
                # jamais interrompre l'envoi aux autres (le rappel quotidien boucle sur tout le
                # monde) — journalisé, la ligne reste, comme pour une erreur transitoire.
                logger.exception("Envoi push impossible pour l'abonnement %s", sub.id)
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
        match = (
            db.query(Match)
            .filter(
                or_(
                    and_(Match.user_a_id == swiper_id, Match.user_b_id == recipient_id),
                    and_(Match.user_a_id == recipient_id, Match.user_b_id == swiper_id),
                )
            )
            .one_or_none()
        )
        match_id = match.id if match else None
    send_push_to_user(
        recipient_id,
        title="Braise commune !",
        body=f"Vous avez matché avec {name}.",
        category="match",
        url=match_url(match_id),
    )


def notify_new_message(match_id: uuid.UUID, sender_id: uuid.UUID) -> None:
    """Jamais le contenu du message (choix produit) : une notification s'affiche sur un écran
    verrouillé, potentiellement sous les yeux de quelqu'un d'autre — pour une app de rencontre,
    même un extrait peut révéler une relation ou une orientation. Le prénom suffit à donner envie
    d'ouvrir l'app. `tag` par conversation : les messages suivants remplacent la notification
    précédente au lieu de s'empiler (le Service Worker la re-signale, voir web/push_worker.js)."""
    if not get_settings().push_enabled:
        return
    with SessionLocal() as db:
        match = db.get(Match, match_id)
        if match is None:
            return
        recipient_id = match.user_b_id if match.user_a_id == sender_id else match.user_a_id
        profile = db.get(PublicProfile, sender_id)
        name = profile.display_name if profile and profile.display_name else "quelqu'un"
    send_push_to_user(recipient_id, **message_push(name, match_id))


def message_push(sender_name: str, match_id: uuid.UUID) -> dict:
    # Ne reçoit jamais le message lui-même : impossible, par construction, d'en faire fuiter un
    # extrait dans une notification (tests/test_notifications.py).
    return {
        "title": f"Nouveau message de {sender_name}",
        "body": "Ouvrez Bresonne pour le lire.",
        "category": "messages",
        "url": match_url(match_id),
        "tag": f"match-{match_id}",
    }


def match_url(match_id: uuid.UUID | None) -> str:
    # Lien ouvert au clic sur la notification : l'app lit `?match=` au démarrage (ou le reçoit du
    # Service Worker si elle est déjà ouverte) et ouvre directement cette conversation — voir
    # web/push_worker.js et lib/push/open_match_listener.dart.
    return f"/?match={match_id}" if match_id else "/"


# Une seule fois par personne et par jour, même si le planificateur tourne deux fois (redémarrage,
# deux instances) : verrou Redis SET NX expirant, partagé entre instances, sans table de plus.
_DAILY_REMINDER_LOCK_TTL_SECONDS = 36 * 3600


def users_to_remind_for_daily_question(db: Session, today: date) -> list[uuid.UUID]:
    """Personnes à qui rappeler la question du jour : au moins un match encore voilé (le jeu des
    flammes n'a de sens qu'avant le déblocage) dont elles n'ont pas encore répondu à la question
    du jour, et au moins un abonnement push qui accepte la catégorie « question ». Comptes bannis
    ou supprimés exclus. Le jour est celui de services/messaging.py (`date.today()`, même horloge),
    pour qu'« pas encore répondu » désigne bien la même question que celle que l'app affiche."""
    answered_today = {
        (row.match_id, row.for_user_id)
        for row in db.query(DailyQuestion.match_id, DailyQuestion.for_user_id).filter(
            DailyQuestion.question_date == today, DailyQuestion.answered.is_(True)
        )
    }
    subscribed = {
        user_id
        for (user_id,) in db.query(PushSubscription.user_id)
        .filter(PushSubscription.notify_question.is_(True))
        .distinct()
    }
    if not subscribed:
        return []
    eligible_users = {
        user_id
        for (user_id,) in db.query(User.id).filter(
            User.id.in_(subscribed), User.is_banned.is_(False), User.deleted_at.is_(None)
        )
    }
    to_remind: set[uuid.UUID] = set()
    for match in db.query(Match).filter(Match.unlocked_at.is_(None)):
        for user_id in (match.user_a_id, match.user_b_id):
            if user_id in eligible_users and (match.id, user_id) not in answered_today:
                to_remind.add(user_id)
    return sorted(to_remind)


def send_daily_question_reminders(today: date | None = None) -> list[uuid.UUID]:
    """Appelé une fois par jour par scripts/scheduler.py. Renvoie les personnes réellement
    rappelées (hors doublons évités par le verrou)."""
    if not get_settings().push_enabled:
        return []
    today = today or date.today()
    with SessionLocal() as db:
        user_ids = users_to_remind_for_daily_question(db, today)
    sent: list[uuid.UUID] = []
    client = redis.Redis.from_url(get_settings().redis_url, socket_timeout=2)
    with client:
        for user_id in user_ids:
            key = f"bresonne:push:daily-question:{today.isoformat()}:{user_id}"
            if not client.set(key, "1", nx=True, ex=_DAILY_REMINDER_LOCK_TTL_SECONDS):
                continue
            send_push_to_user(
                user_id,
                title="Votre question du jour vous attend",
                body="Une bonne réponse, et c'est une flamme de plus pour vous deux.",
                category="question",
                url="/",
                tag="daily-question",
            )
            sent.append(user_id)
    return sent
