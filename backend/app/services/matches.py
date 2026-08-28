import uuid

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.models.match import Match
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
