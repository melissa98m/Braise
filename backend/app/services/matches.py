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
    suffit pour un chat 1-to-1 — voir models/match.py."""
    now = datetime.now(timezone.utc)
    if match.user_a_id == user.id:
        match.last_read_at_a = now
    else:
        match.last_read_at_b = now
    db.commit()
    return now


def message_is_read(match: Match, message: Message) -> bool:
    """Un message est "lu" quand le destinataire (pas l'émetteur) a marqué le match comme lu
    après l'envoi de ce message — ne dépend jamais de qui consulte, contrairement à un "vu par
    moi" par viewer, ce qui garde ce calcul simple et le même pour tout le monde."""
    recipient_last_read = (
        match.last_read_at_b if message.sender_id == match.user_a_id else match.last_read_at_a
    )
    return recipient_last_read is not None and recipient_last_read >= message.created_at
