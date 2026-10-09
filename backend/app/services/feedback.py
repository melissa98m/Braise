from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.models.feedback import Feedback
from app.models.user import User
from app.schemas.feedback import FeedbackIn

# Plafond journalier par personne : de quoi tout dire pendant une session de test, pas de quoi
# remplir la file staff par un script.
MAX_FEEDBACK_PER_DAY = 20


def create_feedback(db: Session, user: User, payload: FeedbackIn, user_agent: str | None) -> Feedback:
    since = datetime.now(timezone.utc) - timedelta(days=1)
    recent = db.query(Feedback).filter(Feedback.user_id == user.id, Feedback.created_at >= since).count()
    if recent >= MAX_FEEDBACK_PER_DAY:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Beaucoup de retours aujourd'hui — merci ! Réessayez demain.",
        )
    feedback = Feedback(
        user_id=user.id,
        category=payload.category,
        message=payload.message.strip(),
        context=payload.context,
        user_agent=(user_agent or "")[:255] or None,
    )
    db.add(feedback)
    db.commit()
    db.refresh(feedback)
    return feedback
