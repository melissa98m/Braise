import uuid
from datetime import datetime, timezone

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.models.match import Match
from app.models.message import Message
from app.models.user import User


def get_match_or_404(db: Session, user: User, match_id: uuid.UUID) -> Match:
    # Un match inexistant et un match qui existe mais n'appartient pas à l'appelant renvoient
    # la même erreur générique — même logique anti-énumération que pour les profils/swipes.
    match = db.get(Match, match_id)
    if match is None or user.id not in (match.user_a_id, match.user_b_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Match introuvable.")
    return match


def other_user_id(match: Match, user: User) -> uuid.UUID:
    return match.user_b_id if match.user_a_id == user.id else match.user_a_id


def mark_read(db: Session, match: Match, user: User) -> datetime:
    """Pose "lu jusqu'à maintenant" côté de l'appelant. Un timestamp par côté (pas par message)
    suffit pour un chat 1-to-1 — voir models/match.py. Fait aussi progresser last_delivered_at_*
    du même côté si besoin : lire un message implique nécessairement l'avoir reçu, donc l'accusé
    de réception ne doit jamais rester en retard sur la lecture, même si le client n'a jamais
    envoyé l'accusé "delivered" explicite (voir mark_delivered)."""
    now = datetime.now(timezone.utc)
    if match.user_a_id == user.id:
        match.last_read_at_a = now
        if match.last_delivered_at_a is None or match.last_delivered_at_a < now:
            match.last_delivered_at_a = now
    else:
        match.last_read_at_b = now
        if match.last_delivered_at_b is None or match.last_delivered_at_b < now:
            match.last_delivered_at_b = now
    db.commit()
    return now


def mark_delivered(db: Session, match: Match, user: User) -> datetime:
    """Pose "reçu jusqu'à maintenant" côté de l'appelant — même forme que mark_read, mais posé dès
    que le client a effectivement reçu la trame WS d'un message plutôt que quand il le marque lu
    (voir api/v1/messaging.py::chat_ws, événement "delivered"). N'écrase jamais un timestamp plus
    récent : un "delivered" en retard (ex. reconnexion après une coupure) ne doit pas faire
    reculer l'accusé de réception."""
    now = datetime.now(timezone.utc)
    if match.user_a_id == user.id:
        if match.last_delivered_at_a is None or match.last_delivered_at_a < now:
            match.last_delivered_at_a = now
    else:
        if match.last_delivered_at_b is None or match.last_delivered_at_b < now:
            match.last_delivered_at_b = now
    db.commit()
    return now


def _recipient_timestamp(match: Match, message: Message, *, field: str) -> datetime | None:
    is_from_a = message.sender_id == match.user_a_id
    return getattr(match, f"{field}_b" if is_from_a else f"{field}_a")


def message_read_at(match: Match, message: Message) -> datetime | None:
    """Heure à laquelle le destinataire (pas l'émetteur) a marqué le match comme lu après l'envoi
    de ce message — ne dépend jamais de qui consulte, contrairement à un "vu par moi" par viewer,
    ce qui garde ce calcul simple et le même pour tout le monde. `None` si pas encore lu."""
    recipient_last_read = _recipient_timestamp(match, message, field="last_read_at")
    if recipient_last_read is not None and recipient_last_read >= message.created_at:
        return recipient_last_read
    return None


def message_is_read(match: Match, message: Message) -> bool:
    return message_read_at(match, message) is not None


def message_delivered_at(match: Match, message: Message) -> datetime | None:
    """Même principe que message_read_at, pour l'accusé de réception plutôt que la lecture."""
    recipient_last_delivered = _recipient_timestamp(match, message, field="last_delivered_at")
    if recipient_last_delivered is not None and recipient_last_delivered >= message.created_at:
        return recipient_last_delivered
    return None


def message_is_delivered(match: Match, message: Message) -> bool:
    return message_delivered_at(match, message) is not None
